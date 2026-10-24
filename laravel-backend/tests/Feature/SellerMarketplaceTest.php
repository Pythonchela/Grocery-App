<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\ReturnRequest;
use App\Models\Seller;
use App\Models\SellerLedgerEntry;
use App\Models\User;
use Database\Factories\SellerFactory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Multi-seller behaviour: attribution, the commission split, and the boundary
 * between one merchant's shop and another's.
 *
 * The isolation tests matter most. In a marketplace the difference between a
 * seller dashboard and a data breach is a missing where-clause, so each of
 * those asserts that a seller reaching for someone else's data is refused
 * rather than merely that their own data comes back.
 */
class SellerMarketplaceTest extends TestCase
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

    /** A merchant plus the account that operates it. */
    private function seller(float $commission = 10, string $status = 'ACTIVE'): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create([
            'user_id' => $user->id,
            'commission_rate' => $commission,
            'status' => $status,
        ]);
    }

    private function productFor(Seller $seller, float $price = 1000, int $stock = 20): Product
    {
        $product = Product::factory()->pricedAt($price)->soldBy($seller)->create();
        ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

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

    // ── Attribution and the split ────────────────────────────────────────

    public function test_every_product_has_a_seller_and_defaults_to_the_house_account(): void
    {
        $product = Product::factory()->create();

        $this->assertNotNull($product->seller_id);
        $this->assertTrue($product->seller->is_house);
    }

    public function test_a_sold_line_records_the_seller_and_the_commission_split(): void
    {
        $seller = $this->seller(commission: 15);
        $product = $this->productFor($seller, 1000);

        $order = $this->buy($this->customer(), [$product]);
        $item = $order->items->first();

        $this->assertSame($seller->id, $item->seller_id);
        $this->assertEquals(15.0, (float) $item->commission_rate);
        $this->assertEquals(150.0, (float) $item->commission_amount);
        $this->assertEquals(850.0, (float) $item->seller_earning);
    }

    public function test_the_seller_is_credited_what_the_line_earned(): void
    {
        $seller = $this->seller(commission: 20);
        $product = $this->productFor($seller, 2000);

        $this->buy($this->customer(), [$product]);

        $this->assertEquals(1600.0, (float) $seller->fresh()->payout_balance);

        $entry = SellerLedgerEntry::where('seller_id', $seller->id)->firstOrFail();
        $this->assertSame('SALE', $entry->type);
        $this->assertEquals(2000.0, (float) $entry->gross);
        $this->assertEquals(400.0, (float) $entry->commission);
        $this->assertEquals(1600.0, (float) $entry->balance_after);
    }

    public function test_commission_is_taken_on_the_discounted_price_not_the_list_price(): void
    {
        $seller = $this->seller(commission: 10);
        $product = $this->productFor($seller, 1000);
        \App\Models\Coupon::factory()->percent(20)->create(['code' => 'TWENTY']);

        $this->actingAs($this->customer(), 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [[
                'product_id' => $product->id,
                'variant_id' => $product->variants->first()->id,
                'quantity' => 1,
            ]],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
            'coupon_code' => 'TWENTY',
        ])->assertCreated();

        $item = Order::with('items')->first()->items->first();

        // ₹800 was actually paid, so the split is on ₹800 — the discount comes
        // out of the seller's take, not out of the platform's commission.
        $this->assertEquals(80.0, (float) $item->commission_amount);
        $this->assertEquals(720.0, (float) $item->seller_earning);
        $this->assertEquals(720.0, (float) $seller->fresh()->payout_balance);
    }

    public function test_two_sellers_on_one_order_are_credited_separately(): void
    {
        $a = $this->seller(commission: 10);
        $b = $this->seller(commission: 25);

        $this->buy($this->customer(), [
            $this->productFor($a, 1000),
            $this->productFor($b, 2000),
        ]);

        $this->assertEquals(900.0, (float) $a->fresh()->payout_balance);
        $this->assertEquals(1500.0, (float) $b->fresh()->payout_balance);
    }

    public function test_a_rate_change_does_not_rewrite_past_sales(): void
    {
        $seller = $this->seller(commission: 10);
        $this->buy($this->customer(), [$this->productFor($seller, 1000)]);

        $seller->update(['commission_rate' => 50]);

        $item = Order::with('items')->first()->items->first();
        $this->assertEquals(10.0, (float) $item->commission_rate);
        $this->assertEquals(900.0, (float) $seller->fresh()->payout_balance);
    }

    // ── Unwinding ───────────────────────────────────────────────────────

    public function test_cancelling_an_order_reverses_the_sellers_credit(): void
    {
        $seller = $this->seller(commission: 10);
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($seller, 1000)]);

        $this->assertEquals(900.0, (float) $seller->fresh()->payout_balance);

        $this->actingAs($customer, 'sanctum')
            ->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'changed my mind'])
            ->assertOk();

        $this->assertEquals(0.0, (float) $seller->fresh()->payout_balance);
        $this->assertSame(1, SellerLedgerEntry::where('type', 'REFUND')->count());
    }

    public function test_a_refund_claws_back_the_sellers_share_and_the_commission(): void
    {
        $seller = $this->seller(commission: 10);
        $customer = $this->customer();
        $order = $this->buy($customer, [$this->productFor($seller, 1000)]);
        $order->update(['status' => 'DELIVERED', 'delivered_at' => now()->subDay()]);

        $this->actingAs($customer, 'sanctum')->postJson('/api/v1/returns', [
            'order_item_id' => $order->items->first()->id,
            'kind' => 'RETURN',
            'reason' => 'Did not fit',
            'refund_mode' => 'WALLET',
        ])->assertCreated();

        $return = ReturnRequest::first();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/approve");
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/picked-up");
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$return->id}/refund")->assertOk();

        // The platform doesn't keep its cut of a sale that came back.
        $this->assertEquals(0.0, (float) $seller->fresh()->payout_balance);
    }

    // ── Isolation ───────────────────────────────────────────────────────

    public function test_a_seller_cannot_edit_another_sellers_product(): void
    {
        $mine = $this->seller();
        $theirs = $this->seller();
        $victim = $this->productFor($theirs, 500);

        $this->actingAs($mine->user, 'sanctum')
            ->putJson("/api/v1/products/{$victim->id}", ['price' => 1])
            ->assertForbidden();

        $this->assertEquals(500.0, (float) $victim->fresh()->price);
    }

    public function test_a_seller_cannot_delete_another_sellers_product(): void
    {
        $mine = $this->seller();
        $theirs = $this->seller();
        $victim = $this->productFor($theirs);

        $this->actingAs($mine->user, 'sanctum')
            ->deleteJson("/api/v1/products/{$victim->id}")
            ->assertForbidden();

        $this->assertNotNull($victim->fresh());
    }

    public function test_a_seller_cannot_create_a_product_under_another_sellers_name(): void
    {
        $mine = $this->seller();
        $theirs = $this->seller();
        $category = \App\Models\Category::factory()->create();

        $this->actingAs($mine->user, 'sanctum')->postJson('/api/v1/products', [
            'title' => 'Smuggled listing',
            'category_id' => $category->id,
            'seller_id' => $theirs->id,
            'price' => 100,
            'mrp' => 200,
        ])->assertCreated();

        // The payload named another seller; it was pinned to the caller's.
        $this->assertSame($mine->id, Product::where('title', 'Smuggled listing')->first()->seller_id);
    }

    public function test_a_seller_only_sees_their_own_catalog_and_sales(): void
    {
        $mine = $this->seller();
        $theirs = $this->seller();
        $myProduct = $this->productFor($mine, 1000);
        $theirProduct = $this->productFor($theirs, 2000);

        $this->buy($this->customer(), [$myProduct, $theirProduct]);

        $products = $this->actingAs($mine->user, 'sanctum')
            ->getJson('/api/v1/seller/products')->assertOk()->json('data');
        $this->assertCount(1, $products);
        $this->assertSame($myProduct->id, $products[0]['id']);

        $lines = $this->actingAs($mine->user, 'sanctum')
            ->getJson('/api/v1/seller/order-items')->assertOk()->json('data');
        $this->assertCount(1, $lines);
        $this->assertSame($myProduct->id, $lines[0]['product_id']);
    }

    public function test_a_customer_cannot_reach_the_seller_area(): void
    {
        $this->seller();

        $this->actingAs($this->customer(), 'sanctum')
            ->getJson('/api/v1/seller/me')->assertForbidden();
        $this->actingAs($this->customer(), 'sanctum')
            ->getJson('/api/v1/seller/ledger')->assertForbidden();
    }

    public function test_a_seller_cannot_reach_the_admin_area(): void
    {
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')
            ->getJson('/api/v1/admin/orders')->assertForbidden();
        $this->actingAs($seller->user, 'sanctum')
            ->getJson('/api/v1/admin/sellers')->assertForbidden();
        $this->actingAs($seller->user, 'sanctum')
            ->getJson('/api/v1/admin/analytics')->assertForbidden();
    }

    public function test_a_seller_cannot_set_their_own_commission_or_status(): void
    {
        $seller = $this->seller(commission: 20);

        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', [
            'display_name' => 'Renamed Shop',
            'commission_rate' => 0,
            'status' => 'ACTIVE',
            'payout_balance' => 999999,
        ])->assertOk();

        $fresh = $seller->fresh();
        $this->assertSame('Renamed Shop', $fresh->display_name);
        $this->assertEquals(20.0, (float) $fresh->commission_rate);
        $this->assertEquals(0.0, (float) $fresh->payout_balance);
    }

    // ── Standing ────────────────────────────────────────────────────────

    public function test_a_suspended_sellers_products_leave_the_storefront(): void
    {
        $seller = $this->seller();
        $product = $this->productFor($seller);

        $this->getJson('/api/v1/products')->assertOk()->assertJsonPath('count', 1);

        $seller->update(['status' => 'SUSPENDED']);

        $this->getJson('/api/v1/products')->assertOk()->assertJsonPath('count', 0);
    }

    public function test_a_suspended_sellers_products_cannot_be_bought(): void
    {
        $seller = $this->seller();
        $product = $this->productFor($seller);
        $seller->update(['status' => 'SUSPENDED']);

        $this->actingAs($this->customer(), 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [[
                'product_id' => $product->id,
                'variant_id' => $product->variants->first()->id,
                'quantity' => 1,
            ]],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_a_pending_seller_cannot_list_products_yet(): void
    {
        $seller = $this->seller(status: 'PENDING');
        $category = \App\Models\Category::factory()->create();

        $this->actingAs($seller->user, 'sanctum')->postJson('/api/v1/products', [
            'title' => 'Too early',
            'category_id' => $category->id,
            'price' => 100,
            'mrp' => 200,
        ])->assertForbidden();
    }

    public function test_the_public_catalog_never_exposes_commission_or_payout(): void
    {
        $seller = $this->seller(commission: 30);
        $product = $this->productFor($seller);
        $this->buy($this->customer(), [$product]);

        $body = $this->getJson('/api/v1/products')->assertOk()->json('data.0.seller');

        $this->assertArrayHasKey('display_name', $body);
        $this->assertArrayNotHasKey('commission_rate', $body);
        $this->assertArrayNotHasKey('payout_balance', $body);
    }

    // ── Staff administration ─────────────────────────────────────────────

    public function test_an_admin_can_onboard_a_seller_and_the_user_becomes_one(): void
    {
        $operator = $this->customer();

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/sellers', [
            'display_name' => 'Jaipur Handicrafts',
            'user_id' => $operator->id,
            'commission_rate' => 12.5,
            'status' => 'ACTIVE',
        ])->assertCreated();

        $this->assertSame(User::ROLE_SELLER, $operator->fresh()->role);
        $this->assertEquals(12.5, (float) Seller::where('user_id', $operator->id)->first()->commission_rate);
    }

    public function test_a_staff_account_cannot_also_be_a_seller(): void
    {
        $staff = $this->admin();

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/sellers', [
            'display_name' => 'Conflicted Shop',
            'user_id' => $staff->id,
        ])->assertStatus(422);

        $this->assertSame(0, Seller::where('user_id', $staff->id)->count());
    }

    public function test_an_admin_payout_adjustment_moves_the_balance_and_is_ledgered(): void
    {
        $seller = $this->seller();

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/v1/admin/sellers/{$seller->id}/payout-adjustment", [
                'amount' => -250,
                'note' => 'Chargeback recovered',
            ])->assertOk();

        $this->assertEquals(-250.0, (float) $seller->fresh()->payout_balance);

        $entry = SellerLedgerEntry::where('type', 'ADJUSTMENT')->firstOrFail();
        $this->assertEquals(-250.0, (float) $entry->net);
        $this->assertSame('Chargeback recovered', $entry->note);
    }

    public function test_house_products_carry_no_commission(): void
    {
        $house = SellerFactory::house();
        $product = $this->productFor($house, 1000);

        $this->buy($this->customer(), [$product]);

        $item = Order::with('items')->first()->items->first();
        $this->assertEquals(0.0, (float) $item->commission_amount);
        $this->assertEquals(1000.0, (float) $item->seller_earning);
    }
}
