<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Database\Seeders\ShowcaseCatalogSeeder;
use Database\Seeders\StarterCatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The sample catalogue that fills a fresh store: safe to run twice, never destructive. */
class ShowcaseCatalogSeederTest extends TestCase
{
    use RefreshDatabase;

    private function seedAll(): void
    {
        $this->seed(StarterCatalogSeeder::class);
        $this->seed(ShowcaseCatalogSeeder::class);
    }

    public function test_it_adds_restaurant_produce_and_grocery_categories_with_their_options(): void
    {
        $this->seedAll();

        $restaurant = Category::where('slug', 'restaurant')->first();
        $this->assertSame(['portion', 'add_ons', 'leave_out', 'spice_level'], array_column($restaurant->option_groups, 'key'));

        $produce = Category::where('slug', 'fresh-produce')->first();
        $this->assertSame('stepper', $produce->option_groups[0]['type']);

        $this->assertNull(Category::where('slug', 'groceries')->first()->option_groups);
    }

    public function test_every_sample_is_labelled_active_and_in_stock(): void
    {
        $this->seedAll();

        $showcase = Product::where('slug', 'like', 'sample-%')
            ->whereHas('variants', fn ($q) => $q->where('sku', 'like', 'SHOW-%'))->get();

        $this->assertGreaterThanOrEqual(15, $showcase->count());
        foreach ($showcase as $product) {
            $this->assertStringStartsWith('Sample: ', $product->title);
            $this->assertSame('ACTIVE', $product->status);
            $this->assertTrue($product->cod_available);
            $this->assertGreaterThan(0, $product->variants->sum('stock'));
        }
    }

    public function test_a_dish_can_actually_be_priced_and_bought(): void
    {
        $this->seedAll();
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
        $this->seedAll();
        $tomatoes = Product::where('slug', 'sample-tomatoes')->with('variants')->first();

        $this->postJson('/api/v1/cart/price', ['items' => [[
            'product_id' => $tomatoes->id, 'variant_id' => $tomatoes->variants->first()->id,
            'quantity' => 1, 'options' => ['weight' => 2.5],
        ]]])->assertJsonPath('data.items.0.unit_price', 100);
    }

    public function test_the_kurta_has_swatches_and_sizes_with_their_own_stock(): void
    {
        $this->seedAll();
        $kurta = Product::where('slug', 'sample-cotton-kurta')->with('variants')->first();

        $this->assertSame(['Maroon', 'Navy', 'Olive'], $kurta->variants->pluck('color')->unique()->sort()->values()->all());
        $this->assertSame('#1F3A93', $kurta->variants->firstWhere('color', 'Navy')->color_hex);
    }

    public function test_the_sold_out_starter_samples_become_buyable(): void
    {
        $this->seed(StarterCatalogSeeder::class);
        $this->assertSame(0, ProductVariant::where('sku', 'like', 'SAMPLE-%')->sum('stock'));

        $this->seed(ShowcaseCatalogSeeder::class);

        $this->assertSame(0, ProductVariant::where('sku', 'like', 'SAMPLE-%')->where('stock', 0)->count());
        $this->assertTrue((bool) Product::where('slug', 'sample-anarkali-set')->value('cod_available'));
    }

    public function test_running_it_again_changes_nothing_and_never_undoes_a_real_stock_count(): void
    {
        $this->seedAll();
        $variant = ProductVariant::where('sku', 'SAMPLE-ANARKALI-SET-1')->first();
        $variant->update(['stock' => 3]);   // staff counted real stock
        Product::where('slug', 'sample-margherita-pizza')->update(['price' => 175]);   // and repriced a dish
        $products = Product::count();
        $variants = ProductVariant::count();

        $this->seed(ShowcaseCatalogSeeder::class);

        $this->assertSame($products, Product::count());
        $this->assertSame($variants, ProductVariant::count());
        $this->assertSame(3, $variant->fresh()->stock);
        $this->assertEquals(175, Product::where('slug', 'sample-margherita-pizza')->value('price'));
    }

    public function test_each_kind_of_item_gets_the_delivery_it_needs(): void
    {
        $this->seedAll();

        $this->assertSame(['instant', 25], [Category::where('slug', 'restaurant')->value('delivery_profile'), Category::where('slug', 'restaurant')->value('prep_minutes')]);
        $this->assertSame('instant', Category::where('slug', 'fresh-produce')->value('delivery_profile'));
        $this->assertSame('parcel', Category::where('slug', 'ethnic-wear')->value('delivery_profile'));
        $this->assertSame('parcel', Category::where('slug', 'electronics')->value('delivery_profile'));
    }

    public function test_a_profile_chosen_in_the_admin_is_never_overwritten(): void
    {
        $this->seedAll();
        Category::where('slug', 'restaurant')->update(['delivery_profile' => 'parcel', 'prep_minutes' => 5]);

        $this->seed(ShowcaseCatalogSeeder::class);

        $this->assertSame('parcel', Category::where('slug', 'restaurant')->value('delivery_profile'));
        $this->assertSame(5, (int) Category::where('slug', 'restaurant')->value('prep_minutes'));
    }
}
