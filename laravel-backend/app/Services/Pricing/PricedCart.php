<?php

namespace App\Services\Pricing;

use App\Models\Coupon;

/**
 * The server's own arithmetic for a cart — the single answer that checkout,
 * the coupon preview and the payment intent all quote from.
 *
 * Before this existed each of those three computed its own total, which is how
 * the storefront came to show a ₹99 flat shipping fee while checkout charged a
 * live carrier quote. One calculation, three readers.
 */
final class PricedCart
{
    /** @param CartLine[] $lines */
    public function __construct(
        public readonly array $lines,
        public readonly float $subtotal,
        public readonly ?Coupon $coupon,
        public readonly float $couponDiscount,
        public readonly float $shipping,
        public readonly string $serviceLevel,
        public readonly ?string $carrier,
        public readonly int $etaMinutes,
        public readonly int $pointsRedeemable,
        public readonly float $pointsDiscount,
        public readonly float $walletApplicable,
        public readonly float $total,
        public readonly float $bundleDiscount = 0.0,
        /** @var array<int, array{bundle_id: string, name: string, pairs: int, discount: float}> */
        public readonly array $bundles = [],
    ) {}

    /** Bundle + coupon + points. Shipping is a charge, not a discount, so it stays out. */
    public function totalDiscount(): float
    {
        return round($this->bundleDiscount + $this->couponDiscount + $this->pointsDiscount, 2);
    }

    /** Amount the payment gateway must actually capture, in paise. */
    public function payablePaise(): int
    {
        return (int) round($this->total * 100);
    }

    /** @return array<string, mixed> The breakdown the storefront renders. */
    public function toArray(): array
    {
        return [
            'items' => array_map(fn (CartLine $l) => [
                'product_id' => $l->product->id,
                'variant_id' => $l->variant->id,
                'title' => $l->product->title,
                'quantity' => $l->quantity,
                'unit_price' => $l->unitPrice,
                'line_total' => $l->lineTotal(),
                'discount_allocated' => $l->discountAllocated,
            ], $this->lines),
            'subtotal' => $this->subtotal,
            'bundle_discount' => $this->bundleDiscount,
            'bundles' => $this->bundles,
            'coupon_code' => $this->coupon?->code,
            'coupon_discount' => $this->couponDiscount,
            'points_redeemable' => $this->pointsRedeemable,
            'points_discount' => $this->pointsDiscount,
            'wallet_applicable' => $this->walletApplicable,
            'shipping' => $this->shipping,
            'service_level' => $this->serviceLevel,
            'carrier' => $this->carrier,
            'eta_minutes' => $this->etaMinutes,
            'total' => $this->total,
        ];
    }
}
