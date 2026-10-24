<?php

namespace App\Logging;

use Monolog\Formatter\FormatterInterface;
use Monolog\LogRecord;

/** Wraps a formatter and scrubs what it produced. */
class RedactingFormatter implements FormatterInterface
{
    public const MASK = SecretScrubber::MASK;

    public function __construct(private readonly FormatterInterface $inner) {}

    public function format(LogRecord $record): mixed
    {
        $line = $this->inner->format($record);

        return is_string($line) ? SecretScrubber::scrub($line) : $line;
    }

    public function formatBatch(array $records): mixed
    {
        $out = $this->inner->formatBatch($records);

        return is_string($out) ? SecretScrubber::scrub($out) : $out;
    }
}
