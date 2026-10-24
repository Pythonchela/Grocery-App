<?php

namespace App\Services\Pricing;

use App\Models\BundleDeal;

/**
 * "Buy these two together" pricing.
 *
 * A bundle is a pair of products sold for less than the sum of their prices. The
 * discount is worked out here, from the database, for every pair of units the
 * cart actually contains: ten of A and three of B make three pairs, and the
 * other seven As pay full price.
 *
 * The discount is written onto the lines (`discountAllocated`) exactly as a
 * coupon's is, so a later partial return refunds what was paid rather than the
 * list price, and each seller's earning is computed on what the customer paid.
 *
 * Deliberately conservative where the cart is ambiguous: when a product sits in
 * the cart under several variants at different prices, the cheapest one sets the
 * bundle's saving, so a bundle never discounts by more than the shopper can see.
 */
final class BundleDiscounts
{
    /**
     * @param  CartLine[]  $lines
     * @return array{0: float, 1: array<int, array{bundle_id: string, name: string, pairs: int, discount: float}>}
     */
    public function apply(array $lines): array
    {
        if ($lines === []) {
            return [0.0, []];
        }

        /** @var array<string, CartLine[]> $byProduct */
        $byProduct = [];
        foreach ($lines as $line) {
            $byProduct[$line->product->id][] = $line;
        }

        $productIds = array_keys($byProduct);

        $bundles = BundleDeal::live()
            ->whereIn('primary_product_id', $productIds)
            ->whereIn('secondary_product_id', $productIds)
            ->get();

        if ($bundles->isEmpty()) {
            return [0.0, []];
        }

        $remaining = [];
        $unitPrice = [];
        foreach ($byProduct as $productId => $productLines) {
            $remaining[$productId] = array_sum(array_map(fn (CartLine $l) => $l->quantity, $productLines));
            $unitPrice[$productId] = min(array_map(fn (CartLine $l) => $l->unitPrice, $productLines));
        }

        // Best saving first, so a product that belongs to several bundles goes
        // to the one that helps the shopper most.
        $candidates = $bundles
            ->map(fn (BundleDeal $b) => [
                'bundle' => $b,
                'saving' => round(
                    $unitPrice[$b->primary_product_id] + $unitPrice[$b->secondary_product_id] - (float) $b->bundle_price,
                    2,
                ),
            ])
            ->filter(fn (array $c) => $c['saving'] > 0
                && $c['bundle']->primary_product_id !== $c['bundle']->secondary_product_id)
            ->sortByDesc('saving')
            ->values();

        $total = 0.0;
        $applied = [];

        foreach ($candidates as $candidate) {
            /** @var BundleDeal $bundle */
            $bundle = $candidate['bundle'];
            $primary = $bundle->primary_product_id;
            $secondary = $bundle->secondary_product_id;

            $pairs = min($remaining[$primary], $remaining[$secondary]);
            if ($pairs <= 0) {
                continue;
            }

            $remaining[$primary] -= $pairs;
            $remaining[$secondary] -= $pairs;

            $discount = round($pairs * $candidate['saving'], 2);

            // Split between the two products in proportion to their price, then
            // spread each half over that product's lines.
            $pairValue = $unitPrice[$primary] + $unitPrice[$secondary];
            $primaryShare = round($discount * ($unitPrice[$primary] / $pairValue), 2);

            $this->spread($byProduct[$primary], $primaryShare);
            $this->spread($byProduct[$secondary], round($discount - $primaryShare, 2));

            $total = round($total + $discount, 2);
            $applied[] = [
                'bundle_id' => $bundle->id,
                'name' => $bundle->name,
                'pairs' => $pairs,
                'discount' => $discount,
            ];
        }

        return [$total, $applied];
    }

    /**
     * Add [amount] to the lines' allocated discount in proportion to their value,
     * giving the rounding remainder to the last line so the parts sum to the whole.
     *
     * @param  CartLine[]  $lines
     */
    private function spread(array $lines, float $amount): void
    {
        $base = array_sum(array_map(fn (CartLine $l) => $l->lineTotal(), $lines));
        if ($amount <= 0 || $base <= 0) {
            return;
        }

        $assigned = 0.0;
        $last = count($lines) - 1;

        foreach (array_values($lines) as $i => $line) {
            $share = $i === $last
                ? round($amount - $assigned, 2)
                : round($amount * ($line->lineTotal() / $base), 2);

            $line->discountAllocated = round($line->discountAllocated + $share, 2);
            $assigned = round($assigned + $share, 2);
        }
    }
}
