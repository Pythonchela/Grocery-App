<?php

namespace App\Services\Delivery;

use App\Models\Order;
use App\Models\Seller;

/**
 * Where an order's goods are collected from.
 *
 * A seller's own pickup address when they have set one; otherwise the platform's
 * (config/admin: "Shipping" settings), which is where the house inventory ships
 * from. Always the whole address from one place - a seller's street is never
 * mixed with the platform's pincode.
 */
final class PickupLocation
{
    /**
     * @return array{name: string, phone: string, line1: string, city: string, state: string, pincode: string, lat: ?float, lng: ?float, code: ?string, seller_id: ?string, seller_name: ?string}
     */
    public static function platform(): array
    {
        $a = (array) config('delivery.pickup_address', []);

        return [
            'name' => (string) ($a['name'] ?? ''),
            'phone' => (string) ($a['phone'] ?? ''),
            'line1' => (string) ($a['line1'] ?? ''),
            'city' => (string) ($a['city'] ?? ''),
            'state' => (string) ($a['state'] ?? ''),
            'pincode' => (string) ($a['pincode'] ?? config('delivery.pickup_pincode')),
            'lat' => isset($a['lat']) ? (float) $a['lat'] : null,
            'lng' => isset($a['lng']) ? (float) $a['lng'] : null,
            'code' => null,
            'seller_id' => null,
            'seller_name' => null,
        ];
    }

    /** @return array<string, mixed> */
    public static function forSeller(?Seller $seller): array
    {
        if (! $seller || ! $seller->hasPickupAddress()) {
            $location = self::platform();
            $location['seller_id'] = $seller?->id;
            $location['seller_name'] = $seller?->display_name;

            return $location;
        }

        return [
            'name' => (string) ($seller->pickup_name ?: $seller->display_name),
            'phone' => (string) ($seller->pickup_phone ?: $seller->support_phone ?: ''),
            'line1' => (string) $seller->pickup_line1,
            'city' => (string) $seller->pickup_city,
            'state' => (string) $seller->pickup_state,
            'pincode' => (string) $seller->pickup_pincode,
            'lat' => $seller->pickup_lat !== null ? (float) $seller->pickup_lat : null,
            'lng' => $seller->pickup_lng !== null ? (float) $seller->pickup_lng : null,
            'code' => $seller->pickup_code ?: null,
            'seller_id' => $seller->id,
            'seller_name' => $seller->display_name,
        ];
    }

    /**
     * The pickup for a whole order: its seller's when every line is one seller's,
     * the platform's otherwise (a booking for a mixed order is refused elsewhere).
     *
     * @return array<string, mixed>
     */
    public static function forOrder(Order $order): array
    {
        $order->loadMissing('items.product.seller');
        $sellers = $order->items->map(fn ($i) => $i->product?->seller)->filter()->unique('id');

        return $sellers->count() === 1 ? self::forSeller($sellers->first()) : self::platform();
    }

    /** One key per physical pickup point, so items from the same place share a parcel. */
    public static function key(array $location): string
    {
        return implode('|', [$location['pincode'], strtolower($location['line1']), $location['lat'], $location['lng']]);
    }
}
