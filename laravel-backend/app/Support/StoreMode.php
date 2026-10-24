<?php

namespace App\Support;

/**
 * What kind of store this installation is: one business selling its own goods.
 *
 * There are no vendors here: no applications, no shops to choose between, no
 * basket rule. This class stays as the one place that says so, and as the shape
 * the web and phone apps read from `GET /config`, so that every check they make
 * ("do vendors exist?", "show shops?") has a single, honest answer.
 */
final class StoreMode
{
    public static function mode(): string
    {
        return 'single';
    }

    /** Whether outside sellers may apply, list and sell. */
    public static function vendorsEnabled(): bool
    {
        return false;
    }

    /** Whether the owner's own shop shows to shoppers. */
    public static function houseVisible(): bool
    {
        return true;
    }

    public static function showsShops(): bool
    {
        return false;
    }

    public static function oneShopPerCart(): bool
    {
        return false;
    }

    /** What the apps need to know, as the public config endpoint returns it. */
    public static function publicConfig(): array
    {
        return [
            'mode' => self::mode(),
            'vendors_enabled' => false,
            'house_visible' => true,
            'shops_first' => false,
            'shows_shops' => false,
            'home_shows_shops' => false,
            'one_shop_per_cart' => false,
            'store_name' => (string) config('app.name'),
        ];
    }
}
