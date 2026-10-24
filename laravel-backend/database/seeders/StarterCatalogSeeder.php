<?php

namespace Database\Seeders;

use App\Models\Category;
use App\Models\Product;
use App\Models\Seller;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

/** Starter catalog only: safe to run without creating logins or resetting edits. */
class StarterCatalogSeeder extends Seeder
{
    public function run(): void
    {
        $createdCategories = 0;
        $createdProducts = 0;

        DB::transaction(function () use (&$createdCategories, &$createdProducts) {
            $seller = Seller::house();
            $categories = [];
            $categoryRows = [
                ['ethnic-wear', 'Ethnic & Festive', 'Sparkles', 'photo-1610030469983-98e550d6193c'],
                ['casual-wear', 'Casual & Streetwear', 'Shirt', 'photo-1576995853123-5a10305d93c0'],
                ['footwear', 'Footwear & Sneakers', 'Zap', 'photo-1542291026-7eec264c27ff'],
                ['electronics', 'Electronics & Accessories', 'Headphones', 'photo-1505740420928-5e560c06d30e'],
                ['wellness', 'Beauty & Personal Care', 'Leaf', 'photo-1556229010-6c3f2c9ca5f8'],
            ];

            foreach ($categoryRows as $index => [$slug, $name, $icon, $photo]) {
                $category = Category::firstOrCreate(['slug' => $slug], [
                    'name' => $name,
                    'icon_url' => $icon,
                    'banner_url' => $this->image($photo),
                    'sort_order' => $index + 1,
                    'is_featured' => true,
                ]);
                $createdCategories += (int) $category->wasRecentlyCreated;
                $categories[$slug] = $category;
            }

            $productRows = [
                ['anarkali-set', 'Anarkali Set', 'ethnic-wear', 3499, 6999,
                    'photo-1610030469983-98e550d6193c', ['S', 'M', 'L', 'XL'], 'Pink',
                    ['occasion' => 'Festive', 'fit' => 'Regular'],
                    'An ethnic outfit example for the festive collection.'],
                ['sherwani-set', 'Sherwani & Stole Set', 'ethnic-wear', 7499, 12999,
                    'photo-1594938298603-c8148c4dae35', ['38', '40', '42'], 'Navy',
                    ['occasion' => 'Wedding', 'fit' => 'Regular'],
                    'A formal outfit example with a coordinating stole.'],
                ['denim-jacket', 'Indigo Denim Jacket', 'casual-wear', 2299, 4500,
                    'photo-1576995853123-5a10305d93c0', ['M', 'L', 'XL'], 'Blue',
                    ['material' => 'Denim', 'fit' => 'Relaxed'],
                    'A casual jacket example for an everyday layered look.'],
                ['casual-shirt', 'Everyday Casual Shirt', 'casual-wear', 1699, 3299,
                    'photo-1596755094514-f87e34085b2c', ['S', 'M', 'L', 'XL'], 'Olive',
                    ['fit' => 'Regular', 'occasion' => 'Casual'],
                    'A shirt example for the casual clothing collection.'],
                ['running-shoes', 'Everyday Running Shoes', 'footwear', 1899, 3999,
                    'photo-1542291026-7eec264c27ff', ['UK 7', 'UK 8', 'UK 9', 'UK 10'], 'Red',
                    ['style' => 'Running', 'closure' => 'Lace-up'],
                    'A lace-up sports shoe example for the footwear collection.'],
                ['leather-sneakers', 'Classic Low-Top Sneakers', 'footwear', 2499, 4999,
                    'photo-1549298916-b41d501d3772', ['UK 7', 'UK 8', 'UK 9', 'UK 10'], 'Tan',
                    ['style' => 'Sneakers', 'closure' => 'Lace-up'],
                    'A low-top sneaker example for everyday styling.'],
                ['headphones', 'Over-Ear Headphones', 'electronics', 1999, 3499,
                    'photo-1505740420928-5e560c06d30e', ['One Size'], 'Yellow',
                    ['type' => 'Headphones'],
                    'An over-ear headphone example for the accessories collection.'],
                ['smartwatch', 'Everyday Smartwatch', 'electronics', 2999, 4999,
                    'photo-1546868871-7041f2a55e12', ['One Size'], 'Black',
                    ['type' => 'Smartwatch'],
                    'A smartwatch example for the electronics collection.'],
                ['face-serum', 'Daily Face Serum', 'wellness', 599, 899,
                    'photo-1556229010-6c3f2c9ca5f8', ['30 ml'], 'Standard',
                    ['type' => 'Serum'],
                    'A personal care product example for the beauty collection.'],
                ['moisturizer', 'Daily Moisturizer', 'wellness', 449, 699,
                    'photo-1620916566398-39f1143ab7be', ['50 ml'], 'Standard',
                    ['type' => 'Moisturizer'],
                    'A moisturizer example for the personal care collection.'],
            ];

            foreach ($productRows as $index => [$slug, $title, $category, $price, $mrp, $photo, $sizes, $color, $attributes, $description]) {
                $product = Product::firstOrCreate(['slug' => 'sample-'.$slug], [
                    'title' => 'Sample: '.$title,
                    'description' => $description.' Sample listing: photos and prices are illustrative. Replace with your actual product details and inventory before sale.',
                    'category_id' => $categories[$category]->id,
                    'seller_id' => $seller->id,
                    'brand' => 'Sample Collection',
                    'mrp' => $mrp,
                    'price' => $price,
                    'images' => [$this->image($photo)],
                    'rollover_image' => $this->image($photo),
                    'status' => 'ACTIVE',
                    'is_new' => $index % 2 === 0,
                    'tags' => ['Sample Catalog'],
                    'attributes' => $attributes,
                    'features' => ['Illustrative sample product', 'Replace details before selling'],
                    'cod_available' => false,
                    'local_store_available' => false,
                    'express_pincodes' => [],
                    'hotspots' => [],
                ]);

                // Re-running this seed must preserve staff edits, stock, and variants.
                if (! $product->wasRecentlyCreated) {
                    continue;
                }

                $createdProducts++;
                foreach ($sizes as $variantIndex => $size) {
                    $product->variants()->create([
                        'sku' => strtoupper('SAMPLE-'.$slug.'-'.($variantIndex + 1)),
                        'size' => $size,
                        'color' => $color,
                        'stock' => 0,
                    ]);
                }
            }
        });

        Cache::forget('products.facets');
        $this->command?->info("Created {$createdCategories} categories and {$createdProducts} sample products.");
    }

    private function image(string $photo): string
    {
        return 'https://images.unsplash.com/'.$photo.'?auto=format&fit=crop&w=800&q=80';
    }
}
