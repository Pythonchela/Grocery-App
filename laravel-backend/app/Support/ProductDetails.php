<?php

namespace App\Support;

/**
 * The "all details" part of a product page: the specification table and the
 * manufacturer panel. Both are free-form data typed in by a seller or admin, so
 * this is where it is tidied before it is stored: trimmed, emptied rows dropped,
 * and capped, so a runaway paste cannot bloat every product response.
 */
final class ProductDetails
{
    public const MAX_GROUPS = 10;
    public const MAX_ROWS = 60;

    /** Fields of the manufacturer panel, in the order they are shown. */
    public const MANUFACTURER_FIELDS = [
        'generic_name', 'country_of_origin', 'manufacturer_name', 'manufacturer_address', 'packer_name', 'packer_address',
    ];

    /** Validation rules to merge into a request's rules. */
    public static function rules(): array
    {
        return [
            'description_html' => 'nullable|string|max:40000',
            'specifications' => 'nullable|array|max:'.self::MAX_GROUPS,
            'specifications.*.title' => 'nullable|string|max:60',
            'specifications.*.rows' => 'nullable|array|max:'.self::MAX_ROWS,
            'specifications.*.rows.*.label' => 'nullable|string|max:60',
            'specifications.*.rows.*.value' => 'nullable|string|max:300',
            'manufacturer' => 'nullable|array',
            'manufacturer.generic_name' => 'nullable|string|max:120',
            'manufacturer.country_of_origin' => 'nullable|string|max:80',
            'manufacturer.manufacturer_name' => 'nullable|string|max:200',
            'manufacturer.manufacturer_address' => 'nullable|string|max:400',
            'manufacturer.packer_name' => 'nullable|string|max:200',
            'manufacturer.packer_address' => 'nullable|string|max:400',
        ];
    }

    /**
     * A table of rows grouped under headings, e.g.
     * [{title: "General", rows: [{label: "Fabric", value: "Cotton"}]}].
     * A row needs both halves; a group needs a row. Null when nothing is left.
     */
    public static function specifications(?array $groups): ?array
    {
        $clean = [];

        foreach ($groups ?? [] as $group) {
            $rows = [];

            foreach (($group['rows'] ?? []) as $row) {
                $label = trim((string) ($row['label'] ?? ''));
                $value = trim((string) ($row['value'] ?? ''));

                if ($label !== '' && $value !== '') {
                    $rows[] = ['label' => $label, 'value' => $value];
                }
            }

            if ($rows) {
                $title = trim((string) ($group['title'] ?? ''));
                $clean[] = ['title' => $title !== '' ? $title : 'General', 'rows' => $rows];
            }
        }

        return $clean ?: null;
    }

    /** Only the manufacturer fields that were filled in, or null. */
    public static function manufacturer(?array $info): ?array
    {
        $clean = [];

        foreach (self::MANUFACTURER_FIELDS as $field) {
            $value = trim((string) ($info[$field] ?? ''));

            if ($value !== '') {
                $clean[$field] = $value;
            }
        }

        return $clean ?: null;
    }

    /**
     * A category's suggested specification rows, so a shirt asks for Fabric and
     * Fit and headphones for Battery and Connectivity:
     * [{title: "General", labels: ["Fabric", "Fit"]}].
     */
    public static function template(?array $groups): ?array
    {
        $clean = [];

        foreach ($groups ?? [] as $group) {
            $labels = array_values(array_unique(array_filter(array_map(
                fn ($l) => trim((string) $l),
                (array) ($group['labels'] ?? []),
            ), fn ($l) => $l !== '')));

            if ($labels) {
                $title = trim((string) ($group['title'] ?? ''));
                $clean[] = ['title' => $title !== '' ? $title : 'General', 'labels' => array_slice($labels, 0, self::MAX_ROWS)];
            }
        }

        return $clean ?: null;
    }

    public static function templateRules(): array
    {
        return [
            'spec_template' => 'nullable|array|max:'.self::MAX_GROUPS,
            'spec_template.*.title' => 'nullable|string|max:60',
            'spec_template.*.labels' => 'nullable|array|max:'.self::MAX_ROWS,
            'spec_template.*.labels.*' => 'nullable|string|max:60',
        ];
    }
}
