<?php

namespace App\Integrations\Testers;

use App\Services\Push\FcmClient;

/**
 * Trades the service account's signed request for an access token at Google. That
 * proves the key is real and not revoked without sending anyone a notification,
 * and only ever contacts Google's fixed token endpoint.
 */
class PushTester implements Tester
{
    public function test(array $values, ?string $target = null): TestResult
    {
        $json = $values['service_account'] ?? null;

        if (! is_string($json) || trim($json) === '') {
            return TestResult::incomplete('Paste the service account JSON to test.');
        }

        if (FcmClient::parseServiceAccount($json) === null) {
            return TestResult::failed('That is not a Firebase service account file. It must contain project_id, client_email and private_key.');
        }

        // Test the candidate values, not whatever is currently saved.
        config(['services.fcm.service_account' => $json]);

        return match ((new FcmClient)->check()) {
            'ok' => TestResult::ok('Google accepted this service account.'),
            'unreachable' => TestResult::failed('Could not reach Google. Try again in a moment.'),
            default => TestResult::failed('Google rejected this service account. Download a fresh key from Firebase and paste it in full.'),
        };
    }
}
