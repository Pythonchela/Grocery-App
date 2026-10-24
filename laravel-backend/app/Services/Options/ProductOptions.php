<?php

namespace App\Services\Options;

use App\Models\OrderItem;
use App\Models\Product;
use App\Models\ProductVariant;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Custom selection options: half / full plate, "no onions", extra cheese,
 * colour swatches, 1.5 kg of tomatoes - whatever a store sells that a plain
 * variant list can't express.
 *
 * A category holds a *template* (a list of option groups); a product either
 * inherits it (custom_options = null) or carries its own list. Either way the
 * shopper sends what they chose as {group_key: [choice ids]} (or a number for a
 * stepper) and this class turns that into a price - the client never says what
 * an option costs.
 *
 * Group shape (canonical, see normalize()):
 *   key, label, type (single|multi|swatch|stepper), required, min, max,
 *   price_mode (add|set for single/swatch; add|multiply for stepper),
 *   remove (multi only: choices are things to leave out),
 *   stepper {min, max, step, unit, default, price}, choices [{id,label,price,
 *   color,image,default,available,stock}]
 */
final class ProductOptions
{
    public const TYPES = ['single', 'multi', 'swatch', 'stepper'];

    public const MAX_GROUPS = 12;

    public const MAX_CHOICES = 60;

    /**
     * Clean up whatever the admin sent into the canonical shape. Unknown keys are
     * dropped, ids are generated and de-duplicated, numbers are coerced - so what
     * is stored (and later priced against) is always well formed.
     *
     * @param  array<int, mixed>|null  $groups
     * @param  bool  $allowStock  choice stock only makes sense on a product's own options
     * @return array<int, array<string, mixed>>
     *
     * @throws ValidationException
     */
    public static function normalize(?array $groups, bool $allowStock = false, string $field = 'option_groups'): array
    {
        $groups = array_values(array_filter($groups ?? [], 'is_array'));

        if (count($groups) > self::MAX_GROUPS) {
            throw ValidationException::withMessages([$field => ['At most '.self::MAX_GROUPS.' option groups are allowed.']]);
        }

        $out = [];
        $keys = [];
        $setGroups = 0;

        foreach ($groups as $i => $g) {
            $label = trim((string) ($g['label'] ?? ''));
            if ($label === '') {
                throw ValidationException::withMessages(["$field.$i.label" => ['Every option group needs a name.']]);
            }

            $type = in_array($g['type'] ?? null, self::TYPES, true) ? $g['type'] : 'single';
            $key = self::uniqueKey(Str::slug((string) (($g['key'] ?? '') ?: $label), '_') ?: 'option', $keys);
            $keys[] = $key;

            $group = [
                'key' => $key,
                'label' => Str::limit($label, 60, ''),
                'type' => $type,
                'required' => (bool) ($g['required'] ?? false),
                'help' => isset($g['help']) && trim((string) $g['help']) !== '' ? Str::limit(trim((string) $g['help']), 140, '') : null,
            ];

            if ($type === 'stepper') {
                $s = is_array($g['stepper'] ?? null) ? $g['stepper'] : [];
                $min = max(0, (float) ($s['min'] ?? 1));
                $max = max($min, (float) ($s['max'] ?? 10));
                $step = (float) ($s['step'] ?? 1);
                $step = $step > 0 ? $step : 1;
                $default = (float) ($s['default'] ?? $min);

                $group['price_mode'] = ($g['price_mode'] ?? 'multiply') === 'add' ? 'add' : 'multiply';
                $group['stepper'] = [
                    'min' => $min,
                    'max' => $max,
                    'step' => $step,
                    'unit' => Str::limit(trim((string) ($s['unit'] ?? '')), 12, ''),
                    'default' => min($max, max($min, $default)),
                    // Only used when price_mode is "add": rupees per step.
                    'price' => max(0, round((float) ($s['price'] ?? 0), 2)),
                ];
                $group['choices'] = [];
                $out[] = $group;

                continue;
            }

            $group['price_mode'] = $type !== 'multi' && ($g['price_mode'] ?? 'add') === 'set' ? 'set' : 'add';
            $group['remove'] = $type === 'multi' && (bool) ($g['remove'] ?? false);

            $rawChoices = array_values(array_filter($g['choices'] ?? [], 'is_array'));
            if (count($rawChoices) > self::MAX_CHOICES) {
                throw ValidationException::withMessages(["$field.$i.choices" => ['At most '.self::MAX_CHOICES." choices in \"$label\"."]]);
            }

            $choices = [];
            $ids = [];
            foreach ($rawChoices as $j => $c) {
                $cl = trim((string) ($c['label'] ?? ''));
                if ($cl === '') {
                    throw ValidationException::withMessages(["$field.$i.choices.$j.label" => ["A choice in \"$label\" has no name."]]);
                }

                $id = self::uniqueKey(Str::slug((string) (($c['id'] ?? '') ?: $cl), '_') ?: 'choice', $ids);
                $ids[] = $id;

                $price = round((float) ($c['price'] ?? 0), 2);
                if ($price < 0) {
                    throw ValidationException::withMessages(["$field.$i.choices.$j.price" => ['A price cannot be negative.']]);
                }

                $color = isset($c['color']) ? strtoupper(trim((string) $c['color'])) : null;
                $stock = $allowStock && isset($c['stock']) && $c['stock'] !== '' ? max(0, (int) $c['stock']) : null;

                $choices[] = [
                    'id' => $id,
                    'label' => Str::limit($cl, 60, ''),
                    'price' => $group['remove'] ? 0.0 : $price,
                    'color' => $color !== null && preg_match('/^#[0-9A-F]{6}([0-9A-F]{2})?$/', $color) ? $color : null,
                    'image' => isset($c['image']) && $c['image'] !== '' ? Str::limit((string) $c['image'], 2048, '') : null,
                    'default' => (bool) ($c['default'] ?? false),
                    'available' => (bool) ($c['available'] ?? true),
                    'stock' => $stock,
                ];
            }

            if ($choices === []) {
                throw ValidationException::withMessages(["$field.$i.choices" => ["\"$label\" needs at least one choice."]]);
            }

            if ($type !== 'multi') {
                // One default at most - the first one flagged wins.
                $seen = false;
                foreach ($choices as &$c) {
                    if ($c['default'] && $seen) {
                        $c['default'] = false;
                    }
                    $seen = $seen || $c['default'];
                }
                unset($c);
            }

            $count = count($choices);
            $min = max(0, (int) ($g['min'] ?? ($group['required'] ? 1 : 0)));
            $max = (int) ($g['max'] ?? $count);
            $group['min'] = $type === 'multi' ? min($min, $count) : ($group['required'] ? 1 : 0);
            $group['max'] = $type === 'multi' ? max(max(1, $group['min']), min($max, $count)) : 1;
            if ($type === 'multi' && $group['min'] > 0) {
                $group['required'] = true;
            }

            if ($group['price_mode'] === 'set') {
                $setGroups++;
            }

            $group['choices'] = $choices;
            $out[] = $group;
        }

        if ($setGroups > 1) {
            throw ValidationException::withMessages([$field => ['Only one group can set the price (e.g. Half / Full). Make the others "adds to the price".']]);
        }

        return $out;
    }

