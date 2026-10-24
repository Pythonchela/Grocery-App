<?php

namespace Tests\Feature;

use App\Models\Setting;
use App\Models\Order;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class StorefrontSettingsTest extends TestCase
{
    use RefreshDatabase;

    public function test_the_public_free_delivery_threshold_is_the_one_pricing_applies(): void
    {
        config(['delivery.free_above' => 1999]);
        $this->getJson('/api/v1/settings')->assertOk()->assertJsonPath('data.free_shipping_threshold', 1999);

        // Changed under Integrations > Shipping, which pricing reads.
        Setting::put('delivery.free_above', 999);

        $this->getJson('/api/v1/settings')->assertOk()->assertJsonPath('data.free_shipping_threshold', 999);
    }

    public function test_business_details_are_saved_and_receipt_does_not_invent_tax(): void
    {
        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
        $this->actingAs($admin, 'sanctum')->putJson('/api/v1/admin/settings', [
            'store_legal_name' => 'Example Retail Private Limited',
            'store_address' => 'Example Road, Delhi',
            'store_gstin' => '07ABCDE1234F1Z5',
        ])->assertOk();

        $this->getJson('/api/v1/settings')->assertJsonPath('data.store_legal_name', 'Example Retail Private Limited');
        $order = Order::create([
            'order_number' => 'BX-RECEIPT-1', 'user_id' => $admin->id,
            'status' => 'CONFIRMED', 'payment_status' => 'PAID', 'payment_method' => 'COD',
            'subtotal' => 100, 'discount' => 0, 'shipping_charge' => 20, 'total_amount' => 120,
            'shipping_address' => ['name' => 'Buyer', 'line1' => 'Street', 'city' => 'Delhi', 'state' => 'Delhi', 'pincode' => '110001'],
        ]);
        $receipt = $this->getJson("/api/v1/orders/{$order->id}/invoice")
            ->assertOk()->assertJsonPath('data.document_type', 'ORDER_RECEIPT')
            ->assertJsonPath('data.seller.gstin', '07ABCDE1234F1Z5')
            ->assertJsonPath('data.totals.grand_total', 120)
            ->json('data');
        $this->assertArrayNotHasKey('gst', $receipt['totals']);
        $this->assertArrayNotHasKey('gst_rate', $receipt['totals']);
    }
}
