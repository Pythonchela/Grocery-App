<?php

namespace App\Services\Delivery;

/**
 * What delivering a cart looks like: one parcel per pickup point, and the options
 * that cover all of them.
 *
 * A basket from one seller is one parcel and its options are exactly that
 * parcel's quotes. A basket from several sellers is several parcels, and an
 * option exists only if every parcel can travel at that speed: its price is the
 * parcels' prices added up and its arrival is when the *last* parcel arrives.
 */
final class CartDeliveryPlan
{
    /**
     * @param  Shipment[]  $shipments  one per pickup point
     * @param  DeliveryQuote[]  $quotes  fastest first
     * @param  array<int, array{seller_id: ?string, seller_name: ?string, pickup_pincode: string, pickup_city: string, items: int}>  $parcels
     */
    public function __construct(
        public readonly array $shipments,
        public readonly array $quotes,
        public readonly array $parcels,
        public readonly ?string $conflict,
        public readonly bool $preferFastest,
    ) {}

    public function first(): ?Shipment
    {
        return $this->shipments[0] ?? null;
    }

    public function isSplit(): bool
    {
        return count($this->shipments) > 1;
    }
}
