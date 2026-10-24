<?php

namespace App\Integrations\Testers;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

/**
 * Lists the models available to the key — a read-only call that costs nothing
 * and fails clearly for a bad key. The key travels in a header, never the URL, so
 * it cannot end up in a logged exception message.
 */
class GeminiTester implements Tester
{
    // Fixed. Never built from input.
    private const ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

    public function test(array $values, ?string $target = null): TestResult
    {
        $key = $values['api_key'] ?? null;

        if (! is_string($key) || trim($key) === '') {
            return TestResult::incomplete('Enter an API key to test.');
        }

        try {
            $response = Http::timeout(8)
                ->withHeaders(['x-goog-api-key' => $key])
                ->get(self::ENDPOINT, ['pageSize' => 1]);
        } catch (ConnectionException) {
            return TestResult::failed('Could not reach Google. Try again in a moment.');
        }

        return match (true) {
            $response->successful() => TestResult::ok('Google accepted this key.'),
            in_array($response->status(), [400, 401, 403], true) => TestResult::failed('Google rejected this key. Check it was copied in full.'),
            $response->status() === 429 => TestResult::failed('Google is rate limiting this key. Try again shortly.'),
            default => TestResult::failed('Google could not check the key right now.'),
        };
    }
}
