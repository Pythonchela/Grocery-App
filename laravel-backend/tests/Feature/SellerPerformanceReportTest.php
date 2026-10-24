<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Staff can see how a shop has been doing before deciding to keep, coach or suspend it. */
class SellerPerformanceReportTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
        'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
    ];

    private function staff(string $role = 'ADMIN'): User
    {
        return User::factory()->create(['role' => $role, 'status' => 'ACTIVE']);
    }

    private function seller(array $attributes = []): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(['user_id' => $user->id, 'status' => 'ACTIVE'] + $attributes);
    }

    private function productFor(Seller $seller, float $price = 500, int $stock = 10): Product
    {
        $product = Product::factory()->pricedAt($price)->soldBy($seller)->create();
        ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function buy(Product $product): Order
    {
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $number = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $product->id, 'variant_id' => $product->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ])->assertCreated()->json('data.order_number');

        return Order::with('items')->where('order_number', $number)->firstOrFail();
    }

    private function report(User $viewer, Seller $seller, string $query = '')
    {
        return $this->actingAs($viewer, 'sanctum')->getJson("/api/v1/admin/sellers/{$seller->id}/performance{$query}");
    }

    public function test_a_new_shop_has_an_empty_report_not_an_error(): void
    {
        $seller = $this->seller();

        $this->report($this->staff(), $seller)->assertOk()
            ->assertJsonPath('data.orders', 0)
            ->assertJsonPath('data.sales', 0)
            ->assertJsonPath('data.acceptance_rate', null)
            ->assertJsonPath('data.return_rate', null)
            ->assertJsonPath('data.products_live', 0);
    }

    public function test_it_counts_orders_sales_and_products_for_that_shop_only(): void
    {
        $seller = $this->seller();
        $other = $this->seller();
        $this->buy($this->productFor($seller, 500));
        $this->buy($this->productFor($seller, 700));
        $this->buy($this->productFor($other, 999));

        $data = $this->report($this->staff(), $seller)->assertOk()->json('data');

        $this->assertSame(2, $data['orders']);
        $this->assertSame(2, $data['items']);
        $this->assertEquals(1200, $data['sales']);
        $this->assertSame(2, $data['products_live']);
        $this->assertSame(30, $data['days']);
        $this->assertEquals(100.0, $data['acceptance_rate']);
    }

    public function test_cancelled_orders_do_not_count_as_sales(): void
    {
        $seller = $this->seller();
        $order = $this->buy($this->productFor($seller, 500));
        $order->forceFill(['status' => 'CANCELLED'])->save();

        $data = $this->report($this->staff(), $seller)->json('data');

        $this->assertSame(0, $data['orders']);
        $this->assertEquals(0, $data['sales']);
    }

    public function test_declined_and_missed_orders_lower_the_acceptance_rate(): void
    {
        $seller = $this->seller();
        $first = $this->buy($this->productFor($seller));
        $second = $this->buy($this->productFor($seller));

        OrderItem::where('order_id', $second->id)->update([
            'seller_response' => 'REJECTED',
            'rejected_by' => 'SELLER',
            'rejection_reason' => 'CANNOT_PREPARE',
            'rejected_at' => now(),
        ]);

        $data = $this->report($this->staff(), $seller)->json('data');

        $this->assertEquals(50.0, $data['acceptance_rate']);
        $this->assertSame(1, $data['declined']);
        $this->assertSame(0, $data['missed']);
        $this->assertNotNull($first);
    }

    public function test_low_stock_and_drafts_are_flagged(): void
    {
        $seller = $this->seller();
        $this->productFor($seller, 500, 2);
        Product::factory()->pricedAt(0)->soldBy($seller)->create(['status' => 'DRAFT']);

        $data = $this->report($this->staff(), $seller)->json('data');

        $this->assertSame(1, $data['products_low_stock']);
        $this->assertSame(1, $data['products_draft']);
    }

    public function test_only_the_known_windows_are_accepted(): void
    {
        $seller = $this->seller();

        $this->assertSame(7, $this->report($this->staff(), $seller, '?days=7')->json('data.days'));
        $this->assertSame(90, $this->report($this->staff(), $seller, '?days=90')->json('data.days'));
        $this->assertSame(30, $this->report($this->staff(), $seller, '?days=9999')->json('data.days'));
    }

    public function test_unknown_shops_are_a_clean_404(): void
    {
        $this->actingAs($this->staff(), 'sanctum')
            ->getJson('/api/v1/admin/sellers/00000000-0000-0000-0000-000000000000/performance')
            ->assertNotFound();
    }

    public function test_only_full_admins_can_see_it(): void
    {
        $seller = $this->seller();

        $this->getJson("/api/v1/admin/sellers/{$seller->id}/performance")->assertUnauthorized();
        $this->report($this->seller()->user, $seller)->assertForbidden();
        $this->report(User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']), $seller)->assertForbidden();
        $this->report($this->staff('SUB_ADMIN'), $seller)->assertForbidden();
    }
}
