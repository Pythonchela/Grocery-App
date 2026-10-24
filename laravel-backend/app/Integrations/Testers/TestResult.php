<?php

namespace App\Integrations\Testers;

/** The outcome of a connection test: a verdict and a message safe to show an admin. */
final class TestResult
{
    private function __construct(
        public readonly string $status, // ok | failed | unavailable | incomplete
        public readonly string $message,
    ) {}

    public static function ok(string $message = 'Connected successfully.'): self
    {
        return new self('ok', $message);
    }

    public static function failed(string $message): self
    {
        return new self('failed', $message);
    }

    /** This integration cannot be verified live (yet). Not an error. */
    public static function unavailable(string $message = 'Saved. Live verification is not available for this integration yet.'): self
    {
        return new self('unavailable', $message);
    }

    /** Not enough information to test. */
    public static function incomplete(string $message): self
    {
        return new self('incomplete', $message);
    }

    public function passed(): bool
    {
        return $this->status === 'ok';
    }

    /** @return array{status: string, message: string} */
    public function toArray(): array
    {
        return ['status' => $this->status, 'message' => $this->message];
    }
}
