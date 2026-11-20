<?php

namespace App\Services\Options;

/**
 * The size/colour choices a category offers, in one clean shape:
 *
 *   {
 *     "size_label":  "Size",                      what the first choice is called
 *     "sizes":       ["6", "7", "8"],             values to offer, in order
 *     "color_label": "Colour",                    what the second choice is called
 *     "colors":      [{"name":"Black","hex":"#111111"}]
 *   }
 *
 * Either choice can be left out. Returns null when nothing is set, so the column stays empty
 * for a category that does not use it.
 */
class VariantSetup
{
    public const RULES = [
        'variant_setup' => 'nullable|array',
        'variant_setup.size_label' => 'nullable|string|max:30',
        'variant_setup.sizes' => 'nullable|array|max:60',
        'variant_setup.sizes.*' => 'nullable|string|max:30',
        'variant_setup.color_label' => 'nullable|string|max:30',
        'variant_setup.colors' => 'nullable|array|max:60',
        'variant_setup.colors.*.name' => 'nullable|string|max:30',
        'variant_setup.colors.*.hex' => ['nullable', 'regex:/^#[0-9A-Fa-f]{6}$/'],
    ];

    public static function normalize(?array $setup): ?array
    {
        if (! $setup) {
            return null;
        }

        $sizes = [];
        foreach ((array) ($setup['sizes'] ?? []) as $size) {
            $size = trim((string) $size);
            if ($size !== '' && ! in_array(mb_strtolower($size), array_map('mb_strtolower', $sizes), true)) {
                $sizes[] = $size;
            }
        }

        $colors = [];
        $seen = [];
        foreach ((array) ($setup['colors'] ?? []) as $color) {
            $name = trim((string) (is_array($color) ? ($color['name'] ?? '') : $color));
            if ($name === '' || in_array(mb_strtolower($name), $seen, true)) {
                continue;
            }
            $seen[] = mb_strtolower($name);
            $hex = is_array($color) ? strtoupper((string) ($color['hex'] ?? '')) : '';
            $colors[] = ['name' => $name, 'hex' => preg_match('/^#[0-9A-F]{6}$/', $hex) ? $hex : null];
        }

        $sizeLabel = trim((string) ($setup['size_label'] ?? ''));
        $colorLabel = trim((string) ($setup['color_label'] ?? ''));

        if ($sizes === [] && $colors === [] && $sizeLabel === '' && $colorLabel === '') {
            return null;
        }

        return [
            'size_label' => $sizeLabel !== '' ? $sizeLabel : 'Size',
            'sizes' => $sizes,
            'color_label' => $colorLabel !== '' ? $colorLabel : 'Colour',
            'colors' => $colors,
        ];
    }
}
