<?php

namespace App\Services\Import;

use App\Services\Contracts\ProductParser;
use App\Support\ProductDetails;
use Illuminate\Support\Str;

/**
 * Deterministic product parser. Detects the input shape (JSON / delimited /
 * markdown table / freeform prose), maps whatever column names the source used
 * onto our schema via fuzzy matching, and pulls prices, variants and tags out
 * of unstructured text.
 *
 * This is the default driver: it needs no API key and no network, so bulk
 * import works out of the box. GeminiProductParser takes over when a key is
 * configured and falls back to this one on any failure.
 */
class HeuristicProductParser implements ProductParser
{
    /** Accepted spellings for each target field, lowercased and de-punctuated. */
    private const FIELD_ALIASES = [
        'title' => ['title', 'name', 'product', 'productname', 'producttitle', 'item', 'itemname'],
        'description' => ['description', 'desc', 'details', 'about', 'longdescription', 'body', 'summary'],
        'price' => ['price', 'sellingprice', 'offerprice', 'saleprice', 'ourprice', 'finalprice', 'sp'],
        'mrp' => ['mrp', 'listprice', 'originalprice', 'maximumretailprice', 'wasprice', 'compareatprice', 'retailprice'],
        'brand' => ['brand', 'make', 'manufacturer', 'vendor', 'label'],
        'category' => ['category', 'categoryname', 'cat', 'department', 'type', 'collection'],
        'sku' => ['sku', 'code', 'itemcode', 'productcode', 'barcode', 'ean'],
        'stock' => ['stock', 'qty', 'quantity', 'inventory', 'available', 'stockcount', 'units'],
        'images' => ['image', 'images', 'imageurl', 'imageurls', 'photo', 'photos', 'picture', 'thumbnail'],
        'tags' => ['tags', 'keywords', 'features', 'badges', 'highlights', 'labels'],
        'color' => ['color', 'colour', 'shade'],
        'size' => ['size', 'sizes', 'variant', 'variants', 'option', 'options'],
    ];

    private const REQUIRED = ['title', 'price'];

    /** Stock given to a product whose source does not say. The owner sets it in the import screen. */
    protected int $defaultStock = 10;

    /** Whether the last parse found named columns (or JSON) rather than guessing. */
    protected bool $structured = false;

    public function parse(string $raw, array $context = []): array
    {
        $raw = trim($raw);
        $categories = $context['categories'] ?? [];
        $this->defaultStock = max(0, (int) ($context['default_stock'] ?? 10));
        $this->structured = false;

        if ($raw === '') {
            return ['rows' => [], 'format' => 'empty', 'driver' => $this->driverName(), 'structured' => false];
        }

        [$format, $records] = $this->detectAndExtract($raw);

        $rows = [];
        foreach ($records as $i => $record) {
            $rows[] = $this->normaliseRow($record, $i, $categories);
        }

        return ['rows' => $rows, 'format' => $format, 'driver' => $this->driverName(), 'structured' => $this->structured];
    }

    /**
     * Drops title lines above a table ("Price list 2026", a shop name, blank
     * rows) so the header row is the first line. Unchanged when no header is
     * found in the first fifteen lines.
     */
    public function stripPreamble(string $raw): string
    {
        $lines = preg_split('/\r\n|\r|\n/', $raw);

        foreach (array_slice($lines, 0, 15, true) as $i => $line) {
            foreach (["\t", ',', ';', '|'] as $delim) {
                $cells = $delim === ',' ? str_getcsv($line) : explode($delim, $line);
                $named = count(array_filter(array_map(fn ($c) => $this->matchField(trim((string) $c, " \t\"'|")), $cells)));

                if ($named >= 2) {
                    return implode("\n", array_slice($lines, $i));
                }
            }
        }

        return $raw;
    }

    protected function driverName(): string
    {
        return 'heuristic';
    }

    // ── Format detection ─────────────────────────────────────────────────

