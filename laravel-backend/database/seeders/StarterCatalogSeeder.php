<?php

namespace Database\Seeders;

use App\Models\Category;
use App\Models\Product;
use App\Models\Seller;
use App\Services\Options\ProductOptions;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

/**
 * Sample restaurant, fresh-produce and grocery items for the food and grocery app: portions
 * and add-ons on dishes, a weight in kg on produce, pack sizes on groceries, and the
 * veg / non-veg mark on all the food.
 *
 * Safe to run on a live site and safe to run twice. It only ever *adds* rows that are
 * missing (matched by slug) and never overwrites what staff have edited. Everything it makes
 * is titled "Sample: ..." so it is obvious, and easy to delete from the admin once real
 * items are in.
 */
class StarterCatalogSeeder extends Seeder
{
    public function run(): void
    {
        $created = ['categories' => 0, 'products' => 0];

        DB::transaction(function () use (&$created) {
            $seller = Seller::house();

            // Every category here is delivered by a local rider; "ready in" is how long the kitchen or packer needs.
            $restaurant = $this->category('restaurant', 'Restaurant', 'Flame', 1, 'photo-1574071318508-1cdbab80d002', 25, $this->foodTemplate(), [
                ['title' => 'Food details', 'labels' => ['Ingredients', 'Serves', 'Allergens']],
            ], $created);
            $produce = $this->category('fresh-produce', 'Fresh Produce', 'Leaf', 2, 'photo-1592924357228-91a4daadcfea', 15, $this->produceTemplate(), [
                ['title' => 'Produce details', 'labels' => ['Origin', 'Shelf life', 'Storage']],
            ], $created);
            $groceries = $this->category('groceries', 'Groceries', 'ShoppingBag', 3, 'photo-1586201375761-83865001e31c', 20, null, [
                ['title' => 'Food details', 'labels' => ['Ingredients', 'Shelf life', 'Storage', 'FSSAI licence no.']],
            ], $created, [
                // What a packet comes in, so the add-product page offers these as ticks.
                'size_label' => 'Pack size',
                'sizes' => ['100 g', '250 g', '500 g', '1 kg', '2 kg', '5 kg'],
                'color_label' => 'Flavour',
                'colors' => [],
            ]);

            // ── Restaurant: the category's template gives every dish a portion,
            //    add-ons, leave-outs and spice level. ────────────────────────────
            $dishes = [
                ['margherita-pizza', 'Margherita Pizza', 150, 180, 'photo-1574071318508-1cdbab80d002', 'Wood-fired, with fresh basil and mozzarella.', 'veg'],
                ['paneer-butter-masala', 'Paneer Butter Masala', 190, 230, 'photo-1631452180519-c014fe946bc7', 'Creamy tomato gravy with soft paneer cubes.', 'veg'],
                ['veg-biryani', 'Veg Dum Biryani', 170, 200, 'photo-1563379091339-03b21ab4a4f8', 'Fragrant basmati layered with vegetables and saffron.', 'veg'],
                ['chicken-biryani', 'Chicken Dum Biryani', 220, 260, 'photo-1563379091339-03b21ab4a4f8', 'Basmati slow-cooked with marinated chicken and saffron.', 'non_veg'],
                ['masala-dosa', 'Masala Dosa', 90, 110, 'photo-1668236543090-82eba5ee5976', 'Crisp dosa with spiced potato filling, sambar and chutney.', 'veg'],
            ];
            foreach ($dishes as [$slug, $title, $price, $mrp, $photo, $about, $diet]) {
                $this->product($restaurant, $seller, $slug, $title, $price, $mrp, $photo, $about, 'Sample Kitchen', 60, null, [['', '']], $diet, $created);
            }

            // A drink has no "half plate": its own options instead of the template.
            $this->product($restaurant, $seller, 'cold-coffee', 'Cold Coffee', 110, 130, 'photo-1461023058943-07fcbe16d735',
                'Chilled coffee blended with milk and ice.', 'Sample Kitchen', 60,
                ProductOptions::normalize([
                    ['label' => 'Size', 'type' => 'single', 'required' => true, 'price_mode' => 'set',
                        'choices' => [['label' => 'Regular', 'price' => 110, 'default' => true], ['label' => 'Large', 'price' => 160]]],
                    ['label' => 'Sugar', 'type' => 'single',
                        'choices' => [['label' => 'No sugar'], ['label' => 'Less sugar'], ['label' => 'Regular', 'default' => true]]],
                    ['label' => 'Extras', 'type' => 'multi', 'max' => 2,
                        'choices' => [['label' => 'Ice cream scoop', 'price' => 40], ['label' => 'Whipped cream', 'price' => 25]]],
                ], true, 'custom_options'),
                [['', '']], 'veg', $created);

            // ── Fresh produce: priced per kg; the shopper picks how many. ────────
            $items = [
                ['tomatoes', 'Farm Tomatoes (per kg)', 40, 48, 'photo-1592924357228-91a4daadcfea'],
                ['onions', 'Red Onions (per kg)', 35, 42, 'photo-1618512496248-a07fe83aa8cb'],
                ['potatoes', 'Potatoes (per kg)', 30, 36, 'photo-1518977676601-b53f82aba655'],
                ['apples', 'Shimla Apples (per kg)', 180, 220, 'photo-1560806887-1e4cd0b6cbd6'],
                ['bananas', 'Robusta Bananas (per kg)', 55, 65, 'photo-1571771894821-ce9b6c11b08e'],
            ];
            foreach ($items as [$slug, $title, $price, $mrp, $photo]) {
                $this->product($produce, $seller, $slug, $title, $price, $mrp, $photo,
                    'Picked fresh and priced per kg. Choose how much you need.', 'Sample Farm', 300, null, [['', '']], 'veg', $created);
            }

            // ── Groceries: plain packs, no choices to make. ───────────────────────
            $packs = [
                ['basmati-rice', 'Basmati Rice 5 kg', 520, 640, 'photo-1586201375761-83865001e31c', '5 kg'],
                ['sunflower-oil', 'Sunflower Oil 1 L', 140, 165, 'photo-1474979266404-7eaacbcd87c5', '1 L'],
                ['butter', 'Salted Butter 500 g', 285, 310, 'photo-1589985270826-4b7bb135bc9d', '500 g'],
                ['tea', 'Assam Tea 250 g', 130, 160, 'photo-1597318181409-cf64d0b5d8a2', '250 g'],
            ];
            foreach ($packs as [$slug, $title, $price, $mrp, $photo, $size]) {
                $this->product($groceries, $seller, $slug, $title, $price, $mrp, $photo,
                    'A pantry staple, packed fresh.', 'Sample Pantry', 150, null, [['', $size]], 'veg', $created);
            }
        });

        Cache::forget('products.facets');
        $this->command?->info("Added {$created['categories']} categories and {$created['products']} sample products.");
    }

