<?php

namespace App\Services\Pricing;

use App\Models\Seller;
use App\Support\StoreMode;
use Illuminate\Validation\ValidationException;

/**
 * What a shop requires of a basket before it will take the order.
 *
 * Shops differ: one takes orders only between nine and nine, one wants a
 * minimum basket, one delivers to a few PIN codes. And a store can limit a
 * basket to one shop at a time (see StoreMode). All of that is decided here, in
 * one place, so the cart, the payment step and checkout cannot disagree.
 *
 * The checks that only matter when the shopper is actually ordering (hours,
 * minimum, area) are skipped while they are still building a basket; the others
 * are about what can be in a basket at all, so they always apply.
 */
class ShopRules
{
    /**
     * @param  CartLine[]  $lines
     *
     * @throws ValidationException
     */
    public function check(array $lines, ?string $pincode, bool $ordering, ?\DateTimeInterface $now = null): void
    {
        /** @var array<string, float> $subtotals the basket's value, per shop */
        $subtotals = [];
        foreach ($lines as $line) {
            $subtotals[$line->product->seller_id] = ($subtotals[$line->product->seller_id] ?? 0) + $line->lineTotal();
        }

        $sellers = Seller::whereIn('id', array_keys($subtotals))->get()->keyBy('id');

        foreach ($lines as $line) {
            $seller = $sellers->get($line->product->seller_id);

            if (! $seller || ! $seller->isVisibleToShoppers()) {
                throw ValidationException::withMessages([
                    'items' => ["{$line->product->title} is not available right now."],
                ]);
            }
        }

        if (StoreMode::oneShopPerCart() && count($subtotals) > 1) {
            $names = $sellers->pluck('display_name')->implode(' and ');

            throw ValidationException::withMessages([
                'shops' => ["Your basket has items from different shops ({$names}). Please order from one shop at a time."],
            ]);
        }

        if (! $ordering) {
            return;
        }

        foreach ($subtotals as $sellerId => $subtotal) {
            $seller = $sellers->get($sellerId);

            if (! $seller->isOpenNow($now)) {
                throw ValidationException::withMessages([
                    'shops' => ["{$seller->display_name} is closed right now. {$seller->closedText($now)}."],
                ]);
            }

            $minimum = (float) $seller->min_order_amount;
            if ($minimum > 0 && round($subtotal, 2) < $minimum) {
                $short = $this->rupees($minimum - $subtotal);

                throw ValidationException::withMessages([
                    'shops' => ["The minimum order for {$seller->display_name} is {$this->rupees($minimum)}. Add {$short} more."],
                ]);
            }

            if ($pincode !== null && ! $seller->servesPincode($pincode)) {
                throw ValidationException::withMessages([
                    'shops' => ["{$seller->display_name} does not deliver to {$pincode}."],
                ]);
            }
        }
    }

    /** The first reason a shop cannot deliver to a PIN code, for places that show a message instead of failing. */
    public function areaProblem(array $productIds, string $pincode): ?string
    {
        $sellerIds = \App\Models\Product::whereIn('id', $productIds)->pluck('seller_id')->unique();

        foreach (Seller::whereIn('id', $sellerIds)->get() as $seller) {
            if (! $seller->servesPincode($pincode)) {
                return "{$seller->display_name} does not deliver to {$pincode}.";
            }
        }

        return null;
    }

    private function rupees(float $amount): string
    {
        $amount = round($amount, 2);

        return '₹'.(floor($amount) == $amount ? number_format($amount, 0) : number_format($amount, 2));
    }
}