    private function detectAndExtract(string $raw): array
    {
        // JSON array or single object.
        $json = json_decode($raw, true);
        if (json_last_error() === JSON_ERROR_NONE && is_array($json)) {
            $records = array_is_list($json) ? $json : [$json];
            // Only treat as JSON records if entries are associative.
            if ($records && is_array(reset($records))) {
                $this->structured = true;

                return ['json', $records];
            }
        }

        $lines = preg_split('/\r\n|\r|\n/', $raw);
        $lines = array_values(array_filter(array_map('trim', $lines), fn ($l) => $l !== ''));

        // Markdown table: | Title | Price | ... with a --- separator row.
        if (count($lines) >= 2 && str_starts_with($lines[0], '|') && preg_match('/^\|[\s:|-]+\|$/', $lines[1] ?? '')) {
            return ['markdown', $this->fromDelimited($lines, '|', true)];
        }

        // Delimited (CSV / TSV / semicolon / pipe) — needs a consistent
        // delimiter count across the first few lines to avoid false positives
        // on prose that happens to contain a comma.
        foreach (["\t", ',', ';', '|'] as $delim) {
            if ($this->looksDelimited($lines, $delim)) {
                return [$delim === "\t" ? 'tsv' : 'delimited', $this->fromDelimited($lines, $delim, false)];
            }
        }

        // Freeform: blank-line-separated blocks, or one product per line.
        return ['freeform', $this->fromFreeform($raw)];
    }

    private function looksDelimited(array $lines, string $delim): bool
    {
        if (count($lines) < 2) {
            return false;
        }

        $counts = array_map(fn ($l) => substr_count($l, $delim), array_slice($lines, 0, 5));
        $first = $counts[0];

        return $first >= 1 && count(array_unique($counts)) === 1;
    }

    private function fromDelimited(array $lines, string $delim, bool $markdown): array
    {
        $split = function (string $line) use ($delim, $markdown) {
            if ($markdown) {
                $line = trim($line, '|');
            }
            $parts = $delim === ',' ? str_getcsv($line) : explode($delim, $line);

            return array_map(fn ($p) => trim((string) $p, " \t\"'"), $parts);
        };

        $header = $split($lines[0]);
        $body = array_slice($lines, $markdown ? 2 : 1);

        // Header row must actually name fields we recognise; otherwise treat
        // the first line as data with positional columns.
        $mapped = array_map(fn ($h) => $this->matchField($h), $header);
        $recognised = count(array_filter($mapped));

        $records = [];
        if ($recognised >= 2) {
            $this->structured = true;
            foreach ($body as $line) {
                $cells = $split($line);
                $record = [];
                foreach ($mapped as $i => $field) {
                    if ($field !== null && isset($cells[$i]) && $cells[$i] !== '') {
                        $record[$field] = $cells[$i];
                    }
                }
                if ($record) {
                    $records[] = $record;
                }
            }
        } else {
            // No usable header — assume title, price, mrp, category order.
            $positional = ['title', 'price', 'mrp', 'category'];
            foreach ($lines as $line) {
                $cells = $split($line);
                $record = [];
                foreach ($positional as $i => $field) {
                    if (isset($cells[$i]) && $cells[$i] !== '') {
                        $record[$field] = $cells[$i];
                    }
                }
                if ($record) {
                    $records[] = $record;
                }
            }
        }

        return $records;
    }

    /** Prose blocks — one product per paragraph, or per line if no blanks. */
    private function fromFreeform(string $raw): array
    {
        $blocks = preg_split('/\n\s*\n/', $raw);
        $blocks = array_values(array_filter(array_map('trim', $blocks), fn ($b) => $b !== ''));

        if (count($blocks) === 1) {
            $lines = array_values(array_filter(array_map('trim', explode("\n", $blocks[0])), fn ($l) => $l !== ''));
            if (count($lines) > 1) {
                $blocks = $lines;
            }
        }

        return array_map(fn ($b) => ['_freeform' => $b], $blocks);
    }

    // ── Row normalisation ────────────────────────────────────────────────

