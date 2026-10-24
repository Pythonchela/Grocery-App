<?php

namespace App\Integrations\Testers;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

/**
 * Checks courier credentials where the provider publishes a safe way to.
 *
 * Only Shiprocket has one today: its login call exchanges the API user's email
 * and password for a token and changes nothing. The other partners do not publish
 * open APIs (they are issued after a commercial agreement), so they report that
 * verification is unavailable rather than guessing at an endpoint.
 */
class CourierTester implements Tester
{
    // Fixed. Never built from input, and deliberately not the configurable
    // base_url: a base URL that an admin session could change would be a place to
    // send the credentials this call carries.
    private const SHIPROCKET_LOGIN = 'https://apiv2.shiprocket.in/v1/external/auth/login';

    public function test(array $values, ?string $target = null): TestResult
    {
        if ($target !== 'shiprocket') {
            return TestResult::unavailable();
        }

        $email = $values['shiprocket_email'] ?? null;
        $password = $values['shiprocket_password'] ?? null;

        if (! is_string($email) || $email === '' || ! is_string($password) || $password === '') {
            return TestResult::incomplete('Enter the Shiprocket email and password to test.');
        }

        try {
            $response = Http::timeout(8)->asJson()->post(self::SHIPROCKET_LOGIN, [
                'email' => $email,
                'password' => $password,
            ]);
        } catch (ConnectionException) {
            return TestResult::failed('Could not reach Shiprocket. Try again in a moment.');
        }

        if ($response->successful() && filled($response->json('token'))) {
            return TestResult::ok('Shiprocket accepted these credentials.');
        }

        return in_array($response->status(), [400, 401, 403, 422], true)
            ? TestResult::failed('Shiprocket rejected these credentials.')
            : TestResult::failed('Shiprocket could not check the credentials right now.');
    }
}
