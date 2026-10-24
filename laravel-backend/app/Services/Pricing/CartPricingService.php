<?php

namespace App\Services\Pricing;

use App\Models\Coupon;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Setting;
use App\Models\User;
use App\Services\Delivery\DeliveryAllocator;
use App\Services\Delivery\ServiceLevel;
use App\Services\LoyaltyService;
use App\Services\Options\ProductOptions;
use Illuminate\Validation\ValidationException;

/**
 * Prices a cart from the database, never from the request.
 *
 * The client sends product ids, variant ids and quantities. Everything with a
 * currency sign on it — unit price, coupon discount, shipping, how many points
 * may be burned, how much wallet may be applied — is decided here. That
 * boundary is the whole point: a payload is a statement of *what* the shopper
 * wants, never of *what it costs*.
 */
class CartPricingService
{
    /** One line can't exceed this. Guards typos and scripted stock drains alike. */
    public const MAX_QUANTITY_PER_LINE = 20;

    public function __construct(
        private readonly DeliveryAllocator $allocator,
        private readonly LoyaltyService $loyalty,
        private readonly ShopRules $shopRules,
    ) {}

    /**
     * @param  array<int, array{product_id: string, variant_id?: ?string, quantity: int, options?: ?array}>  $items
     * @param  array{coupon_code?: ?string, pincode?: ?string, payment_method?: ?string,
     *               service_level?: ?string, redeem_points?: ?int, use_wallet?: ?bool,
     *               lock?: bool}  $options
     *
     * @throws ValidationException when the cart cannot be priced as requested
     */
    public function price(array $items, ?User $user = null, array $options = []): PricedCart
    {
        $lock = (bool) ($options['lock'] ?? false);
        $paymentMethod = $options['payment_method'] ?? null;

        // Balances are read from the database, not from whatever the caller's
        // User instance happened to be holding. A model handed in by a caller
        // may predate a credit or a debit applied elsewhere in the request, and
        // quoting a wallet or points figure from a stale instance produces a
        // total the checkout then refuses to honour.
        $user = $user?->fresh() ?? $user;

        $lines = $this->resolveLines($items, $lock, $paymentMethod);

        // Which shops' goods may share a basket always applies; whether a shop
        // is open, its minimum order and its delivery area only matter once the
        // shopper is paying (checkout, or opening a payment).
        $this->shopRules->check($lines, $options['pincode'] ?? null, $lock || $paymentMethod !== null);

        $subtotal = round(array_sum(array_map(fn (CartLine $l) => $l->lineTotal(), $lines)), 2);

        // Bundles first: they are priced into the lines, and a coupon then
        // applies to what is left rather than discounting the same rupees twice.
        [$bundleDiscount, $bundles] = (new BundleDiscounts)->apply($lines);

        [$coupon, $couponDiscount] = $this->applyCoupon(
            $lines,
            round($subtotal - $bundleDiscount, 2),
            $user,
            $options['coupon_code'] ?? null,
            $lock,
        );

        [$shipping, $serviceLevel, $carrier, $etaMinutes] = $this->quoteShipping(
            $lines,
            $subtotal - $bundleDiscount - $couponDiscount,
            $options['pincode'] ?? null,
            $paymentMethod === 'COD',
            $options['service_level'] ?? ServiceLevel::STANDARD,
        );

        $runningTotal = max(0, round($subtotal - $bundleDiscount - $couponDiscount + $shipping, 2));

        // Points are capped against the payable amount, so the cap has to be
        // computed after shipping and the coupon — not against the subtotal.
        $pointsRedeemable = 0;
        $pointsDiscount = 0.0;

        if ($user && ! empty($options['redeem_points'])) {
            $pointsRedeemable = min(
                (int) $options['redeem_points'],
                $this->loyalty->maxRedeemablePoints($user, $runningTotal),
            );
            $pointsDiscount = $this->loyalty->pointsToRupees($pointsRedeemable);
            $runningTotal = max(0, round($runningTotal - $pointsDiscount, 2));
        }

        $walletApplicable = 0.0;
        if ($user && ! empty($options['use_wallet'])) {
            $walletApplicable = round(min((float) $user->wallet_balance, $runningTotal), 2);
            $runningTotal = max(0, round($runningTotal - $walletApplicable, 2));
        }

        return new PricedCart(
            lines: $lines,
            subtotal: $subtotal,
            coupon: $coupon,
            couponDiscount: $couponDiscount,
            shipping: $shipping,
            serviceLevel: $serviceLevel,
            carrier: $carrier,
            etaMinutes: $etaMinutes,
            pointsRedeemable: $pointsRedeemable,
            pointsDiscount: $pointsDiscount,
            walletApplicable: $walletApplicable,
            total: $runningTotal,
            bundleDiscount: $bundleDiscount,
            bundles: $bundles,
        );
    }