    /** @return array<int, array<string, mixed>> */
    private function foodTemplate(): array
    {
        return ProductOptions::normalize([
            // The dish's listed price is the half plate; a full plate adds to it.
            ['label' => 'Portion', 'type' => 'single', 'required' => true, 'price_mode' => 'add',
                'choices' => [['label' => 'Half plate', 'price' => 0, 'default' => true], ['label' => 'Full plate', 'price' => 80]]],
            ['label' => 'Add-ons', 'type' => 'multi', 'max' => 3,
                'choices' => [['label' => 'Extra cheese', 'price' => 30], ['label' => 'Extra gravy', 'price' => 20], ['label' => 'Raita', 'price' => 25]]],
            ['label' => 'Leave out', 'type' => 'multi', 'remove' => true, 'max' => 3,
                'choices' => [['label' => 'Onion'], ['label' => 'Garlic'], ['label' => 'Coriander']]],
            ['label' => 'Spice level', 'type' => 'single',
                'choices' => [['label' => 'Mild'], ['label' => 'Medium', 'default' => true], ['label' => 'Hot']]],
        ]);
    }

    /** @return array<int, array<string, mixed>> */
    private function produceTemplate(): array
    {
        return ProductOptions::normalize([
            ['label' => 'Weight', 'type' => 'stepper', 'required' => true, 'price_mode' => 'multiply',
                'help' => 'The price shown is per kg.',
                'stepper' => ['min' => 0.5, 'max' => 10, 'step' => 0.5, 'unit' => 'kg', 'default' => 1]],
        ]);
    }

    /**
     * @param  array<int, array<string, mixed>>|null  $options  the choices every item here starts with
     * @param  array<int, array{title: string, labels: array<int, string>}>  $specs  rows to suggest when listing an item
     */
    private function category(string $slug, string $name, string $icon, int $order, string $photo, int $prepMinutes, ?array $options, array $specs, array &$created, ?array $variantSetup = null): Category
    {
        $category = Category::firstOrCreate(['slug' => $slug], [
            'name' => $name,
            'icon_url' => $icon,
            'banner_url' => $this->image($photo),
            'sort_order' => $order,
            'is_featured' => true,
            'option_groups' => $options,
            'variant_setup' => $variantSetup,
            'spec_template' => $specs,
            'delivery_profile' => 'instant',
            'prep_minutes' => $prepMinutes,
        ]);
        $created['categories'] += (int) $category->wasRecentlyCreated;

        return $category;
    }

    /**
     * @param  array<int, array{0: string, 1: string}>  $variants  [colour, pack size]
     */
    private function product(Category $category, Seller $seller, string $slug, string $title, int $price, int $mrp, string $photo,
        string $about, string $brand, int $stock, ?array $customOptions, array $variants, ?string $diet, array &$created): void
    {
        $product = Product::firstOrCreate(['slug' => 'sample-'.$slug], [
            'title' => 'Sample: '.$title,
            'description' => $about.' Sample listing: photos and prices are illustrative.',
            'category_id' => $category->id,
            'seller_id' => $seller->id,
            'brand' => $brand,
            'diet' => $diet,
            'mrp' => $mrp,
            'price' => $price,
            'images' => [$this->image($photo)],
            'status' => 'ACTIVE',
            'is_new' => in_array($slug, ['margherita-pizza', 'tomatoes'], true),
            'tags' => ['Sample Catalog'],
            'features' => ['Illustrative sample item'],
            'cod_available' => true,
            'local_store_available' => false,
            'express_pincodes' => [],
            'hotspots' => [],
            'custom_options' => $customOptions,
        ]);

        // Re-running must keep staff edits, stock and variants.
        if (! $product->wasRecentlyCreated) {
            return;
        }

        $created['products']++;
        foreach ($variants as $i => $row) {
            $product->variants()->create([
                'sku' => strtoupper('SAMPLE-'.$slug.'-'.($i + 1)),
                'color' => $row[0] ?? '',
                'size' => $row[1] ?? '',
                'stock' => $stock,
            ]);
        }
    }

    private function image(string $photo): string
    {
        return 'https://images.unsplash.com/'.$photo.'?auto=format&fit=crop&w=800&q=80';
    }
}
