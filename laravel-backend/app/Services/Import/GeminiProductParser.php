<?php

namespace App\Services\Import;

use Illuminate\Support\Facades\Log;

/**
 * The AI driver for the plain-text import contract. Used when a Gemini key is set;
 * on any failure (no key, network error, unusable answer) it hands the text to the
 * built-in reader, so pasting a list never hard-fails.
 *
 * The photo, PDF and document upload goes through {@see ProductImporter}; this class
 * is what answers `ProductParser` for code that only has a string.
 */
class GeminiProductParser extends HeuristicProductParser
{
    public function parse(string $raw, array $context = []): array
    {
        $extractor = new AiProductExtractor(new GeminiClient());

        if (! $extractor->available() || trim($raw) === '') {
            return parent::parse($raw, $context);
        }

        // A table with named columns needs no model: it is read exactly.
        $exact = parent::parse($raw, $context);
        if ($exact['structured'] ?? false) {
            return $exact;
        }

        try {
            $found = $extractor->extract(
                ['texts' => [['name' => 'Pasted text', 'text' => $raw, 'tabular' => false]], 'media' => []],
                $context,
            );
        } catch (\Throwable $e) {
            Log::warning('[GeminiProductParser] falling back to the built-in reader: '.$e->getMessage());

            return $exact;
        }

        if ($found['records'] === []) {
            return $exact;
        }

        $rows = (new ImportRowFactory())->rows($found['records'], $context['categories'] ?? [], (int) ($context['default_stock'] ?? 10));

        return ['rows' => $rows, 'format' => 'document', 'driver' => 'gemini', 'structured' => true];
    }

    protected function driverName(): string
    {
        return 'gemini';
    }
}
