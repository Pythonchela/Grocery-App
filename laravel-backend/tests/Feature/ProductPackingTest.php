<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\Seller;
use App\Models\User;
use App\Services\Delivery\DeliveryAllocator;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * What a product weighs and how big it is packed: what couriers price on.
 */
class ProductPackingTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'title' => 'Brass Lamp',
            'category_id' => Category::factory()->create()->id,
            'mrp' => 2999, 'price' => 2499, 'status' => 'ACTIVE',
            'images' => ['https://example.com/a.jpg'],
            'variants' => [['color' => 'Gold', 'size' => 'M', 'sku' => 'LAMP-'.strtoupper(\Illuminate\Support\Str::random(6)), 'stock' => 5]],
        ], $overrides);
    }

    public function test_weight_and_size_can_be_set_and_come_back(): void
    {
        $id = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/products', $this->payload([
            'weight_grams' => 1200, 'length_cm' => 30, 'width_cm' => 20, 'height_cm' => 15, 'requires_vehicle' => false,
        ]))->assertCreated()->json('data.id');

        $product = Product::findOrFail($id);
        $this->assertSame(1200, $product->weight_grams);
        $this->assertSame([30, 20, 15], [$product->length_cm, $product->width_cm, $product->height_cm]);

        $this->getJson("/api/v1/products/{$id}")->assertJsonPath('data.weight_grams', 1200);
    }

    public function test_a_seller_can_set_them_on_their_own_product(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);
        Seller::factory()->create(['user_id' => $user->id]);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/products', $this->payload(['weight_grams' => 350]))
            ->assertCreated()->assertJsonPath('data.weight_grams', 350);
    }

    public function test_they_can_be_changed_and_cleared(): void
    {
        $admin = $this->admin();
        $id = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $this->payload(['weight_grams' => 500]))->json('data.id');

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/products/{$id}", ['weight_grams' => 750, 'length_cm' => 10])->assertOk();
        $this->assertSame(750, Product::findOrFail($id)->weight_grams);

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/products/{$id}", ['weight_grams' => null])->assertOk();
        $this->assertNull(Product::findOrFail($id)->weight_grams, 'cleared means the default is used again');
    }

    public function test_nonsense_is_refused(): void
    {
        $admin = $this->admin();
        $post = fn (array $extra) => $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $this->payload($extra));

        $post(['weight_grams' => 0])->assertStatus(422)->assertJsonValidationErrors('weight_grams');
        $post(['weight_grams' => -5])->assertStatus(422)->assertJsonValidationErrors('weight_grams');
        $post(['weight_grams' => 'heavy'])->assertStatus(422)->assertJsonValidationErrors('weight_grams');
        $post(['weight_grams' => 999999])->assertStatus(422)->assertJsonValidationErrors('weight_grams');
        $post(['length_cm' => 0])->assertStatus(422)->assertJsonValidationErrors('length_cm');
        $post(['height_cm' => 5000])->assertStatus(422)->assertJsonValidationErrors('height_cm');
    }

    public function test_the_courier_quote_uses_the_weight_that_was_entered(): void
    {
        $light = Product::factory()->create(['weight_grams' => 200]);
        $heavy = Product::factory()->create(['weight_grams' => 8000]);
        \App\Models\ProductVariant::factory()->withStock(5)->create(['product_id' => $light->id]);
        \App\Models\ProductVariant::factory()->withStock(5)->create(['product_id' => $heavy->id]);

        $weightOf = fn (Product $p) => app(DeliveryAllocator::class)
            ->planForCart([['product_id' => $p->id, 'quantity' => 1]], '560038', false, 50000)
            ->first()?->weightGrams;

        $this->assertSame(200, $weightOf($light));
        $this->assertSame(8000, $weightOf($heavy));
    }
}
