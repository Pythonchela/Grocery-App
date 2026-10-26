<?php

namespace App\Integrations;

use App\Models\IntegrationSetting;
use App\Services\AIService;
use App\Services\Contracts\LogisticsProvider;
use App\Services\Contracts\ProductParser;
use App\Services\Delivery\CarrierRegistry;
use App\Services\Delivery\DeliveryAllocator;
use Illuminate\Contracts\Encryption\DecryptException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Mail;

/**
 * Admin-managed settings: stored encrypted, applied over the environment at
 * runtime.
 *
 * Precedence: a value an admin set wins; otherwise whatever the environment
 * (.env and the config files' defaults) provided; clearing a value reverts to
 * that. `apply()` snapshots the environment's value the first time it touches a
 * config path, so it can always be put back.
 *
 * What protects the secrets:
 *  - At rest they are Crypt-encrypted (AES-256 with APP_KEY), together with their
 *    own key name, so a ciphertext copied into another row does not decrypt as
 *    something else.
 *  - Only the *encrypted* rows are cached. Plaintext lives in memory for the
 *    length of one process and is never written to the cache, a log or a config
 *    cache file. apply() runs from HTTP middleware and at the start of console
 *    commands, but never for the commands that compile config
 *    (see NEVER_APPLY_COMMANDS), so `php artisan config:cache` cannot embed a
 *    decrypted secret in bootstrap/cache/config.php.
 *  - Nothing here ever returns a secret to the caller except `value()`, which is
 *    for server-side use and is not wired to any response.
 *  - An undecryptable row (APP_KEY changed) is treated as not set, so the
 *    environment's value takes over rather than the app breaking.
 */
class IntegrationSettings
{
    private const CACHE_KEY = 'integrations.rows';

    /**
     * Console commands that must never see the overlay: the ones that write config
     * to disk (a cached config would hold every secret in plaintext), and the ones
     * that run before the settings table necessarily exists.
     */
    public const NEVER_APPLY_COMMANDS = [
        'config:cache', 'optimize', 'key:generate', 'package:discover',
        'migrate', 'migrate:fresh', 'migrate:refresh', 'migrate:reset', 'migrate:rollback', 'migrate:install',
    ];

    /** Changes take effect within this many seconds on every server. */
    private const CACHE_TTL = 60;

    /** @var array<string, mixed> config() path => the environment's own value */
    private array $original = [];

    /** @var array<string, true> */
    private array $unreadable = [];

    // ── Reading ─────────────────────────────────────────────────────────

    /**
     * The stored rows, still encrypted.
     *
     * @return array<string, string>
     */
    public function rows(): array
    {
        return Cache::remember(self::CACHE_KEY, self::CACHE_TTL, fn () => IntegrationSetting::query()->pluck('value', 'key')->all());
    }

    public function forgetRows(): void
    {
        Cache::forget(self::CACHE_KEY);
    }

    /** What the server's own configuration holds for a field, ignoring any admin value. */
    public function environmentValue(Field $field): mixed
    {
        return array_key_exists($field->config[0], $this->original) ? $this->original[$field->config[0]] : config($field->config[0]);
    }

    /** Whether an admin has set this field (as opposed to the environment providing it). */
    public function has(Field $field): bool
    {
        return $this->value($field) !== null;
    }

    /**
     * The decrypted value an admin set, or null. Server-side use only.
     */
    public function value(Field $field): mixed
    {
        $payload = $this->rows()[$field->key()] ?? null;

        return $payload === null ? null : $this->open($field->key(), $payload);
    }

    // ── Applying ────────────────────────────────────────────────────────