    protected function normaliseRow(array $record, int $index, array $categories): array
    {
        $issues = [];
        $confidence = [];

        if (isset($record['_freeform'])) {
            $record = $this->extractFromProse($record['_freeform'], $confidence);
        } else {
            // Structured input: keys came from a recognised header.
            foreach (array_keys($record) as $k) {
                $confidence[$k] = 0.95;
            }
        }

        $title = $this->cleanText($record['title'] ?? '');
        $price = $this->toNumber($record['price'] ?? null);
        $mrp = $this->toNumber($record['mrp'] ?? null);

        if ($title === '') {
            $issues[] = 'Missing product title.';
        }
        if ($price === null) {
            $issues[] = 'Missing or unreadable price.';
        }

        // MRP below price is almost always the two being swapped.
        if ($price !== null && $mrp !== null && $mrp < $price) {
            [$price, $mrp] = [$mrp, $price];
            $issues[] = 'MRP was lower than price — values swapped, please confirm.';
            $confidence['price'] = 0.5;
            $confidence['mrp'] = 0.5;
        }

        if ($mrp === null && $price !== null) {
            $mrp = $price;
            $confidence['mrp'] = 0.3;
        }

        [$categoryId, $categoryName, $catConfidence] = $this->matchCategory($record['category'] ?? null, $categories);
        if ($categoryId === null) {
            $issues[] = $categoryName
                ? "Category \"{$categoryName}\" didn't match an existing category — pick one below."
                : 'No category detected — pick one below.';
        }
        $confidence['category'] = $catConfidence;

        $variants = $this->buildVariants($record);
        $images = $this->toList($record['images'] ?? null);
        foreach ($images as $img) {
            if (! filter_var($img, FILTER_VALIDATE_URL)) {
                $issues[] = "Image doesn't look like a valid URL: {$img}";
                break;
            }
        }

        // Fields the model itself was unsure about are shown as such.
        foreach ((array) ($record['unsure'] ?? []) as $field) {
            if (is_string($field) && $field !== '') {
                $confidence[$field] = min($confidence[$field] ?? 1.0, 0.4);
            }
        }

        $weight = $this->toNumber($record['weight_grams'] ?? null);

        return [
            'index' => $index,
            'title' => $title,
            'slug' => $title !== '' ? Str::slug($title) : '',
            'description' => $this->cleanText($record['description'] ?? ''),
            'brand' => $this->cleanText($record['brand'] ?? '') ?: null,
            'price' => $price,
            'mrp' => $mrp,
            'category_id' => $categoryId,
            'category_hint' => $categoryName,
            'images' => $images,
            'tags' => $this->toList($record['tags'] ?? null),
            'variants' => $variants,
            'features' => $this->toBullets($record['features'] ?? null),
            'specifications' => ProductDetails::specifications(is_array($record['specifications'] ?? null) ? $record['specifications'] : null) ?? [],
            'manufacturer' => ProductDetails::manufacturer(is_array($record['manufacturer'] ?? null) ? $record['manufacturer'] : null) ?? [],
            'weight_grams' => $weight !== null && $weight >= 1 ? (int) round($weight) : null,
            'length_cm' => $this->toDimension($record['length_cm'] ?? null),
            'width_cm' => $this->toDimension($record['width_cm'] ?? null),
            'height_cm' => $this->toDimension($record['height_cm'] ?? null),
            'photo_numbers' => array_values(array_filter(array_map('intval', (array) ($record['photo_numbers'] ?? [])), fn ($n) => $n > 0)),
            'description_written_by_ai' => (bool) ($record['description_written_by_ai'] ?? false),
            'notes' => $this->cleanText($record['notes'] ?? ''),
            'confidence' => $confidence,
            'issues' => $issues,
            'importable' => $title !== '' && $price !== null && $categoryId !== null,
        ];
    }

    /** @param array<int, mixed> $variants */
    private function explicitVariants(array $variants, array $record): array
    {
        $fallbackStock = $this->toNumber($record['stock'] ?? null);
        $out = [];
        $seen = [];

        foreach (array_slice($variants, 0, 60) as $v) {
            if (! is_array($v)) {
                continue;
            }

            $color = $this->cleanText($v['color'] ?? '') ?: null;
            $size = $this->cleanText($v['size'] ?? '') ?: null;
            $key = mb_strtolower(($color ?? '').'|'.($size ?? ''));

            // The same colour and size twice is one variant, not two.
            if (isset($seen[$key])) {
                continue;
            }
            $seen[$key] = true;

            $stock = $this->toNumber($v['stock'] ?? null) ?? $fallbackStock;
            $price = $this->toNumber($v['price'] ?? null);
            $mrp = $this->toNumber($v['mrp'] ?? null);

            $out[] = [
                'color' => $color,
                'size' => $size ?? ($color === null ? 'Standard' : null),
                'sku' => $this->cleanText($v['sku'] ?? '') ?: null,
                'stock' => $stock === null ? $this->defaultStock : max(0, (int) $stock),
                'price' => $price !== null && $price > 0 ? $price : null,
                'mrp' => $mrp !== null && $mrp > 0 ? $mrp : null,
            ];
        }

        return $out ?: [['color' => null, 'size' => 'Standard', 'stock' => $this->defaultStock, 'sku' => null]];
    }

