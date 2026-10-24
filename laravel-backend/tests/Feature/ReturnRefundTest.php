<?php

namespace Tests\Feature;

use App\Models\Coupon;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\ReturnRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Refunds have to pay back what was actually paid.
 *
 * Refunding `order_items.price` looked right and was quietly a discount
 * laundering machine: buy at 40% off, return, receive the list price. The fix
 * records each line's share of the order-level discount at purchase time, and
 * these tests hold that arithmetic in place.
 */
class ReturnRefundTest extends TestCase
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
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    private function product(float $price, int $stock = 50): Product
    {
        $product = Product::factory()->pricedAt($price)->create();
        ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    /** Places a COD order and marks it delivered, ready to be returned against. */
    private function deliveredOrder(User $user, Product $product, int $qty = 1, ?string $coupon = null): Order
    {
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [[
                'product_id' => $product->id,
                'variant_id' => $product->variants->first()->id,
                'quantity' => $qty,
            ]],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
            'coupon_code' => $coupon,
        ])->assertCreated();

        $order = Order::with('items')->latest('id')->firstOrFail();
        $order->update(['status' => 'DELIVERED', 'delivered_at' => now()->subDay()]);

        return $order->fresh('items');
    }

    private function requestReturn(User $user, Order $order, array $overrides = []): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/returns', array_merge([
            'order_item_id' => $order->items->first()->id,
            'kind' => 'RETURN',
            'reason' => 'Did not fit',
        ], $overrides));
    }

    // ── Refund arithmetic ───────────────────────────────────────────────

    public function test_a_return_refunds_the_discounted_price_not_the_list_price(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);
        Coupon::factory()->percent(10)->create(['code' => 'TEN']);

        $order = $this->deliveredOrder($user, $product, 1, 'TEN');
        $this->assertEquals(100.0, (float) $order->discount);

        $this->requestReturn($user, $order)->assertCreated();

        // ₹1,000 list, ₹100 discount allocated to the line → ₹900 was paid.
        $this->assertEquals(900.0, (float) ReturnRequest::first()->refund_amount);
    }

    public function test_an_undiscounted_return_still_refunds_the_full_price(): void
    {
        $user = $this->customer();
        $product = $this->product(1500);

        $order = $this->deliveredOrder($user, $product);
        $this->requestReturn($user, $order)->assertCreated();

        $this->assertEquals(1500.0, (float) ReturnRequest::first()->refund_amount);
    }

    public function test_a_partial_return_refunds_only_that_units_share(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);
        Coupon::factory()->percent(10)->create(['code' => 'TEN']);

        // Two units at ₹1,000, ₹200 discount over the line → ₹900 paid per unit.
        $order = $this->deliveredOrder($user, $product, 2, 'TEN');
        $this->assertEquals(200.0, (float) $order->discount);

        $this->requestReturn($user, $order, ['quantity' => 1])->assertCreated();

        $this->assertEquals(900.0, (float) ReturnRequest::first()->refund_amount);
    }

    public function test_a_wallet_refund_credits_exactly_the_discounted_amount(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);
        Coupon::factory()->percent(10)->create(['code' => 'TEN']);

        $order = $this->deliveredOrder($user, $product, 1, 'TEN');
        $this->requestReturn($user, $order, ['refund_mode' => 'WALLET'])->assertCreated();

        $return = ReturnRequest::first();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/approve")->assertOk();
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/picked-up")->assertOk();
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/refund", ['refund_mode' => 'WALLET'])->assertOk();

        $this->assertEquals(900.0, (float) $user->fresh()->wallet_balance);
        $this->assertSame('COMPLETED', $return->fresh()->refund_status);
    }

    public function test_a_refunded_return_restocks_the_units(): void
    {
        $user = $this->customer();
        $product = $this->product(1000, stock: 10);
        $variant = $product->variants->first();

        $order = $this->deliveredOrder($user, $product, 2);
        $this->assertSame(8, $variant->fresh()->stock);

        $this->requestReturn($user, $order, ['quantity' => 2, 'refund_mode' => 'WALLET'])->assertCreated();
        $return = ReturnRequest::first();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/approve");
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/picked-up");
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/refund");

        $this->assertSame(10, $variant->fresh()->stock);
    }

    public function test_a_refund_cannot_be_issued_twice(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);
        $order = $this->deliveredOrder($user, $product);

        $this->requestReturn($user, $order, ['refund_mode' => 'WALLET'])->assertCreated();
        $return = ReturnRequest::first();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/approve");
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/picked-up");
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/refund")->assertOk();

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/refund")->assertStatus(422);

        $this->assertEquals(1000.0, (float) $user->fresh()->wallet_balance);
    }

    // ── Exchanges ───────────────────────────────────────────────────────

    public function test_an_exchange_creates_a_valid_replacement_order(): void
    {
        $user = $this->customer();
        $product = $this->product(1000, stock: 10);
        $replacement = ProductVariant::factory()->withStock(5)
            ->create(['product_id' => $product->id, 'size' => 'L']);

        $order = $this->deliveredOrder($user, $product);

        $this->requestReturn($user, $order, [
            'kind' => 'EXCHANGE',
            'exchange_variant_id' => $replacement->id,
        ])->assertCreated();

        $return = ReturnRequest::first();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/approve");
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/picked-up");
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/refund")->assertOk();

        $exchange = Order::where('payment_method', 'EXCHANGE')->first();

        $this->assertNotNull($exchange, 'an exchange order should have been created');
        $this->assertStringStartsWith('EXC-', $exchange->order_number);
        $this->assertEquals(0.0, (float) $exchange->total_amount);
        // The not-null snapshot that used to blow this whole path up.
        $this->assertNotNull($exchange->shipping_address);
        $this->assertSame(self::ADDRESS['pincode'], $exchange->shipping_address['pincode']);
        $this->assertSame($replacement->id, $exchange->items->first()->variant_id);

        $this->assertSame(4, $replacement->fresh()->stock);
        $this->assertSame('EXCHANGED', $return->fresh()->status);
    }

    public function test_an_exchange_is_refused_when_the_replacement_is_out_of_stock(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);
        $replacement = ProductVariant::factory()->withStock(0)
            ->create(['product_id' => $product->id, 'size' => 'XL']);

        $order = $this->deliveredOrder($user, $product);

        $this->requestReturn($user, $order, [
            'kind' => 'EXCHANGE',
            'exchange_variant_id' => $replacement->id,
        ])->assertCreated();

        $return = ReturnRequest::first();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/approve");
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/picked-up");
        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/refund")->assertStatus(422);

        $this->assertSame(0, Order::where('payment_method', 'EXCHANGE')->count());
        $this->assertSame(0, $replacement->fresh()->stock);
    }

    public function test_an_exchange_requires_a_replacement_variant(): void
    {
        $user = $this->customer();
        $order = $this->deliveredOrder($user, $this->product(1000));

        $this->requestReturn($user, $order, ['kind' => 'EXCHANGE'])->assertStatus(422);
    }

    // ── Eligibility ─────────────────────────────────────────────────────

    public function test_an_undelivered_order_cannot_be_returned(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);
        $order = $this->deliveredOrder($user, $product);
        $order->update(['status' => 'SHIPPED', 'delivered_at' => null]);

        $this->requestReturn($user, $order->fresh('items'))->assertStatus(422);
        $this->assertSame(0, ReturnRequest::count());
    }

    public function test_a_return_outside_the_window_is_refused(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);
        $order = $this->deliveredOrder($user, $product);
        $order->update(['delivered_at' => now()->subDays(30)]);

        $this->requestReturn($user, $order->fresh('items'))->assertStatus(422);
        $this->assertSame(0, ReturnRequest::count());
    }

    public function test_a_second_open_return_on_the_same_item_is_refused(): void
    {
        $user = $this->customer();
        $order = $this->deliveredOrder($user, $this->product(1000));

        $this->requestReturn($user, $order)->assertCreated();
        $this->requestReturn($user, $order)->assertStatus(409);

        $this->assertSame(1, ReturnRequest::count());
    }

    public function test_returning_more_than_was_ordered_is_refused(): void
    {
        $user = $this->customer();
        $order = $this->deliveredOrder($user, $this->product(1000), 2);

        $this->requestReturn($user, $order, ['quantity' => 5])->assertStatus(422);
        $this->assertSame(0, ReturnRequest::count());
    }

    public function test_a_user_cannot_open_a_return_on_someone_elses_order(): void
    {
        $owner = $this->customer();
        $stranger = $this->customer();
        $order = $this->deliveredOrder($owner, $this->product(1000));

        $this->requestReturn($stranger, $order)->assertStatus(403);
        $this->assertSame(0, ReturnRequest::count());
    }

    public function test_return_moderation_is_staff_only(): void
    {
        $user = $this->customer();
        $order = $this->deliveredOrder($user, $this->product(1000));
        $this->requestReturn($user, $order)->assertCreated();

        $return = ReturnRequest::first();

        $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/approve")->assertForbidden();
        $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/admin/returns/{$return->id}/refund")->assertForbidden();
    }
}
