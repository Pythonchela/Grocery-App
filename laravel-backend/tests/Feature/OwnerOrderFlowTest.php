<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\ReturnRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The whole life of an order in a single-business store, as the people in it see
 * it: a shopper orders, the owner handles it in the admin, the shopper follows it.
 *
 * Each step is the call the website's admin or the phone app makes.
 */
class OwnerOrderFlowTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
        'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
    ];

    private function owner(): User
    {
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    private function shopper(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    private function product(float $price = 1000, int $stock = 10): Product
    {
        $product = Product::factory()->pricedAt($price)->create(['cod_available' => true]);
        ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function order(User $shopper, Product $product, int $quantity = 1): Order
    {
        $number = $this->actingAs($shopper, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $product->id, 'variant_id' => $product->variants->first()->id, 'quantity' => $quantity]],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ])->assertCreated()->json('data.order_number');

        return Order::with('items')->where('order_number', $number)->firstOrFail();
    }

    private function move(User $owner, Order $order, string $status)
    {
        return $this->actingAs($owner, 'sanctum')->putJson("/api/v1/admin/orders/{$order->id}", ['status' => $status]);
    }

    // ── From order to doorstep ───────────────────────────────────────────

    public function test_an_order_goes_from_the_shopper_to_delivered_through_the_owners_screens(): void
    {
        $owner = $this->owner();
        $shopper = $this->shopper();
        $product = $this->product(1000, stock: 10);
        $variant = $product->variants->first();

        // The shopper orders. It is confirmed at once (the store takes orders automatically) and the stock is held.
        $order = $this->order($shopper, $product, 2);
        $this->assertSame('CONFIRMED', $order->status);
        $this->assertSame('PENDING', $order->payment_status);
        $this->assertSame(8, $variant->fresh()->stock);

        // The owner finds it in the orders list and on the live board.
        $this->actingAs($owner, 'sanctum')->getJson('/api/v1/admin/orders')->assertOk()
            ->assertJsonFragment(['order_number' => $order->order_number]);
        $board = $this->actingAs($owner, 'sanctum')->getJson('/api/v1/admin/live-orders')->assertOk();
        $this->assertSame(1, count($board->json('data')));
        $this->assertSame(1, $board->json('counts.to_pack'));

        // Packed, then the courier is booked.
        $this->move($owner, $order, 'PACKED')->assertOk();
        $this->actingAs($owner, 'sanctum')->postJson("/api/v1/admin/orders/{$order->id}/shipment")
            ->assertOk()->assertJsonPath('status', 'success');
        $this->assertNotEmpty($order->fresh()->tracking_no, 'a booked parcel has a tracking number');

        // The shopper sees where it is at each step, and is told.
        foreach (['SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED'] as $status) {
            $this->move($owner, $order, $status)->assertOk();

            $this->actingAs($shopper, 'sanctum')->getJson("/api/v1/orders/{$order->id}")
                ->assertOk()->assertJsonPath('data.status', $status);
        }

        // Cash is collected at the door, so a delivered cash order is paid, and the return window starts.
        $delivered = $order->fresh();
        $this->assertSame('PAID', $delivered->payment_status);
        $this->assertNotNull($delivered->delivered_at);
        $this->assertGreaterThanOrEqual(1, AppNotification::where('user_id', $shopper->id)->count());

        // Delivered orders leave the live board.
        $this->assertSame(0, count($this->actingAs($owner, 'sanctum')->getJson('/api/v1/admin/live-orders')->json('data')));

        // And the shopper's own list shows it.
        $this->actingAs($shopper, 'sanctum')->getJson('/api/v1/orders/mine')->assertOk()
            ->assertJsonFragment(['order_number' => $order->order_number]);
    }

    public function test_status_counts_on_the_orders_screen_follow_each_move(): void
    {
        $owner = $this->owner();
        $order = $this->order($this->shopper(), $this->product());

        $counts = fn () => $this->actingAs($owner, 'sanctum')->getJson('/api/v1/admin/orders')->json('facets.status');

        $this->assertSame(1, $counts()['CONFIRMED']);

        $this->move($owner, $order, 'PACKED')->assertOk();
        $after = $counts();
        $this->assertSame(1, $after['PACKED']);
        $this->assertSame(0, $after['CONFIRMED'] ?? 0);
    }

    // ── Cancelling ───────────────────────────────────────────────────────

    public function test_the_owner_can_cancel_an_order_before_it_ships_and_the_stock_comes_back(): void
    {
        $owner = $this->owner();
        $product = $this->product(1000, stock: 10);
        $variant = $product->variants->first();
        $order = $this->order($this->shopper(), $product, 3);
        $this->assertSame(7, $variant->fresh()->stock);

        $this->actingAs($owner, 'sanctum')->postJson("/api/v1/orders/{$order->id}/cancel", ['reason_code' => 'OUT_OF_STOCK'])
            ->assertOk();

        $this->assertSame('CANCELLED', $order->fresh()->status);
        $this->assertSame('ADMIN', $order->fresh()->cancelled_by);
        $this->assertSame('OUT_OF_STOCK', $order->fresh()->cancellation_code);
        $this->assertSame(10, $variant->fresh()->stock);
        $this->assertSame(0, count($this->actingAs($owner, 'sanctum')->getJson('/api/v1/admin/live-orders')->json('data')));
    }

    public function test_an_order_that_has_gone_out_can_no_longer_be_cancelled(): void
    {
        $owner = $this->owner();
        $order = $this->order($this->shopper(), $this->product());
        $this->move($owner, $order, 'SHIPPED')->assertOk();

        $this->actingAs($owner, 'sanctum')->postJson("/api/v1/orders/{$order->id}/cancel", ['reason_code' => 'OTHER'])
            ->assertStatus(422);
    }

    // ── After delivery ───────────────────────────────────────────────────

    public function test_a_delivered_order_can_be_returned_and_the_owner_refunds_it(): void
    {
        $owner = $this->owner();
        $shopper = $this->shopper();
        $product = $this->product(1000, stock: 10);
        $variant = $product->variants->first();
        $order = $this->order($shopper, $product);
        $this->move($owner, $order, 'DELIVERED')->assertOk();
        $this->assertSame(9, $variant->fresh()->stock);

        // The shopper asks for a return from the phone.
        $this->actingAs($shopper, 'sanctum')->postJson('/api/v1/returns', [
            'order_item_id' => $order->items->first()->id,
            'kind' => 'RETURN',
            'reason' => 'Did not fit',
        ])->assertCreated();
        $return = ReturnRequest::firstOrFail();
        $this->assertSame('REQUESTED', $return->status);

        // The owner works through it in the Returns screen.
        $this->actingAs($owner, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/approve")->assertOk();
        $this->actingAs($owner, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/picked-up")->assertOk();
        $this->actingAs($owner, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/refund")->assertOk();

        $this->assertSame('REFUNDED', $return->fresh()->status);
        $this->assertSame(10, $variant->fresh()->stock, 'the returned unit is back on the shelf');
        $this->assertEquals(1000.0, (float) $shopper->fresh()->wallet_balance, 'cash orders are refunded to the wallet');
    }

    public function test_the_owner_can_turn_down_a_return(): void
    {
        $owner = $this->owner();
        $shopper = $this->shopper();
        $order = $this->order($shopper, $this->product());
        $this->move($owner, $order, 'DELIVERED')->assertOk();
        $this->actingAs($shopper, 'sanctum')->postJson('/api/v1/returns', [
            'order_item_id' => $order->items->first()->id, 'kind' => 'RETURN', 'reason' => 'Changed my mind',
        ])->assertCreated();
        $return = ReturnRequest::firstOrFail();

        $this->actingAs($owner, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/reject", ['admin_note' => 'Worn and washed.'])
            ->assertOk();

        $this->assertSame('REJECTED', $return->fresh()->status);
        $this->assertEquals(0.0, (float) $shopper->fresh()->wallet_balance);
    }

    // ── Who may do any of it ─────────────────────────────────────────────

    public function test_shoppers_cannot_use_the_owners_order_screens(): void
    {
        $shopper = $this->shopper();
        $order = $this->order($shopper, $this->product());

        $this->actingAs($shopper, 'sanctum');
        $this->getJson('/api/v1/admin/orders')->assertForbidden();
        $this->getJson('/api/v1/admin/live-orders')->assertForbidden();
        $this->putJson("/api/v1/admin/orders/{$order->id}", ['status' => 'DELIVERED'])->assertForbidden();
        $this->postJson("/api/v1/admin/orders/{$order->id}/shipment")->assertForbidden();
        $this->postJson('/api/v1/admin/returns/1/approve')->assertForbidden();

        $this->assertSame('CONFIRMED', $order->fresh()->status);
    }

    public function test_a_shopper_only_sees_their_own_orders(): void
    {
        $mine = $this->shopper();
        $theirs = $this->shopper();
        $order = $this->order($theirs, $this->product());

        $this->actingAs($mine, 'sanctum')->getJson("/api/v1/orders/{$order->id}")->assertForbidden();
        $this->actingAs($mine, 'sanctum')->getJson('/api/v1/orders/mine')->assertOk()
            ->assertJsonMissing(['order_number' => $order->order_number]);
    }
}
