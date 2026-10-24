<?php

namespace App\Services\Delivery;

use App\Models\Product;

/**
 * How a kind of item can be delivered, and how long it takes to get ready.
 *
 *   instant  Food, groceries, anything made or kept near the customer. Brought
 *            by a rider within hours - never as a multi-day parcel.
 *   parcel   Clothes, electronics, books. Goes through a courier network:
 *            express (next day) or standard (days). A rider can't take it, since
 *            it ships from a warehouse, not round the corner.
 *   heavy    Furniture, appliances. A truck, booked for a slot.
 *
 * A category sets a default and a product can override it. With neither set the
 * old behaviour applies: whatever weight and distance allow.
 */
final class DeliveryProfile
{
    public const INSTANT = 'instant';

    public const PARCEL = 'parcel';

    public const HEAVY = 'heavy';

    public const ALL = [self::INSTANT, self::PARCEL, self::HEAVY];

    /** @return string[] the service levels this kind of item may be sent at */
    public static function levels(string $profile): array
    {
        return match ($profile) {
            // Same-day stays as the fallback for when no rider is free right now.
            self::INSTANT => [ServiceLevel::INSTANT, ServiceLevel::SAME_DAY],
            self::PARCEL => [ServiceLevel::EXPRESS, ServiceLevel::STANDARD, ServiceLevel::HEAVY],
            self::HEAVY => [ServiceLevel::HEAVY],
            default => ServiceLevel::ALL,
        };
    }

    public static function label(string $profile): string
    {
        return match ($profile) {
            self::INSTANT => 'Quick local delivery',
            self::PARCEL => 'Courier delivery',
            self::HEAVY => 'Heavy-item delivery',
            default => 'Delivery',
        };
    }

    public static function profileOf(Product $product): ?string
    {
        $profile = $product->delivery_profile
            ?? ($product->relationLoaded('category') ? $product->category?->delivery_profile : $product->category()->value('delivery_profile'));

        return in_array($profile, self::ALL, true) ? $profile : null;
    }

    public static function prepMinutesOf(Product $product): int
    {
        $minutes = $product->prep_minutes
            ?? ($product->relationLoaded('category') ? $product->category?->prep_minutes : $product->category()->value('prep_minutes'));

        return max(0, (int) $minutes);
    }

    /**
     * What a whole cart can use: only the speeds every item allows, and the
     * longest preparation time among them (the rider waits for the slowest dish).
     *
     * @param  iterable<Product>  $products
     * @return array{allowed: ?array<int, string>, prep_minutes: int, conflict: ?string, profile: ?string}
     */
    public static function forProducts(iterable $products): array
    {
        $allowed = null;
        $prep = 0;
        $profiles = [];

        foreach ($products as $product) {
            if (! $product) {
                continue;
            }

            $prep = max($prep, self::prepMinutesOf($product));
            $profile = self::profileOf($product);

            if ($profile === null) {
                continue;
            }

            $profiles[$profile] = true;
            $levels = self::levels($profile);
            $allowed = $allowed === null ? $levels : array_values(array_intersect($allowed, $levels));
        }

        $conflict = ($allowed !== null && $allowed === [])
            ? 'Some of these items are delivered by a local rider and some by courier, so they cannot ship together. Please order them separately.'
            : null;

        return [
            'allowed' => $allowed,
            'prep_minutes' => $prep,
            'conflict' => $conflict,
            'profile' => count($profiles) === 1 ? array_key_first($profiles) : null,
        ];
    }
}