    /**
     * Report on a cart without refusing it.
     *
     * Deliberately separate from price(). Checkout is all-or-nothing: one
     * withdrawn item has to stop the whole order, so price() throws on the first
     * problem. A cart screen is the opposite — the shopper needs to see *which*
     * line went stale and what it costs now, with the rest still priced. Same
     * rules, different failure posture.
     *
     * Display only. Nothing here is authoritative for money; price() is.
     *
     * @param  array<int, array{product_id: string, variant_id?: ?string, quantity: int}>  $items
     * @return array<int, array<string, mixed>>
     */
    public function inspect(array $items): array
    {
        $products = Product::with(['variants', 'category'])
            ->whereIn('id', array_column($items, 'product_id'))
            ->get()
            ->keyBy('id');

        $report = [];

        foreach ($items as $item) {
            $product = $products->get($item['product_id']);
            $variant = $product?->variants->firstWhere('id', $item['variant_id'] ?? null)
                ?? $product?->variants->first();

            $row = [
                'product_id' => $item['product_id'],
                'variant_id' => $item['variant_id'] ?? null,
                'quantity' => (int) $item['quantity'],
                'unit_price' => null,
                'available' => false,
                'reason' => null,
                'options' => [],
            ];

            if (! $product) {
                $row['reason'] = 'This product is no longer in the catalog.';
            } elseif ($product->status !== 'ACTIVE') {
                $row['reason'] = 'This product is no longer available.';
            } elseif (! $variant) {
                $row['reason'] = 'The option you chose is no longer available.';
            } else {
                $row['variant_id'] = $variant->id;
                $row['unit_price'] = (float) $variant->effective_price;
                $row['unit_mrp'] = (float) $variant->effective_mrp;
                $row['title'] = $product->title;
                $row['stock'] = (int) $variant->stock;

                // The price with the shopper's options on it. A choice that was
                // withdrawn since it went in the cart is reported, not thrown.
                $variant->setRelation('product', $product);
                try {
                    $options = ProductOptions::resolve($product, $variant, $item['options'] ?? null);
                    $row['unit_price'] = $options->unitPrice;
                    $row['unit_mrp'] = $this->unitMrp($variant, $options);
                    $row['options'] = $options->summary;
                } catch (ValidationException $e) {
                    $row['reason'] = $e->errors()['items'][0] ?? 'An option you chose is no longer available.';

                    $report[] = $row;

                    continue;
                }

                if ($variant->stock <= 0) {
                    $row['reason'] = 'Out of stock.';
                } elseif ($variant->stock < $item['quantity']) {
                    $row['available'] = true;
                    $row['reason'] = "Only {$variant->stock} left.";
                } else {
                    $row['available'] = true;
                }
            }

            $report[] = $row;
        }

        return $report;
    }

