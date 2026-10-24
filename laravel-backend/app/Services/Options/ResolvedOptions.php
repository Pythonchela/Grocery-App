<?php

namespace App\Services\Options;

/** What a shopper's option picks came to: the unit price and a printable summary. */
final class ResolvedOptions
{
    /**
     * @param  array<int, array<string, mixed>>  $summary  one entry per group that has a pick
     * @param  string  $signature  identical selections share one; used to merge cart lines
     */
    public function __construct(
        public readonly float $unitPrice,
        public readonly array $summary,
        public readonly string $signature,
    ) {}
}
