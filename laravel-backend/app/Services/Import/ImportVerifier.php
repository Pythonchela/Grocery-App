<?php

namespace App\Services\Import;

use App\Models\Product;
use App\Models\ProductVariant;

/**
 * Second opinion on parsed rows, using what the parser cannot know on its own:
 * what the source actually says, and what is already in the catalogue.
 *
 * The AI can misread a digit or invent a price, and a wrong price on a live
 * product is the costly mistake. So every price and MRP is looked for in the
 * source text; one that is not there is marked as doubtful for the owner to check.
 * A photo cannot be searched that way, so those rows are marked as read from a
 * picture instead.
 */
class ImportVerifier
{
    /**
     * @param  list<array>  $rows
     * @param  list<string>  $sourceTexts  every text the rows were read from
     * @param  bool  $fromPictures  whether any of the material was a photo or PDF
     * @return list<array>
     */
    public function verify(array $rows, array $sourceTexts, bool $fromPictures): array
    {
        $numbers = $fromPictures ? null : self::numbersIn(implode("\n", $sourceTexts));
        $catalogue = $this->catalogueTitles();
        $skus = [];

        foreach ($rows as &$row) {
            $row['issues'] = $row['issues'] ?? [];
            $row['confidence'] = $row['confidence'] ?? [];

            $this->checkTitle($row);
            $this->checkPrices($row, $numbers, $fromPictures);
            $this->checkSkus($row, $skus);
            $this->checkAgainstCatalogue($row, $catalogue);

            if (($row['description_written_by_ai'] ?? false) === true) {
                $row['issues'][] = 'The description was written by AI from the details. Read it before publishing.';
                $row['confidence']['description'] = min($row['confidence']['description'] ?? 1.0, 0.6);
            }
            if (! empty($row['notes'])) {
                $row['issues'][] = $row['notes'];
            }
            if (empty($row['images'])) {
                $row['issues'][] = 'No photo yet. Add one after importing, before the product goes live.';
            }

            $row['issues'] = array_values(array_unique($row['issues']));
        }
        unset($row);

        return $rows;
    }

    /**
     * Every number written in a text, as floats: "₹1,25,000.50" gives 125000.5.
     *
     * A comma is a thousands separator only when it sits in a proper group (1,299 or
     * 1,25,000). In a CSV row, "1499,2499" is two prices. A grouped number is also
     * counted as its parts, so "1,299" in a CSV with a comma delimiter is not missed.
     */
    public static function numbersIn(string $text): array
    {
        preg_match_all('/\d{1,3}(?:,\d{2,3})+(?:\.\d+)?(?!\d)|\d+(?:\.\d+)?/', $text, $m);
        $set = [];

        foreach ($m[0] as $raw) {
            $candidates = [str_replace(',', '', $raw)];
            if (str_contains($raw, ',')) {
                array_push($candidates, ...explode(',', $raw));
            }

            foreach ($candidates as $candidate) {
                if (is_numeric($candidate)) {
                    $set[(string) round((float) $candidate, 2)] = true;
                }
            }
        }

        return $set;
    }

    private function checkTitle(array &$row): void
    {
        $title = $row['title'] ?? '';

        // A catalogue typed in capitals reads badly on the storefront.
        if ($title !== '' && mb_strlen($title) > 4 && $title === mb_strtoupper($title) && preg_match('/\p{L}{3}/u', $title)) {
            $row['title'] = mb_convert_case(mb_strtolower($title), MB_CASE_TITLE, 'UTF-8');
            $row['slug'] = \Illuminate\Support\Str::slug($row['title']);
        }
    }

    private function checkPrices(array &$row, ?array $numbers, bool $fromPictures): void
    {
        foreach (['price' => 'Price', 'mrp' => 'MRP'] as $field => $label) {
            $value = $row[$field] ?? null;
            if ($value === null) {
                continue;
            }

            if ($numbers !== null && ! isset($numbers[(string) round((float) $value, 2)])) {
                // An MRP the source never gave was set equal to the price by the parser; that is not a claim.
                $inferred = $field === 'mrp' && ($row['confidence']['mrp'] ?? 1) <= 0.3;
                if (! $inferred) {
                    $row['issues'][] = "{$label} ₹".self::money($value).' was not found in the file. Check it against the source.';
                    $row['confidence'][$field] = min($row['confidence'][$field] ?? 1.0, 0.35);
                }
            }
        }

        $price = (float) ($row['price'] ?? 0);
        $mrp = (float) ($row['mrp'] ?? 0);

        if ($price > 0 && $price < 1) {
            $row['issues'][] = 'The price is under ₹1. Check it.';
        }
        if ($price > 1000000) {
            $row['issues'][] = 'The price is over ₹10 lakh. Check it.';
        }
        if ($price > 0 && $mrp > $price && ($mrp - $price) / $mrp > 0.9) {
            $row['issues'][] = 'The discount is over 90%. Check that price and MRP are not mixed up.';
        }
        if ($fromPictures && $price > 0) {
            $row['confidence']['price'] = min($row['confidence']['price'] ?? 0.7, 0.7);
        }
    }

    /** A SKU already used elsewhere would make the whole import fail, so it is dropped with a note. */
    private function checkSkus(array &$row, array &$seen): void
    {
        $skus = array_values(array_filter(array_map(fn ($v) => $v['sku'] ?? null, $row['variants'] ?? [])));
        $taken = $skus ? ProductVariant::whereIn('sku', $skus)->pluck('sku')->all() : [];

        foreach ($row['variants'] as &$variant) {
            $sku = $variant['sku'] ?? null;
            if ($sku === null) {
                continue;
            }
            if (in_array($sku, $taken, true) || isset($seen[$sku])) {
                $row['issues'][] = "SKU {$sku} is already used by another product, so it was left blank.";
                $variant['sku'] = null;
            } else {
                $seen[$sku] = true;
            }
        }
    }

    /** @param list<array{id: string, title: string, words: array<string, true>}> $catalogue */
    private function checkAgainstCatalogue(array &$row, array $catalogue): void
    {
        $words = self::words($row['title'] ?? '');
        if (count($words) < 2) {
            return;
        }

        foreach ($catalogue as $existing) {
            $shared = count(array_intersect_key($words, $existing['words']));
            $union = count($words) + count($existing['words']) - $shared;

            if ($union > 0 && $shared / $union >= 0.8) {
                $row['issues'][] = "Looks like a product you already have: “{$existing['title']}”. Untick it if it is the same.";
                $row['possible_duplicate'] = $existing['id'];

                return;
            }
        }
    }

    /** @return list<array{id: string, title: string, words: array<string, true>}> */
    private function catalogueTitles(): array
    {
        return Product::query()->select('id', 'title')->limit(5000)->get()
            ->map(fn ($p) => ['id' => $p->id, 'title' => $p->title, 'words' => self::words($p->title)])
            ->all();
    }

    /** @return array<string, true> */
    private static function words(string $title): array
    {
        $clean = preg_replace('/[^\p{L}\p{N}]+/u', ' ', mb_strtolower($title)) ?? '';

        return array_fill_keys(array_filter(explode(' ', $clean), fn ($w) => $w !== ''), true);
    }

    private static function money(float|int|string $value): string
    {
        $v = (float) $value;

        return number_format($v, floor($v) == $v ? 0 : 2);
    }
}