    /**
     * Turn the request's (product, variant, qty) triples into real rows.
     *
     * The variant is looked up *scoped to its product*, which is what stops the
     * cheapest-variant-of-another-product substitution: previously both ids were
     * checked to exist but never checked to belong together, so a payload could
     * pair an expensive product with a cheap product's variant and be charged
     * the cheap one's price.
     *
     * @return CartLine[]
     */
    private function resolveLines(array $items, bool $lock, ?string $paymentMethod): array
    {
        if ($items === []) {
            throw ValidationException::withMessages(['items' => ['Your cart is empty.']]);
        }

        // Seller comes along for the ride: every line snapshots who sold it and
        // what the platform's cut was, and resolving that per line later would
        // be a query per item at the worst possible moment. The category rides
        // along too - it holds the option template a product may inherit.
        $products = Product::with(['variants', 'seller', 'category'])
            ->whereIn('id', array_column($items, 'product_id'))
            ->get()
            ->keyBy('id');

        // One row per (variant, chosen options). The same variant twice with the
        // same options is merged before the stock check, so a quantity cap can't
        // be sidestepped by splitting it across lines - but "pizza, no onions"
        // and "pizza, extra cheese" are different lines and stay separate.
        $merged = [];

        foreach ($items as $item) {
            $product = $products->get($item['product_id']);

            if (! $product) {
                throw ValidationException::withMessages(['items' => ['A product in your cart no longer exists.']]);
            }

            if ($product->status !== 'ACTIVE') {
                throw ValidationException::withMessages([
                    'items' => ["{$product->title} is not available for purchase."],
                ]);
            }

            // A suspended seller's catalog stops selling immediately, without
            // anyone having to walk their products to DRAFT one by one.
            if ($product->seller && ! $product->seller->isActive()) {
                throw ValidationException::withMessages([
                    'items' => ["{$product->title} is not available from this seller right now."],
                ]);
            }

            $variant = ! empty($item['variant_id'])
                ? $product->variants->firstWhere('id', $item['variant_id'])
                : $product->variants->first();

            if (! $variant) {
                throw ValidationException::withMessages([
                    'items' => ["The selected option for {$product->title} is no longer available."],
                ]);
            }

            if ($paymentMethod === 'COD' && ! $product->cod_available) {
                throw ValidationException::withMessages([
                    'payment_method' => ["Cash on Delivery isn't available for {$product->title}."],
                ]);
            }

            // effective_price falls back to the parent product, so handing the
            // variant its already-loaded parent keeps that from becoming a
            // lazy-load per line.
            $variant->setRelation('product', $product);

            $options = ProductOptions::resolve($product, $variant, $item['options'] ?? null);
            $key = $variant->id.'|'.$options->signature;

            $merged[$key] ??= [
                'product' => $product,
                'variant' => $variant,
                'options' => $options,
                'quantity' => 0,
            ];
            $merged[$key]['quantity'] += (int) $item['quantity'];

            if ($merged[$key]['quantity'] > self::MAX_QUANTITY_PER_LINE) {
                throw ValidationException::withMessages([
                    'items' => ['You can order at most '.self::MAX_QUANTITY_PER_LINE." of {$product->title} at a time."],
                ]);
            }
        }

        // Lock every variant in one statement, in a stable id order. Locking in a
        // consistent order across concurrent checkouts is what keeps two carts
        // holding the same two items from deadlocking each other.
        $locked = collect();
        if ($lock) {
            $ids = array_values(array_unique(array_map(fn ($r) => $r['variant']->id, $merged)));
            sort($ids);

            $locked = ProductVariant::whereIn('id', $ids)
                ->orderBy('id')
                ->lockForUpdate()
                ->get()
                ->keyBy('id');

            foreach ($merged as $key => $row) {
                if ($fresh = $locked->get($row['variant']->id)) {
                    $fresh->setRelation('product', $row['product']);
                    $merged[$key]['variant'] = $fresh;
                }
            }
        }

        // Stock is per variant, so lines that share one are checked together.
        $wanted = [];
        foreach ($merged as $row) {
            $wanted[$row['variant']->id] = ($wanted[$row['variant']->id] ?? 0) + $row['quantity'];
        }

        $lines = [];

        foreach ($merged as $row) {
            /** @var ProductVariant $variant */
            $variant = $row['variant'];

            if ($variant->stock < $wanted[$variant->id]) {
                throw ValidationException::withMessages([
                    'items' => [$variant->stock > 0
                        ? "Only {$variant->stock} left of {$row['product']->title}."
                        : "{$row['product']->title} is out of stock."],
                ]);
            }

            $lines[] = new CartLine(
                product: $row['product'],
                variant: $variant,
                quantity: $row['quantity'],
                unitPrice: $row['options']->unitPrice,
                unitMrp: $this->unitMrp($variant, $row['options']),
                options: $row['options']->summary,
            );
        }

        return $lines;
    }

    /**
     * The "was" price shown struck through. Options that change the price (a full
     * plate costs more than the listed half) carry the discount along with them,
     * so the saving stays proportionate rather than shrinking to nothing.
     */
    private function unitMrp(ProductVariant $variant, \App\Services\Options\ResolvedOptions $options): float
    {
        $mrp = (float) $variant->effective_mrp;
        $base = (float) $variant->effective_price;

        if ($options->unitPrice === $base || $base <= 0) {
            return $mrp;
        }

        return max($options->unitPrice, round($mrp * ($options->unitPrice / $base), 2));
    }

