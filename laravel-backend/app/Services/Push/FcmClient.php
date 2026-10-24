<?php

namespace App\Services\Push;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * Firebase Cloud Messaging, HTTP v1.
 *
 * Authenticates as the Firebase project's service account: a signed JWT is traded
 * at Google for a short-lived access token, which is cached until shortly before
 * it expires. The hosts are fixed constants - nothing here is ever built from a
 * request - and no part of the credential is logged or returned.
 */
class FcmClient
{
    private const TOKEN_URL = 'https://oauth2.googleapis.com/token';

    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    private const SEND_URL = 'https://fcm.googleapis.com/v1/projects/%s/messages:send';

    /** @var array{project_id: string, client_email: string, private_key: string}|null */
    private ?array $account = null;

    private bool $accountRead = false;

    /** True when a usable service account has been configured. */
    public function configured(): bool
    {
        return $this->account() !== null;
    }

    /**
     * Send one message to one device.
     *
     * @param  array<string, mixed>  $data  Delivered alongside the notification;
     *                                      FCM requires string values, so they are coerced.
     * @return 'sent'|'invalid_token'|'failed'
     */
    public function send(string $deviceToken, string $title, ?string $body, array $data = []): string
    {
        $account = $this->account();
        if ($account === null) {
            return 'failed';
        }

        try {
            $response = Http::timeout(8)
                ->withToken($this->accessToken($account))
                ->acceptJson()
                ->post(sprintf(self::SEND_URL, $account['project_id']), [
                    'message' => [
                        'token' => $deviceToken,
                        'notification' => array_filter(['title' => $title, 'body' => $body]),
                        'data' => $this->stringify($data),
                        'android' => ['priority' => 'HIGH'],
                    ],
                ]);
        } catch (ConnectionException|RuntimeException) {
            return 'failed';
        }

        if ($response->successful()) {
            return 'sent';
        }

        // 404 UNREGISTERED: the app was uninstalled or the token rotated.
        // 400 INVALID_ARGUMENT on the token field: it was never valid.
        $status = $response->json('error.status');
        if ($response->status() === 404 || $status === 'UNREGISTERED' || $status === 'INVALID_ARGUMENT') {
            return 'invalid_token';
        }

        return 'failed';
    }

    /**
     * Verify the credentials by asking Google for an access token. Sends nothing.
     *
     * @return 'ok'|'rejected'|'unreachable'|'missing'
     */
    public function check(): string
    {
        $account = $this->account();
        if ($account === null) {
            return 'missing';
        }

        try {
            $this->accessToken($account, fresh: true);

            return 'ok';
        } catch (ConnectionException) {
            return 'unreachable';
        } catch (RuntimeException) {
            return 'rejected';
        }
    }

    /**
     * @param  array{project_id: string, client_email: string, private_key: string}  $account
     */
    private function accessToken(array $account, bool $fresh = false): string
    {
        $cacheKey = 'fcm.access_token.'.sha1($account['client_email']);

        if (! $fresh && ($cached = Cache::get($cacheKey))) {
            return $cached;
        }

        $now = time();
        $jwt = $this->signedJwt($account, [
            'iss' => $account['client_email'],
            'scope' => self::SCOPE,
            'aud' => self::TOKEN_URL,
            'iat' => $now,
            'exp' => $now + 3600,
        ]);

        $response = Http::timeout(8)->asForm()->post(self::TOKEN_URL, [
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt,
        ]);

        $token = $response->successful() ? $response->json('access_token') : null;
        if (! is_string($token) || $token === '') {
            throw new RuntimeException('Google did not issue an access token.');
        }

        // Refresh a few minutes early rather than risk sending with an expired one.
        Cache::put($cacheKey, $token, max(60, ((int) $response->json('expires_in', 3600)) - 300));

        return $token;
    }

    /**
     * @param  array{project_id: string, client_email: string, private_key: string}  $account
     * @param  array<string, mixed>  $claims
     */
    private function signedJwt(array $account, array $claims): string
    {
        $encode = fn (string $raw) => rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');

        $unsigned = $encode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']))
            .'.'.$encode(json_encode($claims));

        $key = openssl_pkey_get_private($account['private_key']);
        if ($key === false || ! openssl_sign($unsigned, $signature, $key, OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('The service account key could not be used to sign.');
        }

        return $unsigned.'.'.$encode($signature);
    }

    /**
     * @return array{project_id: string, client_email: string, private_key: string}|null
     */
    private function account(): ?array
    {
        if ($this->accountRead) {
            return $this->account;
        }
        $this->accountRead = true;

        return $this->account = self::parseServiceAccount((string) config('services.fcm.service_account'));
    }

    /**
     * Pull the three fields we need out of a service-account JSON document.
     *
     * @return array{project_id: string, client_email: string, private_key: string}|null
     */
    public static function parseServiceAccount(string $json): ?array
    {
        if (trim($json) === '') {
            return null;
        }

        $decoded = json_decode($json, true);
        if (! is_array($decoded)) {
            return null;
        }

        foreach (['project_id', 'client_email', 'private_key'] as $field) {
            if (! isset($decoded[$field]) || ! is_string($decoded[$field]) || $decoded[$field] === '') {
                return null;
            }
        }

        return [
            'project_id' => $decoded['project_id'],
            'client_email' => $decoded['client_email'],
            // Pasted through a single-line field, the key's line breaks can arrive
            // as the two characters "\n"; PEM needs real ones.
            'private_key' => str_replace('\\n', "\n", $decoded['private_key']),
        ];
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array<string, string>
     */
    private function stringify(array $data): array
    {
        $out = [];
        foreach ($data as $key => $value) {
            if ($value === null) {
                continue;
            }
            $out[(string) $key] = is_scalar($value) ? (string) $value : json_encode($value);
        }

        return $out;
    }
}