    /**
     * The groups a product actually shows: its own, or its category's template.
     *
     * @return array<int, array<string, mixed>>
     */
    public static function groupsFor(Product $product): array
    {
        $own = $product->custom_options;

        if (is_array($own)) {
            return $own;
        }

        $category = $product->relationLoaded('category') ? $product->category : $product->category()->first();
        $template = $category?->option_groups;

        return is_array($template) ? $template : [];
    }

    /**
     * Price one line.
     *
     * @param  array<string, mixed>|null  $selection  {group_key: [choice ids] | number}
     *
     * @throws ValidationException when a choice is missing, invalid or unavailable
     */
    public static function resolve(Product $product, ProductVariant $variant, ?array $selection): ResolvedOptions
    {
        $groups = self::groupsFor($product);
        $selection = $selection ?? [];
        $title = $product->title;

        $known = array_column($groups, 'key');
        foreach (array_keys($selection) as $key) {
            if (! in_array($key, $known, true)) {
                throw self::fail("\"$key\" is not an option for $title.");
            }
        }

        $base = (float) $variant->effective_price;
        $setPrice = null;
        $multiplier = 1.0;
        $add = 0.0;
        $summary = [];
        $signature = [];

        foreach ($groups as $group) {
            $key = $group['key'];
            $label = $group['label'];
            $raw = $selection[$key] ?? null;

            if ($group['type'] === 'stepper') {
                $s = $group['stepper'];

                if ($raw === null || $raw === '' || $raw === []) {
                    if ($group['required']) {
                        throw self::fail("Choose $label for $title.");
                    }

                    continue;
                }

                $value = is_array($raw) ? (float) reset($raw) : (float) $raw;
                if ($value < $s['min'] - 1e-9 || $value > $s['max'] + 1e-9) {
                    throw self::fail("$label for $title must be between ".self::num($s['min']).' and '.self::num($s['max']).'.');
                }

                $steps = ($value - $s['min']) / $s['step'];
                if (abs($steps - round($steps)) > 1e-6) {
                    throw self::fail("$label for $title must go up in steps of ".self::num($s['step']).'.');
                }

                if ($group['price_mode'] === 'multiply') {
                    $multiplier *= $value;
                } else {
                    $add += $value * $s['price'];
                }

                $summary[] = ['key' => $key, 'label' => $label, 'type' => 'stepper', 'value' => $value, 'unit' => $s['unit'], 'choices' => []];
                $signature[] = $key.'='.self::num($value);

                continue;
            }

            $ids = $raw === null || $raw === '' ? [] : array_values(array_unique(array_map('strval', (array) $raw)));
            $byId = [];
            foreach ($group['choices'] as $c) {
                $byId[$c['id']] = $c;
            }

            if ($ids === []) {
                if ($group['required'] || (int) ($group['min'] ?? 0) > 0) {
                    throw self::fail("Choose $label for $title.");
                }

                continue;
            }

            if ($group['type'] !== 'multi' && count($ids) > 1) {
                throw self::fail("Choose only one $label for $title.");
            }

            if ($group['type'] === 'multi') {
                if (count($ids) < (int) $group['min']) {
                    throw self::fail("Choose at least {$group['min']} for $label on $title.");
                }
                if (count($ids) > (int) $group['max']) {
                    throw self::fail("Choose at most {$group['max']} for $label on $title.");
                }
            }

            $picked = [];
            foreach ($ids as $id) {
                $choice = $byId[$id] ?? null;
                if (! $choice) {
                    throw self::fail("That $label choice is no longer offered for $title.");
                }
                if (! ($choice['available'] ?? true) || (($choice['stock'] ?? null) !== null && $choice['stock'] < 1)) {
                    throw self::fail("{$choice['label']} is not available right now.");
                }

                if ($group['price_mode'] === 'set') {
                    $setPrice = (float) $choice['price'];
                } else {
                    $add += (float) $choice['price'];
                }

                $picked[] = ['id' => $choice['id'], 'label' => $choice['label'], 'price' => (float) $choice['price']];
            }

            // Stable order so the same selection always produces the same signature.
            usort($picked, fn ($a, $b) => strcmp($a['id'], $b['id']));
            $signature[] = $key.'='.implode(',', array_column($picked, 'id'));

            $summary[] = [
                'key' => $key,
                'label' => $label,
                'type' => $group['type'],
                'remove' => (bool) ($group['remove'] ?? false),
                'price_mode' => $group['price_mode'],
                'choices' => $picked,
            ];
        }

        sort($signature);
        $unit = round((($setPrice ?? $base) * $multiplier) + $add, 2);

        return new ResolvedOptions($unit, $summary, implode('|', $signature));
    }

