<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\User;
use App\Services\Delivery\PickupLocation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Delivery starts where the seller is, not at one warehouse for everyone.
 */
class SellerPickupDeliveryTest extends TestCase
{
    use RefreshDatabase;

    // The platform's own pickup is 560103 (Bengaluru). A customer at 560038 is the same sorting district.
    private const CUSTOMER_PIN = '560038';

    private function seller(array $pickup = []): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(array_merge(['user_id' => $user->id], $pickup));
    }

    private function bengaluruSeller(): Seller
    {
        return $this->seller([
            'pickup_line1' => '12 Koramangala 4th Block', 'pickup_city' => 'Bengaluru', 'pickup_state' => 'Karnataka',
            'pickup_pincode' => '560034', 'pickup_phone' => '9811111111',
        ]);
    }

    private function mumbaiSeller(): Seller
    {
        return $this->seller([
            'pickup_line1' => '5 Linking Road', 'pickup_city' => 'Mumbai', 'pickup_state' => 'Maharashtra',
            'pickup_pincode' => '400050', 'pickup_phone' => '9822222222',
        ]);
    }

    private function product(Seller $seller, ?string $profile = null, float $price = 300): Product
    {
        $category = Category::factory()->create(['delivery_profile' => $profile]);
        $p = Product::factory()->pricedAt($price)->soldBy($seller)->create(['category_id' => $category->id]);
        ProductVariant::factory()->withStock(20)->create(['product_id' => $p->id]);

        return $p->fresh(['variants', 'category', 'seller']);
    }

    private function quote(array $products): array
    {
        return $this->postJson('/api/v1/delivery/quote', [
            'pincode' => self::CUSTOMER_PIN,
            'order_value' => 300,
            'items' => array_map(fn (Product $p) => ['product_id' => $p->id, 'quantity' => 1], $products),
        ])->assertOk()->json('data');
    }

    private function levels(array $data): array
    {
        return array_column($data['options'], 'service_level');
    }

    // ── Who may set a pickup address, and what is checked ─────────────────

    public function test_a_seller_sets_their_own_pickup_address(): void
    {
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', [
            'pickup_line1' => '12 Koramangala', 'pickup_city' => 'Bengaluru', 'pickup_state' => 'Karnataka',
            'pickup_pincode' => '560034', 'pickup_phone' => '98 1111 1111', 'pickup_lat' => 12.9352, 'pickup_lng' => 77.6245,
        ])->assertOk();

        $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/me')
            ->assertOk()
            ->assertJsonPath('data.pickup_pincode', '560034')
            ->assertJsonPath('data.has_pickup_address', true);
    }

    public function test_a_bad_pincode_or_coordinate_is_refused(): void
    {
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', ['pickup_pincode' => '12345'])
            ->assertStatus(422)->assertJsonValidationErrors('pickup_pincode');
        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', ['pickup_lat' => 400])
            ->assertStatus(422)->assertJsonValidationErrors('pickup_lat');
    }

    public function test_a_seller_cannot_change_someone_elses_pickup(): void
    {
        $mine = $this->seller();
        $theirs = $this->bengaluruSeller();

        // The seller route only ever edits the signed-in seller's own row.
        $this->actingAs($mine->user, 'sanctum')->putJson('/api/v1/seller/me', ['pickup_pincode' => '110001', 'pickup_line1' => 'x']);

        $this->assertSame('560034', $theirs->fresh()->pickup_pincode);
    }

    public function test_an_admin_can_set_any_sellers_pickup(): void
    {
        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
        $seller = $this->seller();

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/admin/sellers/{$seller->id}", [
            'pickup_line1' => '5 Linking Road', 'pickup_pincode' => '400050', 'pickup_city' => 'Mumbai',
        ])->assertOk()->assertJsonPath('data.pickup_pincode', '400050');
    }

    // ── Where a parcel starts ─────────────────────────────────────────────

    public function test_a_seller_without_an_address_ships_from_the_platforms(): void
    {
        $location = PickupLocation::forSeller($this->seller());

        $this->assertSame(config('delivery.pickup_address.pincode'), $location['pincode']);
        $this->assertNotEmpty($location['line1']);
    }

    public function test_a_seller_with_an_address_ships_from_it_whole(): void
    {
        $seller = $this->mumbaiSeller();
        $location = PickupLocation::forSeller($seller);

        $this->assertSame('400050', $location['pincode']);
        $this->assertSame('5 Linking Road', $location['line1']);
        $this->assertSame('Mumbai', $location['city']);
        // Never half one place, half the other.
        $this->assertNotSame(config('delivery.pickup_address.line1'), $location['line1']);
    }

    public function test_a_half_filled_address_is_not_used(): void
    {
        $seller = $this->seller(['pickup_pincode' => '400050']);   // no street

        $this->assertFalse($seller->hasPickupAddress());
        $this->assertSame(config('delivery.pickup_address.pincode'), PickupLocation::forSeller($seller)['pincode']);
    }

    // ── What the shopper is offered ───────────────────────────────────────

    public function test_a_local_seller_can_use_a_rider_a_far_one_cannot(): void
    {
        $near = $this->product($this->bengaluruSeller());
        $far = $this->product($this->mumbaiSeller());

        $this->assertContains('INSTANT', $this->levels($this->quote([$near])));
        $this->assertNotContains('INSTANT', $this->levels($this->quote([$far])));
        $this->assertContains('STANDARD', $this->levels($this->quote([$far])));
    }

    public function test_a_restaurant_in_another_city_cannot_be_delivered_to_you(): void
    {
        $dish = $this->product($this->mumbaiSeller(), profile: 'instant');

        $data = $this->quote([$dish]);

        $this->assertFalse($data['serviceable']);
        $this->assertSame([], $data['options']);
    }

    public function test_a_basket_from_two_sellers_is_two_parcels_priced_together(): void
    {
        $a = $this->product($this->bengaluruSeller());
        $b = $this->product($this->mumbaiSeller());

        $alone = fn (Product $p) => collect($this->quote([$p])['options'])->firstWhere('service_level', 'STANDARD');
        $together = $this->quote([$a, $b]);
        $standard = collect($together['options'])->firstWhere('service_level', 'STANDARD');

        $this->assertCount(2, $together['parcels']);
        $this->assertEqualsCanonicalizing(['560034', '400050'], array_column($together['parcels'], 'pickup_pincode'));
        // Prices add up; the order arrives when the slower parcel does.
        $this->assertSame($alone($a)['price_paise'] + $alone($b)['price_paise'], $standard['price_paise']);
        $this->assertSame(max($alone($a)['eta_minutes'], $alone($b)['eta_minutes']), $standard['eta_minutes']);
        // A rider is only possible if both parcels can ride.
        $this->assertNotContains('INSTANT', $this->levels($together));
    }

    public function test_two_local_sellers_can_both_ride_and_the_fees_add_up(): void
    {
        $a = $this->product($this->bengaluruSeller());
        $b = $this->product($this->bengaluruSeller());   // another shop, another address object

        $a->seller->update(['pickup_line1' => '1 First Street']);
        $b->seller->update(['pickup_line1' => '2 Second Street']);

        $one = collect($this->quote([$a])['options'])->firstWhere('service_level', 'INSTANT');
        $both = collect($this->quote([$a->fresh(), $b->fresh()])['options'])->firstWhere('service_level', 'INSTANT');

        $this->assertNotNull($both);
        $this->assertSame($one['price_paise'] * 2, $both['price_paise']);
    }

    public function test_items_from_one_pickup_point_stay_one_parcel(): void
    {
        $seller = $this->bengaluruSeller();
        $a = $this->product($seller);
        $b = $this->product($seller);

        $this->assertCount(1, $this->quote([$a, $b])['parcels']);
    }

    public function test_the_parcels_say_who_they_are_from(): void
    {
        $seller = $this->mumbaiSeller();

        $parcel = $this->quote([$this->product($seller)])['parcels'][0];

        $this->assertSame($seller->display_name, $parcel['seller_name']);
        $this->assertSame('Mumbai', $parcel['pickup_city']);
    }

    // ── Orders and booking ────────────────────────────────────────────────

    public function test_checking_out_from_two_sellers_charges_both_parcels(): void
    {
        $a = $this->product($this->bengaluruSeller());
        $b = $this->product($this->mumbaiSeller());
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        // Quoted the way the app does for a cash-on-delivery order.
        $standard = collect($this->postJson('/api/v1/delivery/quote', [
            'pincode' => self::CUSTOMER_PIN, 'order_value' => 600, 'cod' => true,
            'items' => [['product_id' => $a->id, 'quantity' => 1], ['product_id' => $b->id, 'quantity' => 1]],
        ])->json('data.options'))->firstWhere('service_level', 'STANDARD');

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => collect([$a, $b])->map(fn ($p) => ['product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => 1])->all(),
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'c', 'state' => 's', 'pincode' => self::CUSTOMER_PIN],
            'payment_method' => 'COD',
            'service_level' => 'STANDARD',
        ])->assertCreated();

        $order = Order::first();
        $this->assertSame(2, OrderItem::count());
        // What the shopper was quoted for two parcels is what the order charges.
        $this->assertEquals($standard['price_paise'], $order->delivery_fee_paise);
    }

    public function test_an_order_from_one_seller_is_booked_from_that_sellers_address(): void
    {
        $seller = $this->mumbaiSeller();
        $p = $this->product($seller);
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'c', 'state' => 's', 'pincode' => self::CUSTOMER_PIN],
            'payment_method' => 'COD',
        ])->assertCreated();

        $this->assertSame('400050', PickupLocation::forOrder(Order::first())['pincode']);
    }

    public function test_one_booking_cannot_cover_two_sellers_parcels(): void
    {
        $a = $this->product($this->bengaluruSeller());
        $b = $this->product($this->mumbaiSeller());
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => collect([$a, $b])->map(fn ($p) => ['product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => 1])->all(),
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'c', 'state' => 's', 'pincode' => self::CUSTOMER_PIN],
            'payment_method' => 'COD',
        ])->assertCreated();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/admin/orders/'.Order::first()->id.'/shipment')
            ->assertStatus(422);
    }
}