    /** Feature bullets keep their commas: "Machine wash, cold" is one point. */
    private function toBullets($value): array
    {
        if (is_array($value)) {
            $items = array_map(fn ($x) => $this->cleanText(is_scalar($x) ? $x : ''), $value);
        } else {
            $items = $value === null || $value === '' ? [] : array_map(fn ($x) => $this->cleanText($x), preg_split('/[\n|]+/', (string) $value));
        }

        return array_values(array_map(fn ($x) => mb_substr($x, 0, 500), array_filter($items, fn ($x) => $x !== '')));
    }

    private function toDimension($value): ?int
    {
        $n = $this->toNumber($value);

        return $n !== null && $n >= 1 && $n <= 500 ? (int) round($n) : null;
    }

    /** Pull fields out of a prose blob like "Silk Saree — ₹3,499 (MRP ₹6,999), red/blue, sizes S-XL". */
    private function extractFromProse(string $text, array &$confidence): array
    {
        $record = [];
        $working = $text;

        // Prices: ₹1,234 / Rs. 1234 / INR 1234 / 1234/-
        preg_match_all('/(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)|([\d,]+(?:\.\d{1,2})?)\s*\/-/i', $working, $m, PREG_SET_ORDER);
        $amounts = [];
        foreach ($m as $hit) {
            $amounts[] = (float) str_replace(',', '', $hit[1] !== '' ? $hit[1] : ($hit[2] ?? '0'));
        }

        if ($amounts) {
            // An explicit "MRP <n>" wins; otherwise lowest = price, highest = MRP.
            if (preg_match('/mrp\D{0,12}?(?:₹|rs\.?|inr)?\s*([\d,]+)/i', $working, $mm)) {
                $record['mrp'] = (float) str_replace(',', '', $mm[1]);
                $others = array_values(array_diff($amounts, [$record['mrp']]));
                $record['price'] = $others ? min($others) : $record['mrp'];
            } else {
                $record['price'] = min($amounts);
                if (count($amounts) > 1) {
                    $record['mrp'] = max($amounts);
                }
            }
            $confidence['price'] = count($amounts) === 1 ? 0.8 : 0.7;
            $confidence['mrp'] = isset($record['mrp']) ? 0.6 : 0.0;
        }

        // Explicit "key: value" pairs anywhere in the text.
        foreach (self::FIELD_ALIASES as $field => $_) {
            if (preg_match('/\b'.preg_quote($field, '/').'\s*[:=]\s*([^\n,;|]+)/i', $working, $fm)) {
                $record[$field] = trim($fm[1]);
                $confidence[$field] = 0.85;
            }
        }

        // Image URLs.
        if (preg_match_all('#https?://\S+\.(?:jpg|jpeg|png|webp|avif|gif)(?:\?\S*)?#i', $working, $im)) {
            $record['images'] = $im[0];
            $confidence['images'] = 0.9;
        }

        // Sizes: "sizes S-XL", "S/M/L", "UK 7,8,9"
        if (preg_match('/\bsizes?\s*[:\-]?\s*([A-Za-z0-9 ,\/\-]+)/i', $working, $sm)) {
            $record['size'] = $sm[1];
            $confidence['size'] = 0.7;
        }
        if (preg_match('/\bcolou?rs?\s*[:\-]?\s*([A-Za-z ,\/]+)/i', $working, $cm)) {
            $record['color'] = $cm[1];
            $confidence['color'] = 0.7;
        }

        // Title: first line, minus any price fragment.
        $firstLine = trim(explode("\n", $text)[0]);
        $title = preg_replace('/(?:₹|rs\.?|inr)\s*[\d,]+(?:\.\d{1,2})?/i', '', $firstLine);
        $title = trim(preg_replace('/[\-–—|,:]+\s*$/', '', trim($title)));
        if (! isset($record['title']) && $title !== '') {
            $record['title'] = $title;
            $confidence['title'] = 0.75;
        }

        // Description: everything after the first line, if substantial.
        $rest = trim(Str::after($text, $firstLine));
        if (! isset($record['description']) && mb_strlen($rest) > 30) {
            $record['description'] = $rest;
            $confidence['description'] = 0.6;
        }

        return $record;
    }

