<?php

namespace App\Monitoring;

use App\Logging\SecretScrubber;
use Sentry\Breadcrumb;
use Sentry\Event;
use Sentry\EventHint;

/**
 * The last stop before an error report leaves the server.
 *
 * An error tracker is a third party, and what reaches it is whatever the exception
 * happened to contain. So every event passes through here first: secrets are removed
 * from messages, stack-trace text and URLs; request bodies and cookies are dropped;
 * authorization headers are dropped; function arguments are dropped from stack frames.
 * A report needs none of that to say what failed and where.
 *
 * Referenced from config/sentry.php as [class, method] arrays (closures would stop
 * `config:cache` working).
 */
class SentryScrubber
{
    /** Headers that carry a credential or a session. */
    private const SENSITIVE_HEADERS = ['authorization', 'cookie', 'set-cookie', 'x-xsrf-token', 'x-csrf-token', 'x-api-key', 'proxy-authorization'];

    public static function beforeSend(Event $event, ?EventHint $hint = null): ?Event
    {
        if (($message = $event->getMessage()) !== null) {
            $event->setMessage(SecretScrubber::scrub($message));
        }

        foreach ($event->getExceptions() as $exception) {
            $exception->setValue(SecretScrubber::scrub($exception->getValue()));

            // Frame variables are function arguments: a password or a key passed to a
            // function shows up here even when it is in no message.
            foreach ($exception->getStacktrace()?->getFrames() ?? [] as $frame) {
                $frame->setVars([]);
            }
        }

        $event->setRequest(self::request($event->getRequest()));
        $event->setExtra(self::deep($event->getExtra()));

        return $event;
    }

    public static function beforeBreadcrumb(Breadcrumb $breadcrumb): ?Breadcrumb
    {
        if (($message = $breadcrumb->getMessage()) !== null) {
            $breadcrumb = $breadcrumb->withMessage(SecretScrubber::scrub($message));
        }

        foreach ($breadcrumb->getMetadata() as $key => $value) {
            $breadcrumb = $breadcrumb->withMetadata($key, self::deep($value));
        }

        return $breadcrumb;
    }

    /**
     * @param  array<string, mixed>  $request
     * @return array<string, mixed>
     */
    private static function request(array $request): array
    {
        // Bodies and cookies are never wanted; drop rather than scrub.
        unset($request['data'], $request['cookies']);

        foreach (['url', 'query_string'] as $key) {
            if (isset($request[$key]) && is_string($request[$key])) {
                $request[$key] = SecretScrubber::scrub($request[$key]);
            }
        }

        if (isset($request['headers']) && is_array($request['headers'])) {
            $request['headers'] = array_filter(
                $request['headers'],
                fn ($name) => ! in_array(strtolower((string) $name), self::SENSITIVE_HEADERS, true),
                ARRAY_FILTER_USE_KEY,
            );
        }

        return $request;
    }

    /** Scrub every string inside a value of any shape. */
    private static function deep(mixed $value): mixed
    {
        if (is_string($value)) {
            return SecretScrubber::scrub($value);
        }

        if (is_array($value)) {
            return array_map(fn ($v) => self::deep($v), $value);
        }

        return $value;
    }
}