    /**
     * Put the admin's values into config(), and restore the environment's for
     * anything the admin has not set. Idempotent and cheap after the first call.
     */
    public function apply(): void
    {
        $fields = Registry::fields();

        // Snapshot first, for every path, before anything is overwritten.
        foreach ($fields as $field) {
            foreach ($field->config as $path) {
                if (! array_key_exists($path, $this->original)) {
                    $this->original[$path] = config($path);
                }
            }
        }

        foreach ($fields as $field) {
            $value = $this->value($field);

            foreach ($field->config as $path) {
                config([$path => $value === null ? $this->original[$path] : $field->cast($value)]);
            }
        }

        $this->derive();
    }

    /**
     * Settings that follow from others rather than being entered.
     *
     * On S3 no `visibility` may be set: it would make every upload ask for a
     * public-read ACL, which buckets created since 2023 (ACLs disabled) reject.
     * Public reads come from the bucket policy or CDN instead. On the local disk
     * the public files keep the visibility they always had. Path-style addressing
     * is what every S3-compatible service accepts, so it follows from an endpoint
     * being set.
     */
    private function derive(): void
    {
        foreach (['media' => 'public'] as $disk => $localVisibility) {
            $s3 = config("filesystems.disks.{$disk}.driver") === 's3';

            config([
                "filesystems.disks.{$disk}.visibility" => $s3 ? null : $localVisibility,
                "filesystems.disks.{$disk}.use_path_style_endpoint" => $s3 && filled(config("filesystems.disks.{$disk}.endpoint")),
            ]);
        }

        // Storage::url() follows the driver. On S3 it is the bucket's public address;
        // on the server disk it is this app, so an address saved for a bucket can never
        // leak onto local files if the admin switches back.
        config(['filesystems.disks.media.url' => config('filesystems.disks.media.driver') === 's3'
            ? (config('filesystems.disks.media.public_url') ?: config('filesystems.disks.media.url'))
            : rtrim((string) config('app.url'), '/').'/storage']);
    }

    // ── Writing ─────────────────────────────────────────────────────────

    public function set(Field $field, mixed $value, ?string $userId = null): void
    {
        IntegrationSetting::query()->updateOrCreate(
            ['key' => $field->key()],
            ['value' => $this->seal($field->key(), $value), 'updated_by' => $userId],
        );

        $this->changed();
    }

    public function clear(Field $field): void
    {
        IntegrationSetting::query()->where('key', $field->key())->delete();

        $this->changed();
    }

    /**
     * Something changed: drop the cache, re-apply, and throw away every service
     * that copied its settings at construction — otherwise it keeps using the old
     * credentials until the process ends.
     */
    public function changed(): void
    {
        $this->forgetRows();
        $this->unreadable = [];
        $this->apply();

        foreach ([AIService::class, ProductParser::class, CarrierRegistry::class, DeliveryAllocator::class, LogisticsProvider::class] as $abstract) {
            app()->forgetInstance($abstract);
        }

        // The mailer and the storage disks are built once and then reused, so they
        // would keep the old credentials just as the services above would.
        app()->forgetInstance('mail.manager');
        Mail::clearResolvedInstance('mail.manager');
        app('filesystem')->forgetDisk(['media']);
    }

    // ── What the admin screen shows ─────────────────────────────────────

    /**
     * Everything the UI may know about a field. **Never a secret.**
     *
     * @return array<string, mixed>
     */
    public function describe(Field $field): array
    {
        $stored = $this->value($field);
        $effective = $stored ?? config($field->config[0]);
        $isSet = $field->cast === 'list' ? ! empty($effective) : filled($effective);

        return [
            'key' => $field->key(),
            'name' => $field->name,
            'label' => $field->label,
            'type' => $field->type,
            'secret' => $field->isSecret(),
            'help' => $field->help,
            'placeholder' => $field->placeholder,
            'options' => $field->options,
            'is_set' => $isSet,
            // admin: set here; environment: provided by the server's .env/config
            'source' => $stored !== null ? 'admin' : ($isSet ? 'environment' : 'unset'),
            // The last four characters of an admin-set secret, and only when it is
            // long enough that four characters give nothing away.
            'masked' => $field->isSecret() && $stored !== null ? $this->mask((string) $stored) : null,
            // Non-secret settings are shown in full so they can be edited.
            'value' => $field->isSecret() ? null : $effective,
            // The row exists but APP_KEY can no longer open it.
            'unreadable' => isset($this->unreadable[$field->key()]),
        ];
    }