    /**
     * Validate the coupon and spread its discount over the lines it covers.
     *
     * A targeted coupon discounts only what it targets. The old behaviour
     * checked that *some* line matched and then applied the percentage to the
     * whole cart, so "50% off socks" took 50% off a phone sitting in the same
     * basket.
     *
     * @param  CartLine[]  $lines
     * @return array{0: ?Coupon, 1: float}
     */
    private function applyCoupon(array $lines, float $subtotal, ?User $user, ?string $code, bool $lock): array
    {
        if (! $code || ! $user) {
            return [null, 0.0];
        }

        $query = Coupon::whereRaw('UPPER(code) = ?', [strtoupper(trim($code))]);

        // Locked during checkout so two simultaneous redemptions can't both pass
        // a usage-limit check that only one of them should.
        $coupon = $lock ? $query->lockForUpdate()->first() : $query->first();

        if (! $coupon) {
            throw ValidationException::withMessages(['coupon_code' => ['Invalid coupon code.']]);
        }

        $productIds = array_map(fn (CartLine $l) => $l->product->id, $lines);
        $categoryIds = array_values(array_unique(array_map(fn (CartLine $l) => $l->product->category_id, $lines)));

        $eligible = array_values(array_filter(
            $lines,
            fn (CartLine $l) => $coupon->covers($l->product->id, $l->product->category_id, $l->product->seller_id),
        ));

        // Net of any bundle discount already written onto the lines.
        $eligibleSubtotal = round(array_sum(array_map(fn (CartLine $l) => $l->netTotal(), $eligible)), 2);

        // A shop's minimum spend is measured against that shop's lines, never
        // unrelated products in the same basket.
        if ($error = $coupon->validateFor($user, $coupon->seller_id ? $eligibleSubtotal : $subtotal, $productIds, $categoryIds)) {
            throw ValidationException::withMessages(['coupon_code' => [$error]]);
        }

        if ($eligibleSubtotal <= 0) {
            throw ValidationException::withMessages([
                'coupon_code' => ['This coupon does not apply to the items in your cart.'],
            ]);
        }

        $discount = $coupon->discountFor($eligibleSubtotal);

        $this->allocate($eligible, $eligibleSubtotal, $discount);

        return [$coupon, $discount];
    }

    /**
     * Spread a discount across lines in proportion to their value, giving the
     * rounding remainder to the last line so the parts always sum to the whole.
     *
     * @param  CartLine[]  $lines
     */
    private function allocate(array $lines, float $base, float $discount): void
    {
        if ($discount <= 0 || $base <= 0) {
            return;
        }

        // Weights are fixed before any line changes, and the discount is added to
        // whatever a line already carries (a bundle's share), never replaces it.
        $weights = array_map(fn (CartLine $l) => $l->netTotal(), $lines);

        $assigned = 0.0;
        $last = count($lines) - 1;

        foreach ($lines as $i => $line) {
            $share = $i === $last
                ? round($discount - $assigned, 2)
                : round($discount * ($weights[$i] / $base), 2);

            $line->discountAllocated = round($line->discountAllocated + $share, 2);
            $assigned = round($assigned + $share, 2);
        }
    }

    /**
     * Rate-shop the cart. Always re-quoted server-side: the fee the shopper saw
     * may be minutes old, and it is exactly the field worth tampering with.
     *
     * @param  CartLine[]  $lines
     * @return array{0: float, 1: string, 2: ?string, 3: int}
     */
    private function quoteShipping(array $lines, float $netValue, ?string $pincode, bool $cod, ?string $requested): array
    {
        $requested ??= ServiceLevel::STANDARD;

        if (! $pincode) {
            // No destination yet (cart drawer, coupon preview). Quote nothing
            // rather than inventing a fee the checkout won't honour.
            return [0.0, $requested, null, 0];
        }

        // One parcel per seller pickup point; the options cover all of them.
        $plan = $this->allocator->planForCart(
            items: array_map(
                fn (CartLine $l) => ['product_id' => $l->product->id, 'quantity' => $l->quantity],
                $lines,
            ),
            dropPincode: $pincode,
            cod: $cod,
            valuePaise: (int) round($netValue * 100),
        );

        if ($plan->conflict) {
            throw ValidationException::withMessages(['items' => [$plan->conflict]]);
        }

        $quotes = collect($plan->quotes);

        $chosen = $quotes->firstWhere('serviceLevel', $requested)
            // The requested speed isn't available to this order. For ordinary
            // goods fall back to the slowest option that is, rather than failing
            // a good order. For things nobody wants slowly (hot food) the
            // *fastest* is the right default: nobody wants the pizza "same day".
            ?? ($plan->preferFastest ? $quotes->first() : $quotes->last());

        if (! $chosen) {
            throw ValidationException::withMessages([
                'shipping_address' => ['We cannot deliver to this pincode right now.'],
            ]);
        }

        $shipping = $chosen->pricePaise / 100;

        // Free shipping is a standard-tier perk. A rider bringing it in 40
        // minutes is not something an order value earns.
        if ($chosen->serviceLevel === ServiceLevel::STANDARD
            && $netValue >= (float) Setting::get('delivery.free_above', config('delivery.free_above'))) {
            $shipping = 0.0;
        }

        // A basket from several sellers travels with several couriers: no single
        // carrier to record against the order (each seller's parcel has its own).
        return [round($shipping, 2), $chosen->serviceLevel, $chosen->carrier === 'multiple' ? null : $chosen->carrier, $chosen->etaMinutes];
    }
}