    protected function buildVariants(array $record): array
    {
        // A source that already lists its variants (the AI reader does) is taken as it is.
        if (isset($record['variants']) && is_array($record['variants']) && array_is_list($record['variants']) && $record['variants'] && is_array($record['variants'][0])) {
            return $this->explicitVariants($record['variants'], $record);
        }

        $colors = $this->toList($record['color'] ?? null);
        $sizes = $this->toList($record['size'] ?? null);
        $stock = $this->toNumber($record['stock'] ?? null);
        $stock = $stock === null ? $this->defaultStock : (int) $stock;
        $sku = $this->cleanText($record['sku'] ?? '') ?: null;

        // Cartesian product when both axes are present, otherwise one axis,
        // otherwise a single default variant so the product is purchasable.
        if ($colors && $sizes) {
            $out = [];
            foreach ($colors as $c) {
                foreach ($sizes as $s) {
                    $out[] = ['color' => $c, 'size' => $s, 'stock' => $stock, 'sku' => null];
                }
            }

            return $out;
        }

        if ($colors) {
            return array_map(fn ($c) => ['color' => $c, 'size' => null, 'stock' => $stock, 'sku' => null], $colors);
        }

        if ($sizes) {
            return array_map(fn ($s) => ['color' => null, 'size' => $s, 'stock' => $stock, 'sku' => null], $sizes);
        }

        return [['color' => null, 'size' => 'Standard', 'stock' => $stock, 'sku' => $sku]];
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /** Fuzzy-match an arbitrary column heading onto one of our fields. */
    private function matchField(string $heading): ?string
    {
        $key = preg_replace('/[^a-z0-9]/', '', mb_strtolower($heading));
        if ($key === '') {
            return null;
        }

        foreach (self::FIELD_ALIASES as $field => $aliases) {
            if (in_array($key, $aliases, true)) {
                return $field;
            }
        }

        // Near-miss (typos, pluralisation) via similarity.
        $best = null;
        $bestScore = 0;
        foreach (self::FIELD_ALIASES as $field => $aliases) {
            foreach ($aliases as $alias) {
                similar_text($key, $alias, $pct);
                if ($pct > $bestScore) {
                    $bestScore = $pct;
                    $best = $field;
                }
            }
        }

        return $bestScore >= 82 ? $best : null;
    }

    protected function matchCategory($value, array $categories): array
    {
        $name = $this->cleanText((string) ($value ?? ''));
        if ($name === '' || ! $categories) {
            return [null, $name ?: null, 0.0];
        }

        $needle = mb_strtolower($name);

        foreach ($categories as $cat) {
            if (mb_strtolower($cat['name']) === $needle || mb_strtolower($cat['slug']) === $needle) {
                return [$cat['id'], $cat['name'], 1.0];
            }
        }

        // Substring or high-similarity match.
        $best = null;
        $bestScore = 0;
        foreach ($categories as $cat) {
            $hay = mb_strtolower($cat['name']);
            if (str_contains($hay, $needle) || str_contains($needle, $hay)) {
                return [$cat['id'], $cat['name'], 0.8];
            }
            similar_text($needle, $hay, $pct);
            if ($pct > $bestScore) {
                $bestScore = $pct;
                $best = $cat;
            }
        }

        return $bestScore >= 70 ? [$best['id'], $best['name'], round($bestScore / 100, 2)] : [null, $name, 0.0];
    }

    private function cleanText($v): string
    {
        return trim(preg_replace('/\s+/', ' ', (string) $v));
    }

    private function toNumber($v): ?float
    {
        if ($v === null || $v === '') {
            return null;
        }
        if (is_numeric($v)) {
            return (float) $v;
        }

        $clean = preg_replace('/[^\d.]/', '', str_replace(',', '', (string) $v));

        return $clean === '' || ! is_numeric($clean) ? null : (float) $clean;
    }

    /** Accepts arrays, or strings delimited by comma / pipe / slash / newline. */
    private function toList($v): array
    {
        if (is_array($v)) {
            return array_values(array_filter(array_map(fn ($x) => $this->cleanText($x), $v)));
        }
        if ($v === null || $v === '') {
            return [];
        }

        $parts = preg_split('/[,\|\/\n]+/', (string) $v);

        return array_values(array_filter(array_map(fn ($p) => $this->cleanText($p), $parts), fn ($p) => $p !== ''));
    }
}
