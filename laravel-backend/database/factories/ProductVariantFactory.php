<?php

namespace Database\Factories;

use App\Models\Product;
use App\Models\ProductVariant;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/** @extends Factory<ProductVariant> */
class ProductVariantFactory extends Factory
{
    protected $model = ProductVariant::class;

    public function definition(): array
    {
        return [
            'product_id' => Product::factory(),
            'sku' => 'SKU-'.Str::upper(Str::random(8)),
            'color' => $this->faker->safeColorName(),
            'size' => 'M',
            // Null price/mrp is the common case: the variant inherits the
            // product's, which is the path `effective_price` exists for.
            'price' => null,
            'mrp' => null,
            'stock' => 25,
        ];
    }

    public function withStock(int $stock): static
    {
        return $this->state(fn () => ['stock' => $stock]);
    }

    public function pricedAt(float $price): static
    {
        return $this->state(fn () => ['price' => $price]);
    }
}
