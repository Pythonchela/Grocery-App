<?php

namespace App\Integrations;

/**
 * One setting an admin can manage.
 *
 * A plain value object: what the setting is called, how to validate it, which
 * config paths it feeds, and how it is shown. The behaviour lives in
 * IntegrationSettings; nothing here touches the database or decrypts anything.
 */
final class Field
{
    public const SECRET = 'secret';
    public const TEXT = 'text';
    public const NUMBER = 'number';
    public const LIST = 'list';
    public const SELECT = 'select'; // one of `options`

    /**
     * @param  list<string>  $config   config() paths this value overrides
     * @param  list<string>  $rules    Laravel validation rules for one value
     * @param  list<string>  $options  allowed members, for LIST fields
     */
    public function __construct(
        public readonly string $group,
        public readonly string $name,
        public readonly string $label,
        public readonly string $type,
        public readonly array $config,
        public readonly array $rules,
        public readonly string $help = '',
        public readonly string $placeholder = '',
        public readonly array $options = [],
        public readonly string $cast = 'string', // string | int | float | list
        public readonly ?string $env = null,
    ) {}

    /** The storage key, e.g. "couriers.shiprocket_password". */
    public function key(): string
    {
        return "{$this->group}.{$this->name}";
    }

    public function isSecret(): bool
    {
        return $this->type === self::SECRET;
    }

    /** A validated request value, in the shape config() expects. */
    public function cast(mixed $value): mixed
    {
        return match ($this->cast) {
            'int' => (int) $value,
            'float' => (float) $value,
            'list' => array_values(array_map('strval', (array) $value)),
            default => (string) $value,
        };
    }
}
