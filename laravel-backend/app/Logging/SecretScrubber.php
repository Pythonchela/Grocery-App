<?php

namespace App\Logging;

use App\Integrations\Registry;

/**
 * Removes credentials from text on its way to a log file or an error tracker.
 *
 * A credential can reach either without anyone meaning it to: an HTTP client
 * exception quotes the request URL, a provider echoes a request back in an error,
 * a developer logs a whole payload. Scrubbing the finished text catches all of
 * those. One implementation, so the log files and Sentry cannot drift apart.
 */
final class SecretScrubber
{
    public const MASK = '[redacted]';

    /** Anything shorter could be a coincidence in ordinary text. */
    private const MIN_LENGTH = 8;

    /** Config paths that hold credentials but are not managed from the admin panel. */
    private const EXTRA = [
        'services.razorpay.key_secret',
        'services.razorpay.webhook_secret',
        'app.key',
        'sentry.dsn',
    ];

    public static function scrub(string $text): string
    {
        // Credentials in a URL's query string or an Authorization header.
        // Not only after a "?" or "&": a bare query string (Sentry's own field) starts
        // with the name. The lookbehind stops "monkey=" matching "key=".
        $text = preg_replace('/(?<![A-Za-z0-9])((?:key|api_key|apikey|token|access_token|client_secret|authkey)=)[^&\s"\'\\\\]+/i', '$1'.self::MASK, $text) ?? $text;
        $text = preg_replace('/(authorization["\']?\s*[:=]\s*["\']?(?:bearer|basic)\s+)[A-Za-z0-9._~+\/=-]+/i', '$1'.self::MASK, $text) ?? $text;

        // Any secret the app currently holds, wherever it turns up.
        foreach (self::secrets() as $secret) {
            $text = str_replace($secret, self::MASK, $text);
        }

        return $text;
    }

    /** @return list<string> */
    public static function secrets(): array
    {
        $paths = self::EXTRA;

        foreach (Registry::fields() as $field) {
            if ($field->isSecret()) {
                array_push($paths, ...$field->config);
            }
        }

        $found = [];

        foreach (array_unique($paths) as $path) {
            $value = config($path);

            // app.key is "base64:…"; the raw key is what would be quoted too.
            if (is_string($value) && str_starts_with($value, 'base64:')) {
                $found[] = substr($value, 7);
            }

            if (is_string($value) && strlen($value) >= self::MIN_LENGTH) {
                $found[] = $value;
            }
        }

        // Longest first, so a secret that contains another is replaced whole.
        usort($found, fn ($a, $b) => strlen($b) <=> strlen($a));

        return $found;
    }
}
