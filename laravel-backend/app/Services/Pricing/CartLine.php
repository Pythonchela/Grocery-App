<?php

namespace App\Services\Pricing;

use App\Models\Product;
use App\Models\ProductVariant;

/**
 * One resolved cart line: a real variant, at the price the server says it
 * costs, with its share of any order-level discount already worked out.
 *
 * `discountAllocated` is the field that makes refunds honest. Discounts are
 * negotiated at order level ("20% off this cart") but refunded at line level
 * ("send back one of the three"), so the split has to be recorded at purchase
 * time — reconstructing it later from a coupon code and a total is guesswork.
 */
final class CartLine
{
    public function __construct(
        public readonly Product $product,
        public readonly ProductVariant $variant,
        public readonly int $quantity,
        public readonly float $unitPrice,
        public readonly float $unitMrp,
        public float $discountAllocated = 0.0,
        /** What the shopper picked (portion, add-ons...), as ProductOptions::resolve() summarised it. */
        public readonly array $options = [],
    ) {}

    /** Identical picks give identical text; empty when nothing was chosen. */
    public function optionsSignature(): string
    {
        $parts = array_map(
            fn (array $g) => $g['key'].'='.($g['type'] === 'stepper'
                ? $g['value']
                : implode(',', array_column($g['choices'], 'id'))),
            $this->options,
        );
        sort($parts);

        return implode(';', $parts);
    }

    public function lineTotal(): float
    {
        return round($this->unitPrice * $this->quantity, 2);
    }

    /** What the customer actually paid for this line, after its discount share. */
    public function netTotal(): float
    {
        return round($this->lineTotal() - $this->discountAllocated, 2);
    }

    /**
     * @return array<string, mixed> Ready for OrderItem::create().
     *
     * The seller and the commission split are snapshotted here rather than
     * resolved later. A seller's rate can be renegotiated and their account can
     * be closed; what a line earned whom is settled at the moment of sale.
     */
    public function toOrderItem(): array
    {
        $seller = $this->product->seller;
        $split = $seller
            ? $seller->splitOf($this->netTotal())
            : ['commission' => 0.0, 'gst' => 0.0, 'tcs' => 0.0, 'tds' => 0.0, 'net' => $this->netTotal()];

        return [
            'product_id' => $this->product->id,
            'variant_id' => $this->variant->id,
            'quantity' => $this->quantity,
            'price' => $this->unitPrice,
            'mrp' => $this->unitMrp,
            'selected_options' => $this->options === [] ? null : $this->options,
            'discount_allocated' => $this->discountAllocated,
            'seller_id' => $seller?->id,
            'commission_rate' => $seller ? (float) $seller->commission_rate : 0.0,
            'commission_amount' => $split['commission'],
            'seller_earning' => $split['net'],
            'gst_on_commission' => $split['gst'],
            'tcs' => $split['tcs'],
            'tds' => $split['tds'],
        ] + \App\Services\SellerOrderDesk::intakeFor($seller);
    }
}
