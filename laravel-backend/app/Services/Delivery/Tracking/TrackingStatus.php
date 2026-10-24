<?php

namespace App\Services\Delivery\Tracking;

/**
 * Where a shipment is, in our words.
 *
 * Every delivery partner has its own vocabulary - "Out For Delivery", "OFD",
 * "dispatched for delivery", status code 17. The apps and the order record only
 * ever see these, so adding a partner means teaching it to map into this list,
 * never changing a screen.
 */
final class TrackingStatus
{
    public const CONFIRMED = 'CONFIRMED';

    public const PACKED = 'PACKED';

    public const PICKED_UP = 'PICKED_UP';

    public const IN_TRANSIT = 'IN_TRANSIT';

    public const OUT_FOR_DELIVERY = 'OUT_FOR_DELIVERY';

    public const DELIVERED = 'DELIVERED';

    public const DELAYED = 'DELAYED';

    public const DELIVERY_FAILED = 'DELIVERY_FAILED';

    public const RETURNING = 'RETURNING';

    public const CANCELLED = 'CANCELLED';

    /** The happy path, in order. Used to draw progress and to never go backwards. */
    public const PROGRESS = [
        self::CONFIRMED, self::PACKED, self::PICKED_UP, self::IN_TRANSIT, self::OUT_FOR_DELIVERY, self::DELIVERED,
    ];

    public static function label(string $status): string
    {
        return match ($status) {
            self::CONFIRMED => 'Order confirmed',
            self::PACKED => 'Packed',
            self::PICKED_UP => 'Picked up by courier',
            self::IN_TRANSIT => 'In transit',
            self::OUT_FOR_DELIVERY => 'Out for delivery',
            self::DELIVERED => 'Delivered',
            self::DELAYED => 'Delayed',
            self::DELIVERY_FAILED => 'Delivery attempt failed',
            self::RETURNING => 'Returning to seller',
            self::CANCELLED => 'Cancelled',
            default => ucfirst(strtolower(str_replace('_', ' ', $status))),
        };
    }

    /**
     * Map a partner's wording onto ours.
     *
     * Matching is by phrase, in a deliberate order: "undelivered" contains
     * "delivered" and "out for delivery" contains "delivery", so the more
     * specific meanings are tested first. Extra phrases for a partner can be
     * added in config/delivery.php without touching code.
     */
    public static function fromText(?string $text, ?string $fallback = null): string
    {
        $t = strtolower(trim((string) $text));
        $t = str_replace(['_', '-'], ' ', $t);

        if ($t === '') {
            return $fallback ?? self::IN_TRANSIT;
        }

        $rules = array_merge(self::builtInRules(), (array) config('delivery.status_phrases', []));

        foreach ($rules as $status => $phrases) {
            foreach ((array) $phrases as $phrase) {
                if ($phrase !== '' && str_contains($t, strtolower($phrase))) {
                    return $status;
                }
            }
        }

        return $fallback ?? self::IN_TRANSIT;
    }

    /** @return array<string, string[]> most specific first */
    private static function builtInRules(): array
    {
        return [
            self::CANCELLED => ['cancel'],
            self::RETURNING => ['rto', 'return to origin', 'returned to', 'returning', 'return initiated'],
            self::DELIVERY_FAILED => ['undelivered', 'not delivered', 'failed', 'attempt', 'ndr', 'refused', 'unable to deliver'],
            self::OUT_FOR_DELIVERY => ['out for delivery', 'ofd', 'dispatched for delivery', 'with delivery', 'reached for delivery'],
            self::DELIVERED => ['delivered'],
            self::DELAYED => ['delay', 'on hold', 'held', 'exception', 'weather'],
            self::PICKED_UP => ['picked up', 'pickup done', 'pickup complete', 'collected', 'shipped', 'manifested', 'in scan', 'received at origin'],
            self::IN_TRANSIT => ['transit', 'reached', 'arrived', 'departed', 'hub', 'sorting', 'dispatched', 'forwarded', 'connected', 'bagged', 'facility'],
            self::PACKED => ['packed', 'ready to ship', 'ready for pickup', 'pickup scheduled', 'awb assigned', 'label generated', 'booked', 'created'],
            self::CONFIRMED => ['confirmed', 'placed', 'new order'],
        ];
    }

    /** Our order record has fewer states; this is how a shipment status moves it. */
    public static function toOrderStatus(string $status): ?string
    {
        return match ($status) {
            self::PACKED => 'PACKED',
            self::PICKED_UP, self::IN_TRANSIT => 'SHIPPED',
            self::OUT_FOR_DELIVERY => 'OUT_FOR_DELIVERY',
            self::DELIVERED => 'DELIVERED',
            default => null,
        };
    }

    public static function fromOrderStatus(?string $status): string
    {
        return match ($status) {
            'PACKED' => self::PACKED,
            'SHIPPED' => self::IN_TRANSIT,
            'OUT_FOR_DELIVERY' => self::OUT_FOR_DELIVERY,
            'DELIVERED' => self::DELIVERED,
            'CANCELLED' => self::CANCELLED,
            default => self::CONFIRMED,
        };
    }
}
