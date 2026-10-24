<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\Setting;
use App\Models\TrackingEvent;
use App\Models\User;
use App\Services\Delivery\Tracking\TrackingMode;
use App\Services\Delivery\Tracking\TrackingStatus;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Slow deliveries get a status list and an expected date; fast ones a live map;
 * and whichever partner reports, the shopper sees the same shape.
 */
class ShipmentTrackingTest extends TestCase
{
    use RefreshDatabase;

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    private function order(User $user, array $attributes = []): Order
    {
        return Order::create(array_merge([
            'order_number' => 'ORD-'.strtoupper(substr(md5(uniqid('', true)), 0, 8)),
            'user_id' => $user->id,
            'status' => 'SHIPPED',
            'payment_status' => 'PAID',
            'payment_method' => 'UPI',
            'subtotal' => 1000,
            'discount' => 0,
            'shipping_charge' => 0,
            'total_amount' => 1000,
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'c', 'state' => 's', 'pincode' => '560038'],
        ], $attributes));
    }

    // ── Reading a partner's wording ───────────────────────────────────────

    public function test_partner_phrases_map_onto_our_statuses(): void
    {
        $cases = [
            'Out For Delivery' => TrackingStatus::OUT_FOR_DELIVERY,
            'OFD' => TrackingStatus::OUT_FOR_DELIVERY,
            'Shipment delivered' => TrackingStatus::DELIVERED,
            'Undelivered - customer not available' => TrackingStatus::DELIVERY_FAILED,
            'RTO Initiated' => TrackingStatus::RETURNING,
            'Reached at Mumbai Hub' => TrackingStatus::IN_TRANSIT,
            'in_transit' => TrackingStatus::IN_TRANSIT,
            'Picked up' => TrackingStatus::PICKED_UP,
            'Pickup Scheduled' => TrackingStatus::PACKED,
            'Delayed due to weather' => TrackingStatus::DELAYED,
            'Cancelled by seller' => TrackingStatus::CANCELLED,
        ];

        foreach ($cases as $text => $expected) {
            $this->assertSame($expected, TrackingStatus::fromText($text), $text);
        }

        $this->assertSame(TrackingStatus::IN_TRANSIT, TrackingStatus::fromText('something new'));
        $this->assertSame(TrackingStatus::PACKED, TrackingStatus::fromText('', TrackingStatus::PACKED));
    }

    public function test_a_store_can_teach_it_a_partners_own_phrase(): void
    {
        config(['delivery.status_phrases' => [TrackingStatus::DELIVERED => ['received by consignee']]]);

        $this->assertSame(TrackingStatus::DELIVERED, TrackingStatus::fromText('Shipment received by consignee'));
    }

    // ── Map or list ───────────────────────────────────────────────────────

    public function test_a_two_hour_rider_delivery_gets_a_live_map(): void
    {
        $order = $this->order($this->customer(), [
            'carrier' => 'porter', 'service_level' => 'INSTANT', 'promised_by' => now()->addMinutes(90),
        ]);

        $this->assertSame(TrackingMode::LIVE_MAP, $order->fresh()->tracking_mode);
    }

    public function test_a_multi_day_parcel_gets_status_updates(): void
    {
        $order = $this->order($this->customer(), [
            'carrier' => 'delhivery', 'service_level' => 'STANDARD', 'promised_by' => now()->addDays(4),
        ]);

        $this->assertSame(TrackingMode::STATUS_UPDATES, $order->fresh()->tracking_mode);
    }

    public function test_a_partner_that_never_reports_position_never_gets_a_map(): void
    {
        $order = $this->order($this->customer(), [
            'carrier' => 'shiprocket', 'service_level' => 'EXPRESS', 'promised_by' => now()->addMinutes(60),
        ]);

        $this->assertSame(TrackingMode::STATUS_UPDATES, $order->fresh()->tracking_mode);
    }

    public function test_the_three_hour_cut_off_is_a_setting(): void
    {
        $order = $this->order($this->customer(), [
            'carrier' => 'porter', 'service_level' => 'SAME_DAY', 'promised_by' => now()->addHours(5),
        ]);
        $this->assertSame(TrackingMode::STATUS_UPDATES, $order->fresh()->tracking_mode);

        Setting::put('delivery.live_map_max_minutes', 360);
        $this->assertSame(TrackingMode::LIVE_MAP, $order->fresh()->tracking_mode);
    }

    // ── The tracking answer ───────────────────────────────────────────────

    public function test_a_slow_shipment_comes_back_as_a_timeline_with_an_expected_date(): void
    {
        $user = $this->customer();
        $order = $this->order($user, [
            'tracking_no' => 'AWB1', 'carrier' => 'delhivery', 'courier' => 'Delhivery',
            'service_level' => 'STANDARD', 'promised_by' => now()->addDays(3),
        ]);

        $this->actingAs($user, 'sanctum')
            ->getJson("/api/v1/delivery/orders/{$order->id}/track")
            ->assertOk()
            ->assertJsonPath('data.mode', 'status_updates')
            ->assertJsonPath('data.status', 'IN_TRANSIT')
            ->assertJsonPath('data.status_label', 'In transit')
            ->assertJsonPath('data.position', null)
            ->assertJsonPath('data.track_url', 'https://www.delhivery.com/track/package/AWB1')
            ->assertJsonStructure(['data' => ['expected_by', 'events' => [['status', 'label', 'at']]]]);
    }

    public function test_it_always_has_at_least_the_order_placed_step(): void
    {
        $user = $this->customer();
        $order = $this->order($user, ['status' => 'CONFIRMED']);

        $events = $this->actingAs($user, 'sanctum')
            ->getJson("/api/v1/delivery/orders/{$order->id}/track")
            ->assertOk()
            ->assertJsonPath('data.status', 'CONFIRMED')
            ->json('data.events');

        $this->assertSame('Order confirmed', $events[0]['label']);
    }

    // ── Webhooks ──────────────────────────────────────────────────────────

    private function shipped(): array
    {
        $user = $this->customer();
        $order = $this->order($user, [
            'status' => 'PACKED', 'tracking_no' => 'AWB9', 'carrier' => 'delhivery', 'courier' => 'Delhivery',
            'service_level' => 'STANDARD', 'promised_by' => now()->addDays(3),
        ]);

        return [$user, $order];
    }

    public function test_a_partner_with_no_secret_configured_is_refused(): void
    {
        [, $order] = $this->shipped();

        $this->postJson('/api/v1/webhooks/delivery/delhivery', ['awb' => 'AWB9', 'status' => 'Delivered'])
            ->assertStatus(401);

        $this->assertSame('PACKED', $order->fresh()->status);
        $this->assertSame(0, TrackingEvent::count());
    }

    public function test_a_wrong_token_is_refused(): void
    {
        config(['delivery.carriers.delhivery.webhook_token' => 'right']);
        [, $order] = $this->shipped();

        $this->postJson('/api/v1/webhooks/delivery/delhivery', ['awb' => 'AWB9', 'status' => 'Delivered'], ['X-Api-Key' => 'wrong'])
            ->assertStatus(401);

        $this->assertSame('PACKED', $order->fresh()->status);
    }

    public function test_an_unknown_partner_is_a_404(): void
    {
        $this->postJson('/api/v1/webhooks/nobody', [])->assertNotFound();
    }

    public function test_a_signed_update_is_stored_and_moves_the_order_on(): void
    {
        config(['delivery.carriers.delhivery.webhook_secret' => 'topsecret']);
        [$user, $order] = $this->shipped();

        $body = json_encode([
            'Shipment' => ['AWB' => 'AWB9', 'Status' => [
                'Status' => 'In Transit', 'StatusLocation' => 'Mumbai Hub', 'StatusDateTime' => '2026-10-10T09:30:00',
            ]],
        ]);

        $this->call('POST', '/api/v1/webhooks/delivery/delhivery', [], [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_X_SIGNATURE' => hash_hmac('sha256', $body, 'topsecret'),
        ], $body)->assertOk()->assertJsonPath('accepted', 1);

        $this->assertSame('SHIPPED', $order->fresh()->status);
        $event = TrackingEvent::first();
        $this->assertSame('IN_TRANSIT', $event->status);
        $this->assertSame('Mumbai Hub', $event->location);
        $this->assertSame('webhook', $event->source);

        $this->actingAs($user, 'sanctum')
            ->getJson("/api/v1/delivery/orders/{$order->id}/track")
            ->assertJsonPath('data.location', 'Mumbai Hub');
    }

    public function test_the_same_update_twice_is_one_event(): void
    {
        config(['delivery.carriers.delhivery.webhook_token' => 'tok']);
        $this->shipped();
        $payload = ['awb' => 'AWB9', 'status' => 'Reached at Pune Hub', 'location' => 'Pune', 'timestamp' => '2026-10-10T10:00:00'];

        $this->postJson('/api/v1/webhooks/delivery/delhivery', $payload, ['X-Api-Key' => 'tok'])->assertOk();
        $this->postJson('/api/v1/webhooks/delivery/delhivery', $payload, ['X-Api-Key' => 'tok'])->assertOk();

        $this->assertSame(1, TrackingEvent::count());
    }

    public function test_a_late_or_earlier_update_never_moves_an_order_backwards(): void
    {
        config(['delivery.carriers.delhivery.webhook_token' => 'tok']);
        [, $order] = $this->shipped();
        $order->update(['status' => 'OUT_FOR_DELIVERY']);

        $this->postJson('/api/v1/webhooks/delivery/delhivery', ['awb' => 'AWB9', 'status' => 'In Transit'], ['X-Api-Key' => 'tok'])->assertOk();

        $this->assertSame('OUT_FOR_DELIVERY', $order->fresh()->status);
    }

    public function test_delivered_closes_the_order(): void
    {
        config(['delivery.carriers.delhivery.webhook_token' => 'tok']);
        [, $order] = $this->shipped();

        $this->postJson('/api/v1/webhooks/delivery/delhivery', ['awb' => 'AWB9', 'status' => 'Delivered'], ['X-Api-Key' => 'tok'])->assertOk();

        $this->assertSame('DELIVERED', $order->fresh()->status);
    }

    public function test_a_courier_delivery_does_what_staff_marking_it_delivered_does(): void
    {
        config(['delivery.carriers.delhivery.webhook_token' => 'tok']);
        $order = $this->order($this->customer(), [
            'status' => 'SHIPPED', 'payment_method' => 'COD', 'payment_status' => 'PENDING',
            'tracking_no' => 'AWB9', 'carrier' => 'delhivery', 'courier' => 'Delhivery',
        ]);

        $this->postJson('/api/v1/webhooks/delivery/delhivery', ['awb' => 'AWB9', 'status' => 'Delivered'], ['X-Api-Key' => 'tok'])->assertOk();

        $order = $order->fresh();
        $this->assertSame('DELIVERED', $order->status);
        $this->assertNotNull($order->delivered_at, 'the return window needs a start date');
        $this->assertSame('PAID', $order->payment_status, 'the courier took the cash');
    }

    public function test_a_prepaid_order_stays_as_paid_when_delivered(): void
    {
        config(['delivery.carriers.delhivery.webhook_token' => 'tok']);
        [, $order] = $this->shipped();

        $this->postJson('/api/v1/webhooks/delivery/delhivery', ['awb' => 'AWB9', 'status' => 'Delivered'], ['X-Api-Key' => 'tok'])->assertOk();

        $this->assertSame('PAID', $order->fresh()->payment_status);
        $this->assertNotNull($order->fresh()->delivered_at);
    }

    public function test_an_update_for_an_unknown_waybill_is_acknowledged_and_ignored(): void
    {
        config(['delivery.carriers.delhivery.webhook_token' => 'tok']);
        $this->shipped();

        $this->postJson('/api/v1/webhooks/delivery/delhivery', ['awb' => 'NOPE', 'status' => 'Delivered'], ['X-Api-Key' => 'tok'])
            ->assertOk()
            ->assertJsonPath('accepted', 0);

        $this->assertSame(0, TrackingEvent::count());
    }

    public function test_a_list_of_scans_in_one_push_is_read_one_by_one(): void
    {
        config(['delivery.carriers.shiprocket.webhook_token' => 'tok']);
        $user = $this->customer();
        $order = $this->order($user, [
            'status' => 'PACKED', 'tracking_no' => 'SR7', 'carrier' => 'shiprocket', 'service_level' => 'STANDARD',
            'promised_by' => now()->addDays(4),
        ]);

        $this->postJson('/api/v1/webhooks/delivery/shiprocket', [
            'awb' => 'SR7',
            'scans' => [
                ['status' => 'Picked Up', 'location' => 'Bengaluru', 'date' => '2026-10-10T08:00:00'],
                ['status' => 'In Transit', 'location' => 'Sorting Centre', 'date' => '2026-10-10T14:00:00'],
            ],
        ], ['x-api-key' => 'tok'])->assertOk()->assertJsonPath('accepted', 2);

        $this->assertSame(2, TrackingEvent::count());
        $this->assertSame('SHIPPED', $order->fresh()->status);
    }
}
