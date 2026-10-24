<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\User;
use Database\Factories\SellerFactory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class InventoryUpdateTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    private function variantOf(Product $product, int $stock = 0): ProductVariant
    {
        return ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);
    }

    public function test_an_admin_can_set_stock_for_many_variants_at_once(): void
    {
        $product = Product::factory()->create();
        $a = $this->variantOf($product, 0);
        $b = $this->variantOf($product, 3);

        $this->actingAs($this->admin(), 'sanctum')->putJson('/api/v1/inventory', [
            'items' => [
                ['variant_id' => $a->id, 'stock' => 25],
                ['variant_id' => $b->id, 'stock' => 0],
            ],
        ])->assertOk()->assertJsonCount(2, 'data');

        $this->assertSame(25, (int) $a->fresh()->stock);
        $this->assertSame(0, (int) $b->fresh()->stock);
    }

    public function test_only_the_stock_changes(): void
    {
        $product = Product::factory()->pricedAt(499)->create();
        $variant = $this->variantOf($product, 1);
        $sku = $variant->sku;

        $this->actingAs($this->admin(), 'sanctum')->putJson('/api/v1/inventory', [
            'items' => [['variant_id' => $variant->id, 'stock' => 9]],
        ])->assertOk();

        $this->assertEquals(499.0, (float) $product->fresh()->price);
        $this->assertSame($sku, $variant->fresh()->sku);
    }

    public function test_a_seller_can_restock_their_own_products(): void
    {
        $seller = SellerFactory::new()->create();
        $owner = User::factory()->create(['role' => 'SELLER', 'status' => 'ACTIVE']);
        $seller->update(['user_id' => $owner->id]);
        $product = Product::factory()->create(['seller_id' => $seller->id]);
        $variant = $this->variantOf($product, 0);

        $this->actingAs($owner->fresh(), 'sanctum')->putJson('/api/v1/inventory', [
            'items' => [['variant_id' => $variant->id, 'stock' => 12]],
        ])->assertOk();

        $this->assertSame(12, (int) $variant->fresh()->stock);
    }

    public function test_a_seller_cannot_touch_anyone_elses_stock_and_nothing_is_partially_applied(): void
    {
        $seller = SellerFactory::new()->create();
        $owner = User::factory()->create(['role' => 'SELLER', 'status' => 'ACTIVE']);
        $seller->update(['user_id' => $owner->id]);

        $mine = $this->variantOf(Product::factory()->create(['seller_id' => $seller->id]), 1);
        $theirs = $this->variantOf(Product::factory()->create(), 1);

        $this->actingAs($owner->fresh(), 'sanctum')->putJson('/api/v1/inventory', [
            'items' => [
                ['variant_id' => $mine->id, 'stock' => 99],
                ['variant_id' => $theirs->id, 'stock' => 99],
            ],
        ])->assertForbidden();

        $this->assertSame(1, (int) $mine->fresh()->stock);
        $this->assertSame(1, (int) $theirs->fresh()->stock);
    }

    public function test_customers_and_visitors_are_refused(): void
    {
        $variant = $this->variantOf(Product::factory()->create(), 1);
        $payload = ['items' => [['variant_id' => $variant->id, 'stock' => 5]]];

        $this->putJson('/api/v1/inventory', $payload)->assertUnauthorized();
        $this->actingAs(User::factory()->create(['role' => 'CUSTOMER']), 'sanctum')
            ->putJson('/api/v1/inventory', $payload)->assertForbidden();
    }

    public function test_negative_or_repeated_entries_are_rejected(): void
    {
        $variant = $this->variantOf(Product::factory()->create(), 1);
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->putJson('/api/v1/inventory', [
            'items' => [['variant_id' => $variant->id, 'stock' => -1]],
        ])->assertStatus(422);

        $this->actingAs($admin, 'sanctum')->putJson('/api/v1/inventory', [
            'items' => [
                ['variant_id' => $variant->id, 'stock' => 1],
                ['variant_id' => $variant->id, 'stock' => 2],
            ],
        ])->assertStatus(422);
    }
}
