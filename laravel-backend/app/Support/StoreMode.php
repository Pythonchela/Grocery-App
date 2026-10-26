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

    /** The first of these settings that holds a client id, or null. */
    private static function clientId(string ...$keys): ?string
    {
        foreach ($keys as $key) {
            $value = config($key);

            if (is_string($value) && trim($value) !== '') {
                return trim($value);
            }
        }

        return null;
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
            // Google client ids are public identifiers (they ship in every page and app that
            // uses them); the admin sets them in Settings so no rebuild is needed. Nothing
            // secret is ever put in this response.
            'google_web_client_id' => self::clientId('services.google.web_client_id', 'services.google.client_id'),
            'google_server_client_id' => self::clientId('services.google.client_id'),
        ];
    }
}
