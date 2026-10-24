<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\TrackingEvent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The admin's order list: finding the order you are looking for, and seeing who
 * sold what and where it is.
 */
class AdminOrdersTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    private function seller(string $name = null): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(array_filter(['user_id' => $user->id, 'display_name' => $name]));
    }

    private function product(Seller $seller): Product
    {
        $product = Product::factory()->pricedAt(500)->soldBy($seller)->create();
        ProductVariant::factory()->withStock(50)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function buy(Seller $seller, array $overrides = [], ?User $customer = null, string $method = 'COD', string $pincode = '560038', string $city = 'Bengaluru'): Order
    {
        $customer ??= User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $p = $this->product($seller);

        $number = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => ['name' => $customer->name, 'phone' => '9876543210', 'line1' => '1 Main Road', 'city' => $city, 'state' => 'Karnataka', 'pincode' => $pincode],
            'payment_method' => 'COD',
        ])->assertCreated()->json('data.order_number');

        $order = Order::where('order_number', $number)->firstOrFail();
        if ($overrides) {
            $order->update($overrides);
        }

        return $order->fresh();
    }

    private function list(string $query = '')
    {
        return $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/orders'.($query ? "?{$query}" : ''));
    }

    private function numbers($response): array
    {
        return collect($response->assertOk()->json('data'))->pluck('order_number')->sort()->values()->all();
    }

    // ── Filters ──────────────────────────────────────────────────────────

    public function test_orders_can_be_filtered_by_status_payment_and_method(): void
    {
        $s = $this->seller();
        $new = $this->buy($s);
        $shipped = $this->buy($s, ['status' => 'SHIPPED']);
        $paid = $this->buy($s, ['payment_status' => 'PAID', 'payment_method' => 'UPI']);

        $this->assertEqualsCanonicalizing([$shipped->order_number], $this->numbers($this->list('status=SHIPPED')));
        $this->assertEqualsCanonicalizing([$paid->order_number], $this->numbers($this->list('payment_status=PAID')));
        $this->assertEqualsCanonicalizing([$paid->order_number], $this->numbers($this->list('payment_method=UPI')));
        $this->assertCount(3, $this->numbers($this->list()));
        $this->assertContains($new->order_number, $this->numbers($this->list('status=CONFIRMED')));
    }

    public function test_orders_can_be_filtered_by_the_shop_that_sold_something_in_them(): void
    {
        $a = $this->seller('Sharma Kirana');
        $b = $this->seller('Fresh Mart');
        $one = $this->buy($a);
        $two = $this->buy($b);

        $this->assertSame([$one->order_number], $this->numbers($this->list("seller={$a->id}")));
        $this->assertSame([$two->order_number], $this->numbers($this->list("seller={$b->id}")));
    }

    public function test_each_line_says_which_shop_it_is_from(): void
    {
        $this->buy($this->seller('Sharma Kirana'));

        $row = $this->list()->json('data.0');

        $this->assertSame('Sharma Kirana', $row['items'][0]['seller']['display_name']);
    }

    public function test_the_search_finds_an_order_by_number_customer_city_pincode_or_tracking(): void
    {
        $s = $this->seller();
        $priya = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE', 'name' => 'Priya Sharma', 'email' => 'priya@example.test']);
        $target = $this->buy($s, ['tracking_no' => 'AWB777'], $priya, 'COD', '400050', 'Mumbai');
        $other = $this->buy($s);

        foreach (['Priya', 'priya@example', $target->order_number, '400050', 'Mumbai', 'AWB777'] as $term) {
            $this->assertSame([$target->order_number], $this->numbers($this->list('search='.urlencode($term))), "searching for {$term}");
        }

        $this->assertSame([], $this->numbers($this->list('search=nobody-by-this-name')));
        $this->assertNotContains($other->order_number, $this->numbers($this->list('search=Priya')));
    }

    public function test_orders_can_be_limited_to_a_date_range(): void
    {
        $s = $this->seller();
        $old = $this->buy($s);
        $old->forceFill(['created_at' => now()->subDays(20)])->save();
        $recent = $this->buy($s);

        $this->assertSame([$old->order_number], $this->numbers($this->list('to='.now()->subDays(10)->toDateString())));
        $this->assertSame([$recent->order_number], $this->numbers($this->list('from='.now()->subDays(10)->toDateString())));
        $this->assertCount(2, $this->numbers($this->list('from='.now()->subDays(30)->toDateString().'&to='.now()->toDateString())));
    }

    public function test_filters_combine(): void
    {
        $s = $this->seller();
        $this->buy($s, ['status' => 'SHIPPED']);
        $target = $this->buy($s, ['status' => 'SHIPPED', 'payment_method' => 'UPI']);
        $this->buy($s, ['payment_method' => 'UPI']);

        $this->assertSame([$target->order_number], $this->numbers($this->list('status=SHIPPED&payment_method=UPI')));
    }

    public function test_a_bad_date_or_seller_id_is_refused_not_ignored(): void
    {
        $this->list('from=not-a-date')->assertStatus(422)->assertJsonValidationErrors('from');
        $this->list('seller=not-a-uuid')->assertStatus(422)->assertJsonValidationErrors('seller');
    }

    // ── Tabs and paging ──────────────────────────────────────────────────

    public function test_the_status_counts_ignore_the_status_filter_so_every_tab_can_show_its_number(): void
    {
        $s = $this->seller();
        $this->buy($s);
        $this->buy($s);
        $this->buy($s, ['status' => 'SHIPPED']);
        $this->buy($s, ['status' => 'DELIVERED']);

        $counts = $this->list('status=SHIPPED')->assertOk()->json('facets.status');

        $this->assertSame(2, $counts['CONFIRMED']);
        $this->assertSame(1, $counts['SHIPPED']);
        $this->assertSame(1, $counts['DELIVERED']);
    }

    public function test_the_status_counts_respect_the_other_filters(): void
    {
        $s = $this->seller();
        $this->buy($s, ['payment_method' => 'UPI']);
        $this->buy($s);

        $counts = $this->list('payment_method=UPI')->json('facets.status');

        $this->assertSame(['CONFIRMED' => 1], $counts);
    }

    public function test_the_list_is_paged(): void
    {
        $s = $this->seller();
        foreach (range(1, 5) as $_) {
            $this->buy($s);
        }

        $response = $this->list('per_page=2&page=2')->assertOk();

        $this->assertCount(2, $response->json('data'));
        $this->assertSame(5, $response->json('count'));
        $this->assertSame(3, $response->json('meta.last_page'));
        $this->assertSame(2, $response->json('meta.current_page'));
    }

    public function test_newest_orders_come_first(): void
    {
        $s = $this->seller();
        $first = $this->buy($s);
        $first->forceFill(['created_at' => now()->subHour()])->save();
        $second = $this->buy($s);

        $this->assertSame([$second->order_number, $first->order_number], collect($this->list()->json('data'))->pluck('order_number')->all());
    }

    // ── Who may ──────────────────────────────────────────────────────────

    public function test_only_staff_can_list_every_order(): void
    {
        // Before anyone is signed in: nobody at all is refused outright.
        $this->getJson('/api/v1/admin/orders')->assertUnauthorized();

        $s = $this->seller();
        $this->buy($s);
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($customer, 'sanctum')->getJson('/api/v1/admin/orders')->assertForbidden();
        $this->actingAs($s->user, 'sanctum')->getJson('/api/v1/admin/orders')->assertForbidden();
    }

    // ── Tracking, for staff ──────────────────────────────────────────────

    public function test_staff_can_see_where_an_orders_parcel_is(): void
    {
        $order = $this->buy($this->seller(), ['status' => 'SHIPPED', 'tracking_no' => 'AWB123', 'courier' => 'Delhivery', 'carrier' => 'delhivery', 'label_generated' => true]);
        TrackingEvent::create([
            'order_id' => $order->id, 'carrier' => 'delhivery', 'tracking_no' => 'AWB123', 'status' => 'IN_TRANSIT',
            'status_text' => 'In Transit', 'location' => 'Nagpur Hub', 'occurred_at' => now()->subHour(), 'source' => 'webhook',
            'fingerprint' => sha1('a'),
        ]);

        $response = $this->actingAs($this->admin(), 'sanctum')->getJson("/api/v1/admin/orders/{$order->id}/tracking")->assertOk();

        $this->assertSame('AWB123', $response->json('data.tracking_no'));
        $this->assertTrue($response->json('data.label_generated'));
        $this->assertContains('IN_TRANSIT', collect($response->json('data.tracking.events'))->pluck('status')->all());
    }

    public function test_an_order_with_no_booking_says_so_instead_of_failing(): void
    {
        $order = $this->buy($this->seller());

        $this->actingAs($this->admin(), 'sanctum')->getJson("/api/v1/admin/orders/{$order->id}/tracking")
            ->assertOk()
            ->assertJsonPath('data.tracking', null)
            ->assertJsonPath('data.label_generated', false);
    }

    public function test_tracking_is_for_staff_only(): void
    {
        $order = $this->buy($this->seller());
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($customer, 'sanctum')->getJson("/api/v1/admin/orders/{$order->id}/tracking")->assertForbidden();
    }

    public function test_an_unknown_order_is_a_404(): void
    {
        $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/orders/'.\Illuminate\Support\Str::uuid().'/tracking')->assertNotFound();
    }
}
