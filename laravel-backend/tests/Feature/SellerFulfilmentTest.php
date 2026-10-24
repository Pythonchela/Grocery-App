<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Services\Contracts\LogisticsProvider;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Sellers packing and shipping their own lines.
 *
 * An order can hold goods from several sellers, so fulfilment lives on the line
 * and the order's status is rolled up from its lines. The tests that matter most
 * are the split-order ones: one seller shipping must not make the whole order
 * look shipped, and must not leave it cancellable.
 */
class SellerFulfilmentTest extends TestCase
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

    private function seller(string $status = 'ACTIVE'): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(['user_id' => $user->id, 'status' => $status]);
    }

    private function productFor(Seller $seller, float $price = 1000): Product
    {
        $product = Product::factory()->pricedAt($price)->soldBy($seller)->create();
        ProductVariant::factory()->withStock(20)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    /** One COD order containing a line from each product given. */
    private function buy(User $user, array $products): Order
    {
        $number = $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => collect($products)->map(fn ($p) => [
                'product_id' => $p->id,
                'variant_id' => $p->variants->first()->id,
                'quantity' => 1,
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

    private function pack(Seller $seller, OrderItem $item): TestResponse
    {
        return $this->actingAs($seller->user, 'sanctum')->postJson("/api/v1/seller/order-items/{$item->id}/pack");
    }

    private function ship(Seller $seller, OrderItem $item, array $body = ['courier' => 'Delhivery', 'tracking_no' => 'DL123456789']): TestResponse
    {
        return $this->actingAs($seller->user, 'sanctum')->postJson("/api/v1/seller/order-items/{$item->id}/ship", $body);
    }

    private function titles(User $user): array
    {
        return AppNotification::where('user_id', $user->id)->pluck('title')->all();
    }

    // ── Packing ─────────────────────────────────────────────────────────

    public function test_a_seller_can_pack_their_line(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->pack($seller, $line)
            ->assertOk()
            ->assertJsonPath('data.fulfilment_status', 'PACKED');

        $this->assertNotNull($line->fresh()->packed_at);
        $this->assertNull($line->fresh()->shipped_at);
    }

    public function test_packing_the_only_line_packs_the_order_and_tells_the_customer(): void
    {
        $seller = $this->seller();
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($seller)]);

        $this->pack($seller, $this->lineOf($order, $seller))->assertOk();

        $this->assertSame('PACKED', $order->fresh()->status);
        $this->assertContains("Order {$order->order_number} has been packed", $this->titles($customer));
    }

    public function test_packing_twice_changes_nothing_and_does_not_notify_twice(): void
    {
        $seller = $this->seller();
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->pack($seller, $line)->assertOk();
        $packedAt = $line->fresh()->packed_at;
        $this->pack($seller, $line)->assertOk();

        $this->assertEquals($packedAt, $line->fresh()->packed_at);
        $this->assertCount(1, array_keys($this->titles($customer), "Order {$order->order_number} has been packed"));
    }

    // ── Shipping ────────────────────────────────────────────────────────

    // ── Automatic booking ───────────────────────────────────────────────

    public function test_shipping_with_nothing_typed_books_the_courier_for_the_seller(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->ship($seller, $line, [])->assertOk()->assertJsonPath('data.fulfilment_status', 'SHIPPED');

        $line = $line->fresh();
        $order = $order->fresh();
        $this->assertNotEmpty($line->tracking_no, 'the booking supplied the tracking number');
        $this->assertNotEmpty($line->courier);
        $this->assertTrue($order->label_generated);
        $this->assertSame($line->tracking_no, $order->tracking_no, 'the courier webhooks look orders up by this');
    }

    public function test_two_lines_of_one_order_share_one_booking(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller), $this->productFor($seller)]);
        [$first, $second] = $order->fresh('items')->items->all();

        $this->ship($seller, $first, [])->assertOk();
        $this->ship($seller, $second, [])->assertOk();

        $this->assertSame($first->fresh()->tracking_no, $second->fresh()->tracking_no, 'one parcel, one tracking number');
    }

    public function test_typed_details_still_work_and_book_nothing(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->ship($seller, $line)->assertOk();

        $this->assertSame('DL123456789', $line->fresh()->tracking_no);
        $this->assertFalse($order->fresh()->label_generated, 'nothing was booked through us');
    }

    public function test_only_half_the_details_is_still_refused(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->ship($seller, $line, ['courier' => 'Delhivery'])->assertStatus(422)->assertJsonValidationErrors('tracking_no');
        $this->ship($seller, $line, ['tracking_no' => 'X1'])->assertStatus(422)->assertJsonValidationErrors('courier');
        $this->assertSame('PENDING', $line->fresh()->fulfilment_status);
    }

    public function test_a_failed_booking_ships_nothing_and_says_what_to_do(): void
    {
        $this->app->bind(LogisticsProvider::class, fn () => new class implements LogisticsProvider {
            public function isServiceable(string $pincode): array { return []; }
            public function createShipment(Order $order): array { throw new \RuntimeException('Shiprocket could not assign a courier: wallet balance too low'); }
            public function track(string $trackingNo): array { return []; }
            public function schedulePickup(\App\Models\ReturnRequest $return): array { return []; }
        });
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $response = $this->ship($seller, $line, [])->assertStatus(422)->assertJsonValidationErrors('fulfilment');

        $this->assertStringContainsString('wallet balance too low', $response->json('errors.fulfilment.0'));
        $this->assertStringContainsString('enter the courier and tracking number yourself', $response->json('errors.fulfilment.0'));
        $this->assertSame('PENDING', $line->fresh()->fulfilment_status);
        $this->assertFalse($order->fresh()->label_generated);
    }

    public function test_an_order_with_two_sellers_cannot_be_booked_as_one_parcel(): void
    {
        $a = $this->seller();
        $b = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($a), $this->productFor($b)]);
        $line = $this->lineOf($order, $a);

        $this->ship($a, $line, [])->assertStatus(422)->assertJsonValidationErrors('fulfilment');
        $this->ship($a, $line)->assertOk();   // typing it themselves still works
    }

    public function test_the_seller_app_is_told_whether_shipping_books_by_itself(): void
    {
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/me')->assertJsonPath('data.auto_book', true);
    }

    public function test_the_seller_app_is_told_when_booking_is_switched_off(): void
    {
        config(['delivery.auto_book' => 'off']);
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/me')->assertJsonPath('data.auto_book', false);
    }

    public function test_with_automatic_booking_off_shipping_needs_a_courier_and_a_tracking_number(): void
    {
        config(['delivery.auto_book' => 'off']);
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->ship($seller, $line, [])->assertStatus(422)->assertJsonValidationErrors(['courier', 'tracking_no']);
        $this->ship($seller, $line, ['courier' => 'Delhivery'])->assertStatus(422)->assertJsonValidationErrors('tracking_no');
        $this->ship($seller, $line, ['tracking_no' => 'X1'])->assertStatus(422)->assertJsonValidationErrors('courier');
        $this->ship($seller, $line, ['courier' => str_repeat('a', 81), 'tracking_no' => 'X1'])->assertStatus(422);

        $this->assertSame('PENDING', $line->fresh()->fulfilment_status, 'nothing changed');
    }

    public function test_shipping_records_the_parcel_and_ships_a_single_seller_order(): void
    {
        $seller = $this->seller();
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->ship($seller, $line)
            ->assertOk()
            ->assertJsonPath('data.fulfilment_status', 'SHIPPED')
            ->assertJsonPath('data.courier', 'Delhivery')
            ->assertJsonPath('data.tracking_no', 'DL123456789');

        $this->assertNotNull($line->fresh()->shipped_at);
        $this->assertNotNull($line->fresh()->packed_at, 'shipping implies it was packed');

        $order = $order->fresh();
        $this->assertSame('SHIPPED', $order->status);
        $this->assertSame('Delhivery', $order->courier, 'one parcel, so the order carries its tracking too');
        $this->assertSame('DL123456789', $order->tracking_no);
        $this->assertContains("Order {$order->order_number} has shipped", $this->titles($customer));
    }

    public function test_tracking_details_are_trimmed(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->ship($seller, $line, ['courier' => '  Blue Dart ', 'tracking_no' => ' BD99 '])->assertOk();

        $this->assertSame('Blue Dart', $line->fresh()->courier);
        $this->assertSame('BD99', $line->fresh()->tracking_no);
    }

    public function test_a_mistyped_tracking_number_can_be_corrected_until_the_order_leaves_for_delivery(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->ship($seller, $line, ['courier' => 'Delhivery', 'tracking_no' => 'WRONG'])->assertOk();
        $this->ship($seller, $line, ['courier' => 'Delhivery', 'tracking_no' => 'RIGHT'])->assertOk();

        $this->assertSame('RIGHT', $line->fresh()->tracking_no);

        $order->fresh()->update(['status' => 'OUT_FOR_DELIVERY']);
        $this->ship($seller, $line, ['courier' => 'Delhivery', 'tracking_no' => 'TOO-LATE'])->assertStatus(422);
        $this->assertSame('RIGHT', $line->fresh()->tracking_no);
    }

    public function test_a_shipped_line_cannot_be_packed_again(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->ship($seller, $line)->assertOk();

        $this->pack($seller, $line)->assertStatus(422);
        $this->assertSame('SHIPPED', $line->fresh()->fulfilment_status);
    }

    // ── Orders with more than one seller ────────────────────────────────

    public function test_one_seller_shipping_does_not_ship_the_whole_order(): void
    {
        [$a, $b] = [$this->seller(), $this->seller()];
        $order = $this->buy($this->customer(), [$this->productFor($a), $this->productFor($b)]);

        $this->ship($a, $this->lineOf($order, $a))->assertOk();

        $this->assertSame('CONFIRMED', $order->fresh()->status, 'the other parcel has not even been packed');
        $this->assertNull($order->fresh()->tracking_no);
    }

    public function test_the_order_is_packed_only_once_every_seller_has_packed(): void
    {
        [$a, $b] = [$this->seller(), $this->seller()];
        $order = $this->buy($this->customer(), [$this->productFor($a), $this->productFor($b)]);

        $this->pack($a, $this->lineOf($order, $a))->assertOk();
        $this->assertSame('CONFIRMED', $order->fresh()->status);

        $this->pack($b, $this->lineOf($order, $b))->assertOk();
        $this->assertSame('PACKED', $order->fresh()->status);
    }

    public function test_the_order_ships_once_every_seller_has_shipped_and_keeps_each_parcel_separate(): void
    {
        [$a, $b] = [$this->seller(), $this->seller()];
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($a), $this->productFor($b)]);

        $this->ship($a, $this->lineOf($order, $a), ['courier' => 'Delhivery', 'tracking_no' => 'AAA'])->assertOk();
        $this->ship($b, $this->lineOf($order, $b), ['courier' => 'Blue Dart', 'tracking_no' => 'BBB'])->assertOk();

        $order = $order->fresh('items');
        $this->assertSame('SHIPPED', $order->status);
        $this->assertNull($order->tracking_no, 'two parcels: no single tracking number for the order');
        $this->assertEqualsCanonicalizing(['AAA', 'BBB'], $order->items->pluck('tracking_no')->all());

        // The customer is told once, when the last parcel leaves — not per seller.
        $this->assertCount(1, array_keys($this->titles($customer), "Order {$order->order_number} has shipped"));
    }

    public function test_two_lines_sent_together_share_one_tracking_number_on_the_order(): void
    {
        [$a, $b] = [$this->seller(), $this->seller()];
        $order = $this->buy($this->customer(), [$this->productFor($a), $this->productFor($b)]);

        $same = ['courier' => 'Delhivery', 'tracking_no' => 'SHARED1'];
        $this->ship($a, $this->lineOf($order, $a), $same)->assertOk();
        $this->ship($b, $this->lineOf($order, $b), $same)->assertOk();

        $this->assertSame('SHARED1', $order->fresh()->tracking_no);
    }

    public function test_a_partly_shipped_order_can_no_longer_be_cancelled(): void
    {
        [$a, $b] = [$this->seller(), $this->seller()];
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($a), $this->productFor($b)]);

        $this->ship($a, $this->lineOf($order, $a))->assertOk();

        // The order is still CONFIRMED, but one parcel is already on its way.
        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'Changed my mind'])
            ->assertStatus(422);

        $this->assertSame('CONFIRMED', $order->fresh()->status);
    }

    public function test_an_order_nobody_has_shipped_can_still_be_cancelled(): void
    {
        $seller = $this->seller();
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($seller)]);

        $this->pack($seller, $this->lineOf($order, $seller))->assertOk();

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'Changed my mind'])
            ->assertOk();
    }

    // ── What can't be fulfilled ─────────────────────────────────────────

    public function test_a_cancelled_order_cannot_be_packed_or_shipped(): void
    {
        $seller = $this->seller();
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/orders/{$order->id}/cancel", [])->assertOk();

        $this->pack($seller, $line)->assertStatus(422);
        $this->ship($seller, $line)->assertStatus(422);
        $this->assertSame('PENDING', $line->fresh()->fulfilment_status);
    }

    public function test_a_delivered_order_cannot_be_packed(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $order->update(['status' => 'DELIVERED']);

        $this->pack($seller, $this->lineOf($order, $seller))->assertStatus(422);
    }

    public function test_staff_moving_the_order_carries_its_lines_with_it(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/admin/orders/{$order->id}", ['status' => 'SHIPPED'])
            ->assertOk();

        $this->assertSame('SHIPPED', $line->fresh()->fulfilment_status);
        $this->assertNotNull($line->fresh()->shipped_at);

        // ...so it no longer sits in the seller's "to pack" list.
        $this->actingAs($seller->user, 'sanctum')
            ->getJson('/api/v1/seller/order-items?stage=to_pack')
            ->assertOk()
            ->assertJsonPath('count', 0);
    }

    public function test_fulfilment_does_not_touch_what_the_seller_is_owed(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $before = (float) $seller->fresh()->payout_balance;

        $this->ship($seller, $this->lineOf($order, $seller))->assertOk();

        $this->assertEquals($before, (float) $seller->fresh()->payout_balance);
    }

    // ── Who may do it ───────────────────────────────────────────────────

    public function test_a_seller_cannot_pack_or_ship_another_sellers_line(): void
    {
        [$mine, $theirs] = [$this->seller(), $this->seller()];
        $order = $this->buy($this->customer(), [$this->productFor($theirs)]);
        $line = $this->lineOf($order, $theirs);

        // 404, the same answer as for a line that does not exist, so ids cannot be probed.
        $this->pack($mine, $line)->assertNotFound();
        $this->ship($mine, $line)->assertNotFound();

        $this->assertSame('PENDING', $line->fresh()->fulfilment_status);
    }

    public function test_a_customer_cannot_pack_or_ship(): void
    {
        $seller = $this->seller();
        $customer = $this->customer();
        $line = $this->lineOf($this->buy($customer, [$this->productFor($seller)]), $seller);

        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/seller/order-items/{$line->id}/pack")->assertForbidden();
        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/seller/order-items/{$line->id}/ship", ['courier' => 'x', 'tracking_no' => 'y'])->assertForbidden();
    }

    public function test_an_anonymous_caller_is_refused(): void
    {
        $this->postJson('/api/v1/seller/order-items/anything/pack')->assertUnauthorized();
    }

    public function test_a_suspended_seller_cannot_ship(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $line = $this->lineOf($order, $seller);

        $seller->update(['status' => 'SUSPENDED']);

        $this->ship($seller, $line)->assertForbidden();
        $this->assertSame('PENDING', $line->fresh()->fulfilment_status);
    }

    public function test_a_pending_seller_cannot_ship(): void
    {
        $seller = $this->seller();
        $line = $this->lineOf($this->buy($this->customer(), [$this->productFor($seller)]), $seller);
        $seller->update(['status' => 'PENDING']);

        $this->pack($seller, $line)->assertForbidden();
    }

    // ── Lists ───────────────────────────────────────────────────────────

    public function test_the_stage_filter_sorts_lines_into_the_sellers_workflow(): void
    {
        $seller = $this->seller();
        $customer = $this->customer();
        $product = $this->productFor($seller);

        $toPack = $this->buy($customer, [$product]);
        $packed = $this->buy($customer, [$product]);
        $shipped = $this->buy($customer, [$product]);
        $delivered = $this->buy($customer, [$product]);
        $cancelled = $this->buy($customer, [$product]);

        // Two sellers on one order keeps the parcels on different stages visible.
        $this->pack($seller, $this->lineOf($packed, $seller))->assertOk();
        $this->ship($seller, $this->lineOf($shipped, $seller))->assertOk();
        $delivered->update(['status' => 'DELIVERED']);
        $cancelled->update(['status' => 'CANCELLED']);

        $stage = fn (string $s) => $this->actingAs($seller->user, 'sanctum')
            ->getJson("/api/v1/seller/order-items?stage={$s}")->assertOk()
            ->collect('data')->pluck('order.order_number')->all();

        $this->assertSame([$toPack->order_number], $stage('to_pack'));
        $this->assertSame([$packed->order_number], $stage('packed'));
        $this->assertSame([$shipped->order_number], $stage('shipped'));
        $this->assertSame([$delivered->order_number], $stage('delivered'));
        $this->assertSame([$cancelled->order_number], $stage('cancelled'));
    }

    public function test_the_list_carries_the_fulfilment_fields(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->customer(), [$this->productFor($seller)]);
        $this->ship($seller, $this->lineOf($order, $seller))->assertOk();

        $row = $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/order-items')->json('data.0');

        $this->assertSame('SHIPPED', $row['fulfilment_status']);
        $this->assertSame('Delhivery', $row['courier']);
        $this->assertSame('DL123456789', $row['tracking_no']);
        $this->assertNotNull($row['shipped_at']);
    }

    public function test_a_customer_sees_the_tracking_for_each_parcel_of_their_order(): void
    {
        [$a, $b] = [$this->seller(), $this->seller()];
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($a), $this->productFor($b)]);
        $this->ship($a, $this->lineOf($order, $a), ['courier' => 'Delhivery', 'tracking_no' => 'AAA'])->assertOk();

        $items = collect(
            $this->actingAs($customer, 'sanctum')->getJson("/api/v1/orders/{$order->id}")->assertOk()->json('data.items')
        );

        $shipped = $items->firstWhere('seller_id', $a->id);
        $waiting = $items->firstWhere('seller_id', $b->id);

        $this->assertSame('SHIPPED', $shipped['fulfilment_status']);
        $this->assertSame('AAA', $shipped['tracking_no']);
        $this->assertSame('PENDING', $waiting['fulfilment_status']);
        $this->assertNull($waiting['tracking_no']);
    }
}
