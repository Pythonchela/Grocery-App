<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * What can be delivered how, and how long it takes: food goes by rider and is
 * never a three-day parcel; a parcel is never a rider job; preparation time is
 * part of the promise.
 */
class DeliveryProfileTest extends TestCase
{
    use RefreshDatabase;

    // Same sorting district as the warehouse (560103), so riders are possible.
    private const NEARBY = '560038';

    private function product(?string $profile = null, ?int $prep = null, array $category = []): Product
    {
        $cat = Category::factory()->create($category);
        $p = Product::factory()->pricedAt(300)->create(
            ['category_id' => $cat->id, 'delivery_profile' => $profile, 'prep_minutes' => $prep],
        );
        ProductVariant::factory()->withStock(20)->create(['product_id' => $p->id]);

        return $p->fresh(['variants', 'category']);
    }

    private function quote(array $products, string $pincode = self::NEARBY)
    {
        return $this->postJson('/api/v1/delivery/quote', [
            'pincode' => $pincode,
            'order_value' => 300,
            'items' => array_map(fn (Product $p) => ['product_id' => $p->id, 'quantity' => 1], $products),
        ]);
    }

    private function levels($response): array
    {
        return collect($response->json('data.options'))->pluck('service_level')->all();
    }

    private function eta($response, string $level): int
    {
        return (int) collect($response->json('data.options'))->firstWhere('service_level', $level)['eta_minutes'];
    }

    public function test_food_is_offered_to_riders_and_never_as_a_multi_day_parcel(): void
    {
        $dish = $this->product(category: ['delivery_profile' => 'instant']);

        $levels = $this->levels($this->quote([$dish])->assertOk());

        $this->assertContains('INSTANT', $levels);
        $this->assertNotContains('STANDARD', $levels);
        $this->assertNotContains('EXPRESS', $levels);
    }

    public function test_a_parcel_is_never_offered_to_a_rider(): void
    {
        $shirt = $this->product(category: ['delivery_profile' => 'parcel']);

        $levels = $this->levels($this->quote([$shirt])->assertOk());

        $this->assertNotContains('INSTANT', $levels);
        $this->assertNotContains('SAME_DAY', $levels);
        $this->assertContains('STANDARD', $levels);
    }

    public function test_with_no_profile_it_behaves_as_before(): void
    {
        $levels = $this->levels($this->quote([$this->product()])->assertOk());

        $this->assertContains('INSTANT', $levels);
        $this->assertContains('STANDARD', $levels);
    }

    public function test_a_product_can_override_its_categorys_profile(): void
    {
        $madeToOrder = $this->product(profile: 'parcel', category: ['delivery_profile' => 'instant']);

        $this->assertNotContains('INSTANT', $this->levels($this->quote([$madeToOrder])->assertOk()));
    }

    public function test_preparation_time_is_part_of_the_promise(): void
    {
        $plain = $this->product(category: ['delivery_profile' => 'instant']);
        $cooked = $this->product(category: ['delivery_profile' => 'instant', 'prep_minutes' => 30]);

        $this->assertSame(
            $this->eta($this->quote([$plain]), 'INSTANT') + 30,
            $this->eta($this->quote([$cooked]), 'INSTANT'),
        );
    }

    public function test_the_longest_preparation_in_the_cart_counts(): void
    {
        $quick = $this->product(category: ['delivery_profile' => 'instant', 'prep_minutes' => 10]);
        $slow = $this->product(category: ['delivery_profile' => 'instant', 'prep_minutes' => 45]);
        $alone = $this->eta($this->quote([$quick]), 'INSTANT');

        // The rider waits for the slowest dish: 45, not 10 + 45.
        $this->assertSame($alone + 35, $this->eta($this->quote([$quick, $slow]), 'INSTANT'));
    }

    public function test_food_and_a_courier_parcel_cannot_share_a_basket(): void
    {
        $dish = $this->product(category: ['delivery_profile' => 'instant']);
        $shirt = $this->product(category: ['delivery_profile' => 'parcel']);

        $response = $this->quote([$dish, $shirt])
            ->assertOk()
            ->assertJsonPath('data.serviceable', false)
            ->assertJsonPath('data.options', []);

        $this->assertStringContainsString('order them separately', $response->json('data.message'));
    }

    public function test_checkout_refuses_a_mixed_basket_and_creates_nothing(): void
    {
        $dish = $this->product(category: ['delivery_profile' => 'instant']);
        $shirt = $this->product(category: ['delivery_profile' => 'parcel']);
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => collect([$dish, $shirt])->map(fn ($p) => ['product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => 1])->all(),
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'c', 'state' => 's', 'pincode' => self::NEARBY],
            'payment_method' => 'COD',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_an_order_for_food_defaults_to_the_fastest_speed_not_standard(): void
    {
        $dish = $this->product(category: ['delivery_profile' => 'instant', 'prep_minutes' => 20]);
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        // No speed chosen: the default is STANDARD, which food does not have.
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $dish->id, 'variant_id' => $dish->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'c', 'state' => 's', 'pincode' => self::NEARBY],
            'payment_method' => 'COD',
        ])->assertCreated();

        $order = Order::first();
        $this->assertSame('INSTANT', $order->service_level);
        $this->assertLessThan(3 * 60, $order->created_at->diffInMinutes($order->promised_by));
    }

    public function test_a_parcel_order_is_promised_in_days_not_hours(): void
    {
        $shirt = $this->product(category: ['delivery_profile' => 'parcel']);
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $shirt->id, 'variant_id' => $shirt->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'c', 'state' => 's', 'pincode' => self::NEARBY],
            'payment_method' => 'COD',
        ])->assertCreated();

        $order = Order::first();
        $this->assertGreaterThan(24 * 60, $order->created_at->diffInMinutes($order->promised_by));
        $this->assertSame('status_updates', $order->tracking_mode);
    }

    public function test_the_app_is_told_to_preselect_the_fastest_for_food_and_the_cheapest_for_parcels(): void
    {
        $dish = $this->product(category: ['delivery_profile' => 'instant']);
        $shirt = $this->product(category: ['delivery_profile' => 'parcel']);

        $this->assertSame('INSTANT', $this->quote([$dish])->json('data.recommended_service_level'));

        $parcel = $this->quote([$shirt]);
        $cheapest = collect($parcel->json('data.options'))->sortBy('price_paise')->first()['service_level'];
        $this->assertSame($cheapest, $parcel->json('data.recommended_service_level'));
        $this->assertSame('STANDARD', $cheapest);
    }

    public function test_the_product_says_how_it_is_delivered(): void
    {
        $dish = $this->product(category: ['delivery_profile' => 'instant', 'prep_minutes' => 25]);

        $this->getJson("/api/v1/products/{$dish->id}")
            ->assertOk()
            ->assertJsonPath('data.delivery_info.profile', 'instant')
            ->assertJsonPath('data.delivery_info.prep_minutes', 25);
    }

    public function test_an_admin_sets_a_categorys_profile(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
        $category = Category::factory()->create();

        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/v1/categories/{$category->id}", ['delivery_profile' => 'instant', 'prep_minutes' => 20])
            ->assertOk()
            ->assertJsonPath('data.delivery_profile', 'instant');

        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/v1/categories/{$category->id}", ['delivery_profile' => 'teleport'])
            ->assertStatus(422);
    }
}
