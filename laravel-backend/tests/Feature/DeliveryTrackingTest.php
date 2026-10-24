<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tracking a dispatched order must work: this is the screen a shopper opens most
 * while waiting for a delivery.
 */
class DeliveryTrackingTest extends TestCase
{
    use RefreshDatabase;

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

    public function test_a_dispatched_order_with_a_promised_time_can_be_tracked(): void
    {
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $promised = now()->addMinutes(40);
        $order = $this->order($user, [
            'tracking_no' => 'TRK-1',
            'carrier' => 'porter',
            'courier' => 'Porter',
            'service_level' => 'INSTANT',
            'promised_by' => $promised,
        ]);

        $response = $this->actingAs($user, 'sanctum')
            ->getJson("/api/v1/delivery/orders/{$order->id}/track")
            ->assertOk();

        $response->assertJsonPath('data.tracking_no', 'TRK-1');
        $this->assertSame(
            $promised->toIso8601String(),
            \Illuminate\Support\Carbon::parse($response->json('data.promised_by'))->toIso8601String(),
        );
    }

    public function test_an_order_with_no_promised_time_can_still_be_tracked(): void
    {
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $order = $this->order($user, ['tracking_no' => 'TRK-2', 'carrier' => 'porter']);

        $this->actingAs($user, 'sanctum')
            ->getJson("/api/v1/delivery/orders/{$order->id}/track")
            ->assertOk()
            ->assertJsonPath('data.promised_by', null);
    }

    public function test_an_order_not_yet_dispatched_says_so(): void
    {
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $order = $this->order($user, ['status' => 'CONFIRMED']);

        $this->actingAs($user, 'sanctum')
            ->getJson("/api/v1/delivery/orders/{$order->id}/track")
            ->assertOk()
            ->assertJsonPath('data.tracking_no', null);
    }

    public function test_someone_elses_order_cannot_be_tracked(): void
    {
        $owner = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $stranger = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $order = $this->order($owner, ['tracking_no' => 'TRK-3', 'carrier' => 'porter']);

        $this->actingAs($stranger, 'sanctum')
            ->getJson("/api/v1/delivery/orders/{$order->id}/track")
            ->assertNotFound();
    }
}
