<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use App\Services\Options\VariantSetup;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** A category says what its products come in (sizes, colours, storage...) so adding a product is picking from a list. */
class CategoryVariantSetupTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    public function test_a_category_keeps_its_labels_sizes_and_colours(): void
    {
        $response = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/categories', [
            'name' => 'Footwear',
            'variant_setup' => [
                'size_label' => 'UK size',
                'sizes' => ['6', '7', ' 8 ', '7', ''],
                'color_label' => 'Colour',
                'colors' => [['name' => 'Black', 'hex' => '#111111'], ['name' => 'black'], ['name' => 'Tan']],
            ],
        ])->assertCreated();

        $setup = $response->json('data.variant_setup');
        $this->assertSame('UK size', $setup['size_label']);
        $this->assertSame(['6', '7', '8'], $setup['sizes']);
        $this->assertSame([['name' => 'Black', 'hex' => '#111111'], ['name' => 'Tan', 'hex' => null]], $setup['colors']);
    }

    public function test_a_product_sends_its_categorys_setup_so_the_shop_can_use_the_labels(): void
    {
        $category = Category::factory()->create([
            'name' => 'Phones',
            'variant_setup' => ['size_label' => 'Storage', 'sizes' => ['128 GB', '256 GB'], 'color_label' => 'Colour', 'colors' => []],
        ]);
        $product = Product::factory()->create(['category_id' => $category->id, 'status' => 'ACTIVE']);

        $this->getJson('/api/v1/products/'.$product->id)
            ->assertOk()
            ->assertJsonPath('data.category.variant_setup.size_label', 'Storage')
            ->assertJsonPath('data.category.variant_setup.sizes.1', '256 GB');
    }

    public function test_a_category_with_nothing_set_stays_empty_and_too_long_a_label_is_refused(): void
    {
        $admin = $this->admin();
        $plain = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/categories', ['name' => 'Misc', 'variant_setup' => ['sizes' => [' ', ''], 'colors' => []]])->assertCreated();
        $this->assertNull($plain->json('data.variant_setup'));

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/categories', ['name' => 'Long', 'variant_setup' => ['size_label' => str_repeat('a', 40)]])
            ->assertStatus(422)->assertJsonValidationErrors('variant_setup.size_label');
    }

    public function test_normalising_returns_null_for_nothing(): void
    {
        $this->assertNull(VariantSetup::normalize(null));
        $this->assertNull(VariantSetup::normalize([]));
        $this->assertSame('Size', VariantSetup::normalize(['sizes' => ['M']])['size_label']);
    }
}
