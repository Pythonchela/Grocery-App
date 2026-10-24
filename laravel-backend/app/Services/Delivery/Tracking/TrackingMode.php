<?php

namespace App\Services\Delivery\Tracking;

use App\Models\Order;
use App\Models\Setting;
use App\Services\Delivery\ServiceLevel;

/**
 * Does this order get a live map, or a list of status updates?
 *
 * A moving dot on a map only means something when a rider is bringing the order
 * in the next couple of hours. For anything slower - a parcel crossing the
 * country in four days - the honest picture is "where it is, and when it
 * should arrive", the way courier and marketplace apps show it.
 *
 * The cut-off is a setting (`delivery.live_map_max_minutes`, default 180 = 3
 * hours) so a store that only ever sells groceries or only ever ships parcels
 * can move it without a release.
 */
final class TrackingMode
{
    public const LIVE_MAP = 'live_map';

    public const STATUS_UPDATES = 'status_updates';

    public static function thresholdMinutes(): int
    {
        return max(0, (int) Setting::get('delivery.live_map_max_minutes', config('delivery.live_map_max_minutes', 180)));
    }

    public static function for(Order $order): string
    {
        // Partners that never report a position cannot draw a live map, however
        // short the promise: the only honest display is the status list.
        $carrier = $order->carrier ? config("delivery.carriers.{$order->carrier}", []) : [];
        if ($order->carrier && ! ($carrier['live_position'] ?? false)) {
            return self::STATUS_UPDATES;
        }

        $window = self::promisedMinutes($order);

        if ($window !== null) {
            return $window <= self::thresholdMinutes() ? self::LIVE_MAP : self::STATUS_UPDATES;
        }

        return $order->service_level === ServiceLevel::INSTANT ? self::LIVE_MAP : self::STATUS_UPDATES;
    }

    /** How long the shopper was promised, from placing the order to arrival. */
    public static function promisedMinutes(Order $order): ?int
    {
        if (! $order->promised_by || ! $order->created_at) {
            return null;
        }

        return max(0, (int) $order->created_at->diffInMinutes($order->promised_by, false));
    }
}
