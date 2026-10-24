<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\User;
use App\Models\WalletTransaction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * The shop's side of an order: accept, promise a time, turn it down.
 *
 * What matters is that a refusal undoes exactly one line: stock back, seller
 * credit reversed, the customer refunded for that line only — and that the
 * order is cancelled in full only when no live line is left.
 */
class SellerOrderDeskTest extends TestCase
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

    private function seller(array $attributes = []): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(['user_id' => $user->id, 'status' => 'ACTIVE'] + $attributes);
    }

    private function productFor(Seller $seller, float $price = 500): Product
    {
        $product = Product::factory()->pricedAt($price)->soldBy($seller)->create();
        ProductVariant::factory()->withStock(10)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function buy(User $user, array $products): Order
    {
        $number = $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => collect($products)->map(fn ($p) => [
                'product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => 1,
            ])->all(),
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ])->assertCreated()->json('data.order_number');

        return Order::with('items')->where('order_number', $number)->firstOrFail();
    }

    private function lineOf(Order $order, Seller $seller): OrderItem
    {
        return $order->fresh('items')->items->firstWhere('seller_id', $seller->id);
    }

    private function act(Seller $seller, string $path, array $body = []): TestResponse
    {
        return $this->actingAs($seller->user, 'sanctum')->postJson("/api/v1/seller/{$path}", $body);
    }

    public function test_a_shop_that_takes_orders_automatically_is_unchanged(): void
    {
        $seller = $this->seller(['prep_minutes' => 20]);
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->assertSame('ACCEPTED', $line->seller_response);
        $this->assertNotNull($line->ready_by);
        $this->act($seller, "order-items/{$line->id}/pack")->assertOk();
    }

    public function test_a_manual_shop_must_accept_before_packing_and_promises_a_time(): void
    {
        $seller = $this->seller(['auto_accept' => false]);
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->assertSame('PENDING', $line->seller_response);
        $this->assertNotNull($line->accept_by);

        $this->act($seller, "order-items/{$line->id}/pack")
            ->assertStatus(422)->assertJsonValidationErrors('fulfilment');

        $queue = $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/order-items?stage=new')->assertOk();
        $this->assertCount(1, $queue->json('data'));
        $this->assertNotEmpty($queue->json('server_time'));

        $this->act($seller, "order-items/{$line->id}/accept", ['prep_minutes' => 25])->assertOk();
        $line->refresh();
        $this->assertSame('ACCEPTED', $line->seller_response);
        $this->assertSame(25, $line->prep_minutes);
        $this->assertNotNull($line->ready_by);

        $this->act($seller, "order-items/{$line->id}/pack")->assertOk();
    }

    public function test_turning_down_the_only_line_cancels_the_order_and_restores_stock(): void
    {
        $seller = $this->seller(['auto_accept' => false]);
        $product = $this->productFor($seller);
        $order = $this->buy($this->customer(), [$product]);
        $line = $this->lineOf($order, $seller);
        $this->assertSame(9, $product->variants->first()->fresh()->stock);

        $this->act($seller, "order-items/{$line->id}/reject", ['reason' => 'CANNOT_PREPARE'])->assertOk();

        $this->assertSame('CANCELLED', $order->fresh()->status);
        $this->assertSame(10, $product->variants->first()->fresh()->stock);
        $this->assertSame('REJECTED', $line->fresh()->seller_response);
        $this->assertSame('CANCELLED', $line->fresh()->fulfilment_status);
    }

    public function test_out_of_stock_reason_stops_selling_the_item(): void
    {
        $seller = $this->seller(['auto_accept' => false]);
        $product = $this->productFor($seller);
        $line = $this->lineOf($this->buy($this->customer(), [$product]), $seller);

        $this->act($seller, "order-items/{$line->id}/reject", ['reason' => 'OUT_OF_STOCK'])->assertOk();

        $this->assertSame(0, $product->variants->first()->fresh()->stock);
    }

    public function test_one_shop_turning_down_its_line_leaves_the_other_shops_order_on_track(): void
    {
        $a = $this->seller(['auto_accept' => false]);
        $b = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($a), $this->productFor($b)]);
        $lineA = $this->lineOf($order, $a);
        $lineB = $this->lineOf($order, $b);

        $this->act($a, "order-items/{$lineA->id}/reject", ['reason' => 'SHOP_CLOSED'])->assertOk();

        $this->assertSame('CONFIRMED', $order->fresh()->status);
        $this->act($b, "order-items/{$lineB->id}/pack")->assertOk();
        // The only live line is packed, so the order is packed — the cancelled one does not hold it back.
        $this->assertSame('PACKED', $order->fresh()->status);

        $this->act($b, "order-items/{$lineB->id}/ship", ['courier' => 'Delhivery', 'tracking_no' => 'DL1'])->assertOk();
        $this->assertSame('SHIPPED', $order->fresh()->status);
    }

    public function test_a_paid_order_refunds_only_the_cancelled_line_then_the_rest_on_the_last(): void
    {
        $a = $this->seller(['auto_accept' => false]);
        $b = $this->seller(['auto_accept' => false]);
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($a, 500), $this->productFor($b, 700)]);
        $order->update(['payment_status' => 'PAID']);
        $lineA = $this->lineOf($order, $a);
        $lineB = $this->lineOf($order, $b);

        $this->act($a, "order-items/{$lineA->id}/reject", ['reason' => 'DAMAGED'])->assertOk();
        $this->assertEqualsWithDelta(500.0, (float) WalletTransaction::where('user_id', $customer->id)->sum('amount'), 0.01);
        $this->assertSame('PAID', $order->fresh()->payment_status);

        $this->act($b, "order-items/{$lineB->id}/reject", ['reason' => 'DAMAGED'])->assertOk();

        $order->refresh();
        $this->assertSame('CANCELLED', $order->status);
        $this->assertEqualsWithDelta(
            (float) $order->total_amount,
            (float) WalletTransaction::where('user_id', $customer->id)->sum('amount'),
            0.01,
        );
    }

    public function test_customer_cancelling_afterwards_does_not_refund_or_restock_a_cancelled_line_twice(): void
    {
        $a = $this->seller(['auto_accept' => false]);
        $b = $this->seller();
        $customer = $this->customer();
        $productA = $this->productFor($a, 500);
        $order = $this->buy($customer, [$productA, $this->productFor($b, 700)]);
        $order->update(['payment_status' => 'PAID']);
        $lineA = $this->lineOf($order, $a);

        $this->act($a, "order-items/{$lineA->id}/reject", ['reason' => 'DAMAGED'])->assertOk();
        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/orders/{$order->id}/cancel")->assertOk();

        $this->assertSame(10, $productA->variants->first()->fresh()->stock);
        $order->refresh();
        $this->assertEqualsWithDelta(
            (float) $order->total_amount,
            (float) WalletTransaction::where('user_id', $customer->id)->sum('amount'),
            0.01,
        );
    }

    public function test_a_shipped_line_cannot_be_turned_down_and_other_shops_lines_are_hidden(): void
    {
        $a = $this->seller();
        $b = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($a), $this->productFor($b)]);
        $lineA = $this->lineOf($order, $a);
        $lineB = $this->lineOf($order, $b);

        $this->act($a, "order-items/{$lineA->id}/ship", ['courier' => 'X', 'tracking_no' => '1'])->assertOk();
        $this->act($a, "order-items/{$lineA->id}/reject", ['reason' => 'OTHER'])->assertStatus(422);
        $this->act($a, "order-items/{$lineB->id}/reject", ['reason' => 'OTHER'])->assertNotFound();
        $this->act($a, "order-items/{$lineA->id}/reject", ['reason' => 'NO_RESPONSE'])->assertStatus(422);
    }

    public function test_unanswered_orders_are_turned_down_by_the_scheduler(): void
    {
        $seller = $this->seller(['auto_accept' => false]);
        $other = $this->seller(['auto_accept' => false]);
        $late = $this->lineOf($this->buy($this->customer(), [$this->productFor($seller)]), $seller);
        $fresh = $this->lineOf($this->buy($this->customer(), [$this->productFor($other)]), $other);
        $late->update(['accept_by' => now()->subMinute()]);

        $this->artisan('orders:expire-unaccepted')->assertSuccessful();

        $this->assertSame('REJECTED', $late->fresh()->seller_response);
        $this->assertSame('SYSTEM', $late->fresh()->rejected_by);
        $this->assertSame('NO_RESPONSE', $late->fresh()->rejection_reason);
        $this->assertSame('PENDING', $fresh->fresh()->seller_response);
    }

    public function test_overview_counts_new_orders_and_the_acceptance_rate(): void
    {
        $seller = $this->seller(['auto_accept' => false]);
        $customer = $this->customer();
        $one = $this->lineOf($this->buy($customer, [$this->productFor($seller)]), $seller);
        $two = $this->lineOf($this->buy($customer, [$this->productFor($seller)]), $seller);
        $this->buy($customer, [$this->productFor($seller)]);

        $this->act($seller, "order-items/{$one->id}/accept")->assertOk();
        $this->act($seller, "order-items/{$two->id}/reject", ['reason' => 'OTHER'])->assertOk();

        $data = $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/overview')->assertOk()->json('data');

        $this->assertSame(1, $data['new_orders']);
        $this->assertSame(1, $data['to_pack']);
        $this->assertSame(1, $data['turned_down_30d']);
        $this->assertEquals(50.0, $data['acceptance_rate_30d']);
    }

    public function test_an_item_can_be_switched_off_for_a_while_and_comes_back_by_itself(): void
    {
        $seller = $this->seller();
        $product = $this->productFor($seller);

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/seller/products/{$product->id}/availability", [
            'available' => false, 'until' => now()->addHours(3)->toIso8601String(),
        ])->assertOk();
        $this->assertSame('OUT_OF_STOCK', $product->fresh()->status);

        $this->artisan('catalog:restore-availability')->assertSuccessful();
        $this->assertSame('OUT_OF_STOCK', $product->fresh()->status);

        $product->forceFill(['available_again_at' => now()->subMinute()])->save();
        $this->artisan('catalog:restore-availability')->assertSuccessful();
        $this->assertSame('ACTIVE', $product->fresh()->status);

        $other = $this->seller();
        $this->actingAs($other->user, 'sanctum')->putJson("/api/v1/seller/products/{$product->id}/availability", ['available' => false])
            ->assertNotFound();
    }

    public function test_a_timed_pause_closes_the_shop_until_it_ends(): void
    {
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', ['pause_minutes' => 90])->assertOk();
        $this->assertFalse($seller->fresh()->isOpenNow());
        $this->assertStringContainsString('Back', $seller->fresh()->closedText());

        $seller->forceFill(['paused_until' => now()->subMinute()])->save();
        $this->assertTrue($seller->fresh()->isOpenNow());

        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', ['pause_minutes' => 30])->assertOk();
        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', ['pause_minutes' => 0])->assertOk();
        $this->assertTrue($seller->fresh()->isOpenNow());
    }

    private function admin(): User
    {
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    public function test_live_board_groups_open_orders_and_flags_late_and_overdue(): void
    {
        $manual = $this->seller(['auto_accept' => false]);
        $auto = $this->seller(['prep_minutes' => 10]);
        $customer = $this->customer();

        $waiting = $this->buy($customer, [$this->productFor($manual)]);
        $late = $this->buy($customer, [$this->productFor($auto)]);
        $this->lineOf($late, $auto)->update(['ready_by' => now()->subMinutes(5)]);
        $late->update(['promised_by' => now()->subMinutes(1)]);
        $this->buy($customer, [$this->productFor($auto)])->update(['status' => 'SHIPPED']);

        $board = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/live-orders')->assertOk()->json();

        $this->assertSame(1, $board['counts']['awaiting_seller']);
        $this->assertSame(1, $board['counts']['to_pack']);
        $this->assertSame(1, $board['counts']['in_transit']);
        $this->assertSame(1, $board['counts']['late_to_pack']);
        $this->assertSame(1, $board['counts']['overdue']);
        $row = collect($board['data'])->firstWhere('order_number', $waiting->order_number);
        $this->assertSame('awaiting_seller', $row['stage']);
        $this->assertNotNull($row['accept_by']);

        $this->actingAs($this->customer(), 'sanctum')->getJson('/api/v1/admin/live-orders')->assertForbidden();
    }

    public function test_admin_can_turn_a_line_down_for_an_unreachable_shop(): void
    {
        $seller = $this->seller(['auto_accept' => false]);
        $line = $this->lineOf($this->buy($this->customer(), [$this->productFor($seller)]), $seller);

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/v1/admin/order-items/{$line->id}/reject", ['reason' => 'SHOP_CLOSED'])->assertOk();

        $line->refresh();
        $this->assertSame('REJECTED', $line->seller_response);
        $this->assertSame('ADMIN', $line->rejected_by);
        $this->assertSame('ADMIN', $line->order->cancelled_by);
        $this->assertSame('SELLER_DECLINED', $line->order->cancellation_code);
    }

    public function test_staff_cancellation_records_a_code_and_customer_cancellation_does_not_need_one(): void
    {
        $seller = $this->seller();
        $customer = $this->customer();
        $one = $this->buy($customer, [$this->productFor($seller)]);
        $two = $this->buy($customer, [$this->productFor($seller)]);

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/v1/orders/{$one->id}/cancel", ['reason_code' => 'FRAUD_SUSPECTED'])->assertOk();
        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/v1/orders/{$two->id}/cancel", ['reason_code' => 'NOT_A_CODE'])->assertStatus(422);

        $this->assertSame('FRAUD_SUSPECTED', $one->fresh()->cancellation_code);
        $this->assertSame('ADMIN', $one->fresh()->cancelled_by);

        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/orders/{$two->id}/cancel")->assertOk();
        $this->assertSame('CUSTOMER_REQUEST', $two->fresh()->cancellation_code);
        $this->assertSame('CUSTOMER', $two->fresh()->cancelled_by);
    }

    public function test_admin_adds_a_product_to_a_chosen_shop_and_the_list_filters_by_shop(): void
    {
        $shop = $this->seller();
        $other = $this->seller();
        $this->productFor($other);
        $admin = $this->admin();

        $payload = [
            'title' => 'Chosen Shop Lamp', 'description' => 'A lamp', 'price' => 900, 'mrp' => 1000,
            'category_id' => \App\Models\Category::factory()->create()->id, 'seller_id' => $shop->id,
            'variants' => [['color' => 'Gold', 'size' => 'M', 'stock' => 5]],
        ];
        $created = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $payload)->assertCreated();
        $this->assertSame($shop->id, $created->json('data.seller_id'));

        $list = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/products?seller='.$shop->id)->assertOk()->json('data');
        $this->assertCount(1, $list);
        $this->assertSame('Chosen Shop Lamp', $list[0]['title']);
    }
}
