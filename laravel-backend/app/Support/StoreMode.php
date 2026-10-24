<?php

namespace App\Support;

/**
 * What kind of store this installation is, and what follows from it.
 *
 * One codebase serves three kinds of business, chosen by the `marketplace.mode`
 * setting:
 *
 *  - single : one business selling its own goods. There are no vendors; the
 *             owner's shop (the "house" seller) is the whole store.
 *  - hybrid : the owner's shop sells next to approved vendors.
 *  - multi  : vendors only. The operator sells nothing, so the house shop is
 *             hidden from shoppers.
 *
 * `marketplace.cart_rule` says whether a basket may hold several shops' goods
 * ("mixed") or one shop at a time ("one_shop", the way food and grocery apps
 * work). With a single shop the rule can never matter.
 */
final class StoreMode
{
    public const SINGLE = 'single';
    public const HYBRID = 'hybrid';
    public const MULTI = 'multi';

    public const MODES = [self::SINGLE, self::HYBRID, self::MULTI];

    public static function mode(): string
    {
        $mode = (string) config('marketplace.mode', self::HYBRID);

        return in_array($mode, self::MODES, true) ? $mode : self::HYBRID;
    }

    /** Whether outside sellers may apply, list and sell. */
    public static function vendorsEnabled(): bool
    {
        return self::mode() !== self::SINGLE;
    }

    /** Whether the owner's own shop shows to shoppers. */
    public static function houseVisible(): bool
    {
        return self::mode() !== self::MULTI;
    }

    public const HOME_LAYOUTS = ['auto', 'products', 'shops'];

    /** What the home page leads with: `auto`, `products` or `shops`. */
    public static function homeLayout(): string
    {
        $layout = (string) config('marketplace.home_layout', 'auto');

        return in_array($layout, self::HOME_LAYOUTS, true) ? $layout : 'auto';
    }

    /** Whether shoppers choose a shop first, then its items. */
    public static function shopsFirst(): bool
    {
        if (! self::showsShops()) {
            return false;
        }

        return match (self::homeLayout()) {
            'products' => false,
            'shops' => true,
            default => self::mode() === self::MULTI,
        };
    }

    /** Whether the home page carries a row of shops among its products. */
    public static function homeShowsShops(): bool
    {
        return self::showsShops() && self::homeLayout() !== 'products';
    }

    /** Whether shops are shown to shoppers at all (anything but a single-business store). */
    public static function showsShops(): bool
    {
        return self::mode() !== self::SINGLE;
    }

    /** Whether a basket is limited to one shop. */
    public static function oneShopPerCart(): bool
    {
        return self::vendorsEnabled() && config('marketplace.cart_rule', 'one_shop') !== 'mixed';
    }

    /** What the apps need to know, as the public config endpoint returns it. */
    public static function publicConfig(): array
    {
        return [
            'mode' => self::mode(),
            'vendors_enabled' => self::vendorsEnabled(),
            'house_visible' => self::houseVisible(),
            'shops_first' => self::shopsFirst(),
            'shows_shops' => self::showsShops(),
            'home_shows_shops' => self::homeShowsShops(),
            'one_shop_per_cart' => self::oneShopPerCart(),
            'store_name' => (string) config('app.name'),
        ];
    }
}
