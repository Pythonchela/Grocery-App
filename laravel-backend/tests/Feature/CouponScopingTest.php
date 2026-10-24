<?php

namespace Tests\Feature;

use App\Models\Coupon;
use App\Models\CouponRedemption;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A targeted coupon must discount only what it targets.
 *
 * The regression these guard against was subtle and expensive: validation
 * correctly checked that *some* cart line qualified, then handed the whole cart
 * subtotal to `discountFor()`. Adding one ₹199 qualifying item to a basket took
 * the percentage off everything in it.
 */
class CouponScopingTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
        'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
    ];

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    private function product(float $price, ?string $categoryId = null): Product
    {
        $product = Product::factory()->pricedAt($price)->create(
            $categoryId ? ['category_id' => $categoryId] : []
        );
        ProductVariant::factory()->withStock(50)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function line(Product $p, int $qty = 1): array
    {
        return ['product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => $qty];
    }

    private function preview(User $user, string $code, array $items): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($user, 'sanctum')
            ->postJson('/api/v1/coupons/preview', ['code' => $code, 'items' => $items]);
    }

    private function placeOrder(User $user, array $items, ?string $code = null): Order
    {
        // By order number rather than `latest()` — orders placed within the
        // same test share a created_at, so recency doesn't identify one.
        $number = $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => $items,
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
            'coupon_code' => $code,
        ])->assertCreated()->json('data.order_number');

        return Order::with('items')->where('order_number', $number)->firstOrFail();
    }

    // ── Scoping ─────────────────────────────────────────────────────────

    public function test_a_product_targeted_coupon_discounts_only_the_targeted_line(): void
    {
        $user = $this->customer();
        $socks = $this->product(200);
        $phone = $this->product(80000);

        Coupon::factory()->percent(50)->forProducts([$socks->id])->create(['code' => 'SOCKS50']);

        $order = $this->placeOrder($user, [$this->line($socks), $this->line($phone)], 'SOCKS50');

        $this->assertEquals(80200.0, (float) $order->subtotal);
        // 50% of the socks alone — not 50% of ₹80,200.
        $this->assertEquals(100.0, (float) $order->discount);
    }

    public function test_a_category_targeted_coupon_discounts_only_that_category(): void
    {
        $user = $this->customer();
        $inScope = $this->product(1000);
        $outOfScope = $this->product(5000);

        Coupon::factory()->percent(20)
            ->forCategories([$inScope->category_id])
            ->create(['code' => 'CATEGORY20']);

        $order = $this->placeOrder($user, [$this->line($inScope), $this->line($outOfScope)], 'CATEGORY20');

        $this->assertEquals(6000.0, (float) $order->subtotal);
        $this->assertEquals(200.0, (float) $order->discount);
    }

    public function test_an_untargeted_coupon_still_discounts_the_whole_cart(): void
    {
        $user = $this->customer();
        $a = $this->product(1000);
        $b = $this->product(3000);

        Coupon::factory()->percent(10)->create(['code' => 'EVERYTHING10']);

        $order = $this->placeOrder($user, [$this->line($a), $this->line($b)], 'EVERYTHING10');

        $this->assertEquals(400.0, (float) $order->discount);
    }

    public function test_a_coupon_that_covers_nothing_in_the_cart_is_refused(): void
    {
        $user = $this->customer();
        $inCart = $this->product(1000);
        $elsewhere = $this->product(500);

        Coupon::factory()->percent(50)->forProducts([$elsewhere->id])->create(['code' => 'OTHER50']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [$this->line($inCart)],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
            'coupon_code' => 'OTHER50',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_max_discount_caps_a_percentage_coupon(): void
    {
        $user = $this->customer();
        $product = $this->product(10000);

        Coupon::factory()->percent(50, maxDiscount: 500)->create(['code' => 'CAPPED']);

        $order = $this->placeOrder($user, [$this->line($product)], 'CAPPED');

        $this->assertEquals(500.0, (float) $order->discount);
    }

    // ── Allocation ──────────────────────────────────────────────────────

    public function test_the_discount_is_allocated_across_lines_and_sums_to_the_whole(): void
    {
        $user = $this->customer();
        $a = $this->product(1000);
        $b = $this->product(3000);

        Coupon::factory()->percent(10)->create(['code' => 'SPREAD10']);

        $order = $this->placeOrder($user, [$this->line($a), $this->line($b)], 'SPREAD10');

        $allocated = $order->items->sum(fn ($i) => (float) $i->discount_allocated);
        $this->assertEquals(400.0, $allocated, 'allocations must sum to the coupon discount');

        // Proportional to line value: ₹100 on the ₹1,000 line, ₹300 on the ₹3,000 one.
        $byProduct = $order->items->keyBy('product_id');
        $this->assertEquals(100.0, (float) $byProduct[$a->id]->discount_allocated);
        $this->assertEquals(300.0, (float) $byProduct[$b->id]->discount_allocated);
    }

    public function test_a_targeted_discount_lands_only_on_the_lines_it_covers(): void
    {
        $user = $this->customer();
        $target = $this->product(1000);
        $other = $this->product(2000);

        Coupon::factory()->percent(25)->forProducts([$target->id])->create(['code' => 'ONLYME']);

        $order = $this->placeOrder($user, [$this->line($target), $this->line($other)], 'ONLYME');

        $byProduct = $order->items->keyBy('product_id');
        $this->assertEquals(250.0, (float) $byProduct[$target->id]->discount_allocated);
        $this->assertEquals(0.0, (float) $byProduct[$other->id]->discount_allocated);
    }

    public function test_rounding_remainder_is_absorbed_so_allocations_always_sum_exactly(): void
    {
        $user = $this->customer();
        // Three equal lines against a discount that doesn't divide cleanly.
        $a = $this->product(333.33);
        $b = $this->product(333.33);
        $c = $this->product(333.34);

        Coupon::factory()->flat(100)->create(['code' => 'FLAT100']);

        $order = $this->placeOrder($user, [$this->line($a), $this->line($b), $this->line($c)], 'FLAT100');

        $allocated = round($order->items->sum(fn ($i) => (float) $i->discount_allocated), 2);
        $this->assertEquals(100.0, $allocated);
    }

    // ── Preview agrees with checkout ─────────────────────────────────────

    public function test_the_preview_quotes_the_same_discount_checkout_applies(): void
    {
        $user = $this->customer();
        $socks = $this->product(200);
        $phone = $this->product(80000);
        $items = [$this->line($socks), $this->line($phone)];

        Coupon::factory()->percent(50)->forProducts([$socks->id])->create(['code' => 'SOCKS50']);

        $previewed = $this->preview($user, 'SOCKS50', $items)
            ->assertOk()
            ->json('data.discount');

        $order = $this->placeOrder($user, $items, 'SOCKS50');

        $this->assertEquals((float) $previewed, (float) $order->discount);
    }

    public function test_the_preview_rejects_a_coupon_checkout_would_reject(): void
    {
        $user = $this->customer();
        $inCart = $this->product(1000);
        $elsewhere = $this->product(500);

        Coupon::factory()->percent(50)->forProducts([$elsewhere->id])->create(['code' => 'OTHER50']);

        $this->preview($user, 'OTHER50', [$this->line($inCart)])->assertStatus(422);
    }

    // ── Limits and lifecycle ─────────────────────────────────────────────

    public function test_a_per_user_limit_is_enforced_across_orders(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);

        Coupon::factory()->percent(10)->create(['code' => 'ONCE', 'per_user_limit' => 1]);

        $this->placeOrder($user, [$this->line($product)], 'ONCE');

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [$this->line($product)],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
            'coupon_code' => 'ONCE',
        ])->assertStatus(422);

        $this->assertSame(1, Order::count());
    }

    public function test_cancelling_an_order_releases_its_coupon_redemption(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);

        $coupon = Coupon::factory()->percent(10)->create(['code' => 'RELEASE', 'per_user_limit' => 1]);
        $order = $this->placeOrder($user, [$this->line($product)], 'RELEASE');

        $this->assertSame(1, (int) $coupon->fresh()->used_count);
        $this->assertSame(1, CouponRedemption::count());

        $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'changed my mind'])
            ->assertOk();

        $this->assertSame(0, (int) $coupon->fresh()->used_count);
        $this->assertSame(0, CouponRedemption::count());
    }
}