    /** 'configured' | 'partial' | 'missing' — for the status badge. */
    public function status(Group $group): string
    {
        $set = fn (string $name) => ($f = $group->field($name)) !== null && $this->describe($f)['is_set'];

        return match ($group->id) {
            'gemini' => $set('api_key') ? 'configured' : 'missing',
            'push' => $set('service_account') ? 'configured' : 'missing',
            'google' => count(array_filter(['client_id', 'web_client_id', 'android_client_id', 'ios_client_id'], $set)) > 0 ? 'configured' : 'missing',
            'couriers' => $this->courierStatus($set),
            'email' => $this->emailStatus($group),
            'sms' => $this->smsStatus($group, $set),
            'storage' => $this->storageStatus($group, $set),
            default => 'configured', // shipping always has defaults
        };
    }

    private function chosen(Group $group, string $name): ?string
    {
        $field = $group->field($name);

        return $field ? (string) ($this->value($field) ?? config($field->config[0])) : null;
    }

    private function emailStatus(Group $group): string
    {
        return $this->chosen($group, 'mailer') === 'smtp' ? 'configured' : 'missing';
    }

    private function smsStatus(Group $group, callable $set): string
    {
        return match ($this->chosen($group, 'driver')) {
            'msg91' => $set('msg91_authkey') && $set('msg91_template_otp') ? 'configured' : 'partial',
            'twilio' => $set('twilio_sid') && $set('twilio_token') && $set('twilio_from') ? 'configured' : 'partial',
            default => 'missing',
        };
    }

    /** 'local' is a working state, but the one to move off before going live. */
    private function storageStatus(Group $group, callable $set): string
    {
        if ($this->chosen($group, 'driver') !== 's3') {
            return 'local';
        }

        return $set('bucket') && $set('public_url') && $set('access_key') && $set('secret_key') ? 'configured' : 'partial';
    }

    private function courierStatus(callable $set): string
    {
        $live = (int) ($set('shiprocket_email') && $set('shiprocket_password'))
            + (int) $set('delhivery_api_token')
            + (int) ($set('ola_client_id') && $set('ola_client_secret'))
            + (int) ($set('rapido_client_id') && $set('rapido_client_secret'))
            + (int) $set('porter_api_key');

        return $live === 0 ? 'missing' : 'configured';
    }

    public function mask(string $secret): ?string
    {
        return strlen($secret) >= 16 ? '••••'.substr($secret, -4) : null;
    }

    /**
     * A short keyed hash of a value, so the audit log can show that something
     * changed — and whether two changes were to the same value — without ever
     * holding the value. Keyed with APP_KEY, so it cannot be brute-forced offline
     * from a leaked log.
     */
    public function fingerprint(mixed $value): string
    {
        return substr(hash_hmac('sha256', (string) json_encode($value), (string) config('app.key')), 0, 16);
    }

    // ── Sealing ─────────────────────────────────────────────────────────

    private function seal(string $key, mixed $value): string
    {
        return Crypt::encryptString((string) json_encode(['k' => $key, 'v' => $value]));
    }

    /** Null when the payload cannot be opened or belongs to another key. */
    private function open(string $key, string $payload): mixed
    {
        try {
            $data = json_decode(Crypt::decryptString($payload), true);
        } catch (DecryptException) {
            $this->unreadable[$key] = true;

            return null;
        }

        // A ciphertext copied from another row decrypts fine but is for another
        // setting. Refuse it rather than use a secret in the wrong place.
        if (! is_array($data) || ($data['k'] ?? null) !== $key) {
            $this->unreadable[$key] = true;

            return null;
        }

        return $data['v'] ?? null;
    }
}