    /**
     * Take the picked choices' stock off the product, under a row lock. Only the
     * product's *own* options carry stock; a template's choices never do.
     *
     * @param  array<int, array{product: Product, options: ?array, quantity: int}>  $lines
     *
     * @throws ValidationException
     */
    public static function reserveStock(array $lines): void
    {
        $needs = [];
        foreach ($lines as $line) {
            foreach (($line['options'] ?? []) as $group) {
                foreach ($group['choices'] ?? [] as $choice) {
                    $pid = $line['product']->id;
                    $needs[$pid][$group['key']][$choice['id']] = ($needs[$pid][$group['key']][$choice['id']] ?? 0) + $line['quantity'];
                }
            }
        }

        foreach ($needs as $productId => $byGroup) {
            $product = Product::whereKey($productId)->lockForUpdate()->first();
            $own = $product?->custom_options;
            if (! is_array($own)) {
                continue;
            }

            $dirty = false;
            foreach ($own as &$group) {
                foreach ($group['choices'] as &$choice) {
                    $want = $byGroup[$group['key']][$choice['id']] ?? 0;
                    if ($want === 0 || ($choice['stock'] ?? null) === null) {
                        continue;
                    }
                    if ($choice['stock'] < $want) {
                        throw self::fail($choice['stock'] > 0
                            ? "Only {$choice['stock']} left of {$choice['label']}."
                            : "{$choice['label']} is sold out.");
                    }
                    $choice['stock'] -= $want;
                    $dirty = true;
                }
                unset($choice);
            }
            unset($group);

            if ($dirty) {
                $product->custom_options = $own;
                $product->save();
            }
        }
    }

    /** Put an order line's option stock back (cancelled or returned). */
    public static function restock(OrderItem $item, int $quantity): void
    {
        $selected = $item->selected_options;
        if (! is_array($selected) || ! $item->product_id) {
            return;
        }

        $product = Product::whereKey($item->product_id)->lockForUpdate()->first();
        $own = $product?->custom_options;
        if (! is_array($own)) {
            return;
        }

        $dirty = false;
        foreach ($selected as $picked) {
            foreach ($own as &$group) {
                if ($group['key'] !== ($picked['key'] ?? null)) {
                    continue;
                }
                foreach ($group['choices'] as &$choice) {
                    foreach ($picked['choices'] ?? [] as $p) {
                        if ($p['id'] === $choice['id'] && ($choice['stock'] ?? null) !== null) {
                            $choice['stock'] += $quantity;
                            $dirty = true;
                        }
                    }
                }
                unset($choice);
            }
            unset($group);
        }

        if ($dirty) {
            $product->custom_options = $own;
            $product->save();
        }
    }

    private static function fail(string $message): ValidationException
    {
        return ValidationException::withMessages(['items' => [$message]]);
    }

    private static function num(float $n): string
    {
        return rtrim(rtrim(number_format($n, 3, '.', ''), '0'), '.');
    }

    /** @param  string[]  $taken */
    private static function uniqueKey(string $key, array $taken): string
    {
        $candidate = $key;
        $n = 2;
        while (in_array($candidate, $taken, true)) {
            $candidate = $key.'_'.$n++;
        }

        return $candidate;
    }
}
