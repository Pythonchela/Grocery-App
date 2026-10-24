<?php

namespace Tests\Feature;

use App\Models\BundleDeal;
use App\Models\Coupon;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Bundle deals are priced by the server, from the database, for every pair of
 * units the cart contains — the apps only ever display the promise.
 */
class BundleDealTest extends TestCase
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

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    private function product(float $price): Product
    {
        $product = Product::factory()->pricedAt($price)->create();
        ProductVariant::factory()->withStock(50)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function line(Product $p, int $qty = 1): array
    {
        return ['product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => $qty];
    }

    private function bundle(Product $a, Product $b, float $price, array $overrides = []): BundleDeal
    {
        return BundleDeal::create(array_merge([
            'name' => 'Weekend set',
            'primary_product_id' => $a->id,
            'secondary_product_id' => $b->id,
            'bundle_price' => $price,
            'is_active' => true,
        ], $overrides));
    }

    private function placeOrder(User $user, array $items, ?string $code = null): Order
    {
        $number = $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => $items,
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
            'coupon_code' => $code,
        ])->assertCreated()->json('data.order_number');

        return Order::with('items')->where('order_number', $number)->firstOrFail();
    }

    /** The order total less shipping — shipping is quoted separately and is not under test here. */
    private function goodsTotal(Order $order): float
    {
        return round((float) $order->total_amount - (float) $order->shipping_charge, 2);
    }

    public function test_a_complete_pair_is_charged_the_bundle_price(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $this->bundle($a, $b, 1200);

        $order = $this->placeOrder($this->customer(), [$this->line($a), $this->line($b)]);

        $this->assertEquals(1500.0, (float) $order->subtotal);
        $this->assertEquals(300.0, (float) $order->discount);
        $this->assertEquals(1200.0, $this->goodsTotal($order));
    }

    public function test_the_saving_is_recorded_on_the_lines_so_refunds_stay_honest(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $this->bundle($a, $b, 1200);

        $order = $this->placeOrder($this->customer(), [$this->line($a), $this->line($b)]);

        $allocated = $order->items->sum(fn ($i) => (float) $i->discount_allocated);
        $this->assertEquals(300.0, round($allocated, 2));
        // Proportional to price: 2/3 of the saving on the dearer product.
        $this->assertEquals(200.0, (float) $order->items->firstWhere('product_id', $a->id)->discount_allocated);
        $this->assertEquals(100.0, (float) $order->items->firstWhere('product_id', $b->id)->discount_allocated);
    }

    public function test_only_complete_pairs_are_discounted(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $this->bundle($a, $b, 1200);

        // Three As and one B make one pair; the other two As pay full price.
        $order = $this->placeOrder($this->customer(), [$this->line($a, 3), $this->line($b, 1)]);

        $this->assertEquals(3500.0, (float) $order->subtotal);
        $this->assertEquals(300.0, (float) $order->discount);
    }

    public function test_a_lone_product_gets_no_discount(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $this->bundle($a, $b, 1200);

        $order = $this->placeOrder($this->customer(), [$this->line($a)]);

        $this->assertEquals(0.0, (float) $order->discount);
        $this->assertEquals(1000.0, $this->goodsTotal($order));
    }

    public function test_inactive_and_expired_bundles_are_ignored(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $this->bundle($a, $b, 1200, ['is_active' => false]);
        $this->bundle($a, $b, 1000, ['expires_at' => now()->subDay()]);

        $order = $this->placeOrder($this->customer(), [$this->line($a), $this->line($b)]);

        $this->assertEquals(0.0, (float) $order->discount);
    }

    public function test_a_bundle_priced_above_the_parts_never_raises_the_total(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $this->bundle($a, $b, 2000);

        $order = $this->placeOrder($this->customer(), [$this->line($a), $this->line($b)]);

        $this->assertEquals(0.0, (float) $order->discount);
        $this->assertEquals(1500.0, $this->goodsTotal($order));
    }

    public function test_a_coupon_applies_to_what_is_left_after_the_bundle(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $this->bundle($a, $b, 1200);
        Coupon::factory()->percent(10)->create(['code' => 'TEN']);

        $order = $this->placeOrder($this->customer(), [$this->line($a), $this->line($b)], 'TEN');

        // 300 bundle + 10% of the remaining 1200.
        $this->assertEquals(420.0, (float) $order->discount);
        $this->assertEquals(1080.0, $this->goodsTotal($order));
        $this->assertEquals(420.0, round($order->items->sum(fn ($i) => (float) $i->discount_allocated), 2));
    }

    public function test_the_public_list_shows_the_saving(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $this->bundle($a, $b, 1200);
        $this->bundle($this->product(10), $this->product(20), 25, ['is_active' => false]);

        $response = $this->getJson('/api/v1/deals/bundles')->assertOk();

        $response->assertJsonCount(1, 'data');
        $response->assertJsonPath('data.0.bundle_price', 1200);
        $response->assertJsonPath('data.0.compare_at_price', 1500);
        $response->assertJsonPath('data.0.savings', 300);
        $response->assertJsonCount(2, 'data.0.products');
    }

    public function test_the_public_list_can_be_narrowed_to_one_product(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $c = $this->product(300);
        $this->bundle($a, $b, 1200);

        $this->getJson('/api/v1/deals/bundles?product_id='.$c->id)->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/deals/bundles?product_id='.$b->id)->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_only_admins_can_manage_bundles(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $payload = [
            'name' => 'Pair', 'primary_product_id' => $a->id,
            'secondary_product_id' => $b->id, 'bundle_price' => 1200,
        ];

        $this->postJson('/api/v1/admin/bundles', $payload)->assertUnauthorized();
        $this->actingAs($this->customer(), 'sanctum')->postJson('/api/v1/admin/bundles', $payload)->assertForbidden();

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/bundles', $payload)
            ->assertCreated()
            ->assertJsonPath('data.name', 'Pair');
    }

    public function test_a_bundle_needs_two_different_products(): void
    {
        $a = $this->product(1000);

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/bundles', [
            'name' => 'Same', 'primary_product_id' => $a->id,
            'secondary_product_id' => $a->id, 'bundle_price' => 500,
        ])->assertStatus(422);
    }

    public function test_admins_can_update_and_delete_a_bundle(): void
    {
        $a = $this->product(1000);
        $b = $this->product(500);
        $deal = $this->bundle($a, $b, 1200);
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/admin/bundles/{$deal->id}", ['bundle_price' => 1100, 'is_active' => false])
            ->assertOk()
            ->assertJsonPath('data.is_active', false);

        $this->assertEquals(1100.0, (float) $deal->fresh()->bundle_price);

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/admin/bundles/{$deal->id}")->assertOk();
        $this->assertNull(BundleDeal::find($deal->id));
    }
}
