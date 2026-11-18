<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Database\Seeders\StarterCatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The sample menu and pantry that fill a fresh food and grocery store: safe to run twice, never destructive. */
class StarterCatalogSeederTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_adds_restaurant_produce_and_grocery_categories_with_their_options(): void
    {
        $this->seed(StarterCatalogSeeder::class);

        $restaurant = Category::where('slug', 'restaurant')->first();
        $this->assertSame(['portion', 'add_ons', 'leave_out', 'spice_level'], array_column($restaurant->option_groups, 'key'));
        $this->assertSame('Ingredients', $restaurant->spec_template[0]['labels'][0]);

        $this->assertSame('stepper', Category::where('slug', 'fresh-produce')->first()->option_groups[0]['type']);
        $this->assertNull(Category::where('slug', 'groceries')->first()->option_groups);
    }

    public function test_there_is_nothing_but_food(): void
    {
        $this->seed(StarterCatalogSeeder::class);

        $this->assertSame(['fresh-produce', 'groceries', 'restaurant'], Category::orderBy('slug')->pluck('slug')->all());
        $this->assertSame(['instant'], Category::pluck('delivery_profile')->unique()->values()->all());
    }

    public function test_every_sample_is_labelled_active_and_in_stock(): void
    {
        $this->seed(StarterCatalogSeeder::class);

        $products = Product::with('variants')->get();
        $this->assertGreaterThanOrEqual(15, $products->count());
        foreach ($products as $product) {
            $this->assertStringStartsWith('Sample: ', $product->title);
            $this->assertSame('ACTIVE', $product->status);
            $this->assertTrue($product->cod_available);
            $this->assertGreaterThan(0, $product->variants->sum('stock'));
        }
    }

    public function test_food_carries_the_veg_mark_and_the_chicken_biryani_is_non_veg(): void
    {
        $this->seed(StarterCatalogSeeder::class);

        $this->assertSame('non_veg', Product::where('slug', 'sample-chicken-biryani')->value('diet'));
        $this->assertSame('veg', Product::where('slug', 'sample-paneer-butter-masala')->value('diet'));
        $this->assertSame(0, Product::whereNull('diet')->count());
    }

    public function test_a_dish_can_actually_be_priced_and_bought(): void
    {
        $this->seed(StarterCatalogSeeder::class);
        $pizza = Product::where('slug', 'sample-margherita-pizza')->with('variants', 'category')->first();
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $line = ['product_id' => $pizza->id, 'variant_id' => $pizza->variants->first()->id, 'quantity' => 1];

        // Half plate is the listed price, a full plate adds to it.
        $this->postJson('/api/v1/cart/price', ['items' => [$line + ['options' => ['portion' => ['half_plate']]]]])
            ->assertJsonPath('data.items.0.unit_price', 150);
        $this->postJson('/api/v1/cart/price', ['items' => [$line + ['options' => ['portion' => ['full_plate'], 'add_ons' => ['extra_cheese']]]]])
            ->assertJsonPath('data.items.0.unit_price', 260);

        // Choosing nothing for a required option is refused.
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [$line], 'payment_method' => 'COD',
            'shipping_address' => ['name' => 'A', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'c', 'state' => 's', 'pincode' => '560038'],
        ])->assertStatus(422);
    }

    public function test_produce_is_priced_by_the_kilo(): void
    {
        $this->seed(StarterCatalogSeeder::class);
        $tomatoes = Product::where('slug', 'sample-tomatoes')->with('variants')->first();

        $this->postJson('/api/v1/cart/price', ['items' => [[
            'product_id' => $tomatoes->id, 'variant_id' => $tomatoes->variants->first()->id,
            'quantity' => 1, 'options' => ['weight' => 2.5],
        ]]])->assertJsonPath('data.items.0.unit_price', 100);
    }

    public function test_running_it_again_changes_nothing_and_never_undoes_a_real_stock_count(): void
    {
        $this->seed(StarterCatalogSeeder::class);
        ProductVariant::where('sku', 'SAMPLE-BASMATI-RICE-1')->update(['stock' => 3]);   // staff counted real stock
        Product::where('slug', 'sample-margherita-pizza')->update(['price' => 175]);      // and repriced a dish
        $products = Product::count();
        $variants = ProductVariant::count();

        $this->seed(StarterCatalogSeeder::class);

        $this->assertSame($products, Product::count());
        $this->assertSame($variants, ProductVariant::count());
        $this->assertSame(3, (int) ProductVariant::where('sku', 'SAMPLE-BASMATI-RICE-1')->value('stock'));
        $this->assertEquals(175, Product::where('slug', 'sample-margherita-pizza')->value('price'));
    }

    public function test_a_delivery_type_chosen_in_the_admin_is_never_overwritten(): void
    {
        $this->seed(StarterCatalogSeeder::class);
        Category::where('slug', 'restaurant')->update(['delivery_profile' => 'parcel', 'prep_minutes' => 5]);

        $this->seed(StarterCatalogSeeder::class);

        $this->assertSame('parcel', Category::where('slug', 'restaurant')->value('delivery_profile'));
        $this->assertSame(5, (int) Category::where('slug', 'restaurant')->value('prep_minutes'));
    }
}
