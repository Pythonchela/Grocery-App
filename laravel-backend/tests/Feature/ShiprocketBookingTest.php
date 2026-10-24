<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\User;
use App\Services\Contracts\LogisticsProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Shiprocket books in four calls: create the order, assign a courier (the
 * tracking number, and the charge), request a pickup, make the label. These
 * check the sequence against faked responses; nothing here reaches Shiprocket.
 */
class ShiprocketBookingTest extends TestCase
{
    use RefreshDatabase;

    private function order(array $attributes = []): Order
    {
        $seller = Seller::factory()->create(['user_id' => User::factory()->create(['role' => User::ROLE_SELLER])->id]);
        $product = Product::factory()->pricedAt(1000)->soldBy($seller)->create();
        ProductVariant::factory()->withStock(5)->create(['product_id' => $product->id]);
        $customer = User::factory()->create(['role' => 'CUSTOMER']);

        $order = Order::create(array_merge([
            'order_number' => 'ORD-'.strtoupper(substr(md5(uniqid('', true)), 0, 8)),
            'user_id' => $customer->id,
            'status' => 'CONFIRMED',
            'payment_status' => 'PAID',
            'payment_method' => 'UPI',
            'subtotal' => 1000, 'discount' => 0, 'shipping_charge' => 0, 'total_amount' => 1000,
            'service_level' => 'STANDARD',
            'carrier' => 'shiprocket',
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038'],
        ], $attributes));

        $order->items()->create([
            'product_id' => $product->id, 'variant_id' => $product->variants->first()?->id,
            'seller_id' => $seller->id, 'quantity' => 1, 'price' => 1000,
        ]);

        return $order->fresh();
    }

    private function live(array $overrides = []): void
    {
        Cache::flush();
        config([
            'delivery.carriers.shiprocket.email' => 'api@example.test',
            'delivery.carriers.shiprocket.password' => 'secret',
        ]);

        Http::fake($overrides + [
            '*/auth/login' => Http::response(['token' => 'tok']),
            '*/courier/serviceability/*' => Http::response(['data' => ['available_courier_companies' => [
                ['courier_name' => 'Pricey Air', 'courier_company_id' => 11, 'rate' => 400, 'estimated_delivery_days' => 4, 'cod' => 1],
                ['courier_name' => 'Delhivery Surface', 'courier_company_id' => 7, 'rate' => 120, 'estimated_delivery_days' => 4, 'cod' => 1],
            ]]]),
            '*/orders/create/adhoc' => Http::response(['order_id' => 5001, 'shipment_id' => 9001]),
            '*/courier/assign/awb' => Http::response(['awb_assign_status' => 1, 'response' => ['data' => ['awb_code' => 'AWB123', 'courier_name' => 'Delhivery Surface']]]),
            '*/courier/generate/pickup' => Http::response(['pickup_status' => 1]),
            '*/courier/generate/label' => Http::response(['label_created' => 1, 'label_url' => 'https://labels.example/9001.pdf']),
        ]);
    }

    private function paths(): array
    {
        return Http::recorded()->map(fn (array $pair) => parse_url($pair[0]->url(), PHP_URL_PATH))->values()->all();
    }

    public function test_it_creates_assigns_requests_pickup_and_makes_the_label_in_that_order(): void
    {
        $this->live();
        $order = $this->order();

        $booking = app(LogisticsProvider::class)->createShipment($order);

        $this->assertSame('AWB123', $booking['tracking_no'], 'the tracking number comes from assigning a courier');
        $this->assertSame('Delhivery Surface', $booking['courier']);
        $this->assertSame('https://labels.example/9001.pdf', $booking['label_url']);

        $calls = array_values(array_filter($this->paths(), fn ($p) => ! str_contains($p, 'serviceability') && ! str_contains($p, 'auth/login')));
        $this->assertSame([
            '/v1/external/orders/create/adhoc',
            '/v1/external/courier/assign/awb',
            '/v1/external/courier/generate/pickup',
            '/v1/external/courier/generate/label',
        ], $calls);
    }

    public function test_it_books_the_cheapest_courier_for_the_speed_that_was_paid_for(): void
    {
        $this->live();

        app(LogisticsProvider::class)->createShipment($this->order());

        Http::assertSent(fn (Request $r) => str_contains($r->url(), 'courier/assign/awb')
            && $r['shipment_id'] == '9001'
            && $r['courier_id'] === 7);   // not the Rs 400 courier
    }

    public function test_the_shipment_id_is_remembered_so_a_retry_does_not_create_a_second_order(): void
    {
        // The wallet is empty the first time and topped up for the second try.
        $this->live(['*/courier/assign/awb' => Http::sequence()
            ->push(['message' => 'Insufficient wallet balance'], 422)
            ->push(['awb_assign_status' => 1, 'response' => ['data' => ['awb_code' => 'AWB123', 'courier_name' => 'Delhivery Surface']]])]);
        $order = $this->order();

        try {
            app(LogisticsProvider::class)->createShipment($order);
            $this->fail('assigning a courier failed, so booking should have failed');
        } catch (\RuntimeException $e) {
            $this->assertStringContainsString('Insufficient wallet balance', $e->getMessage());
        }
        $this->assertSame('9001', $order->fresh()->carrier_shipment_id);

        $booking = app(LogisticsProvider::class)->createShipment($order->fresh());

        $this->assertSame('AWB123', $booking['tracking_no']);
        $this->assertCount(1, array_filter($this->paths(), fn ($p) => str_contains($p, 'orders/create/adhoc')), 'one Shiprocket order, not two');
    }

    public function test_a_pickup_or_label_that_fails_does_not_undo_a_paid_for_booking(): void
    {
        $this->live([
            '*/courier/generate/pickup' => Http::response(['message' => 'down'], 500),
            '*/courier/generate/label' => Http::response(['message' => 'down'], 500),
        ]);

        $booking = app(LogisticsProvider::class)->createShipment($this->order());

        $this->assertSame('AWB123', $booking['tracking_no']);
        $this->assertNull($booking['label_url']);
    }

    public function test_a_response_with_no_tracking_number_is_a_failed_booking(): void
    {
        $this->live(['*/courier/assign/awb' => Http::response(['awb_assign_status' => 0, 'message' => 'Courier not serviceable'])]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Courier not serviceable');

        app(LogisticsProvider::class)->createShipment($this->order());
    }

    public function test_asking_to_book_twice_books_once(): void
    {
        $this->live();
        $order = $this->order();
        $booker = app(\App\Services\Delivery\ShipmentBooker::class);

        $first = $booker->book($order);
        $second = $booker->book($order->fresh());

        $this->assertFalse($first['already_booked']);
        $this->assertTrue($second['already_booked']);
        $this->assertSame($first['tracking_no'], $second['tracking_no']);
        $this->assertCount(1, array_filter($this->paths(), fn ($p) => str_contains($p, 'courier/assign/awb')), 'the wallet was charged once');
    }

    public function test_the_admin_button_does_not_book_a_second_time_either(): void
    {
        $this->live();
        $order = $this->order();
        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);

        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/orders/{$order->id}/shipment")->assertOk();
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/orders/{$order->id}/shipment")->assertOk()
            ->assertJsonPath('shipment.already_booked', true);

        $this->assertCount(1, array_filter($this->paths(), fn ($p) => str_contains($p, 'courier/assign/awb')));
    }
}
