<?php

namespace Database\Factories;

use App\Models\Category;
use App\Models\Product;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/** @extends Factory<Product> */
class ProductFactory extends Factory
{
    protected $model = Product::class;

    public function definition(): array
    {
        $title = Str::title($this->faker->unique()->words(3, true));
        $price = $this->faker->numberBetween(200, 9000);

        return [
            'title' => $title,
            'slug' => Str::slug($title).'-'.Str::lower(Str::random(4)),
            'description' => $this->faker->sentence(),
            'category_id' => Category::factory(),
            // Every product has a seller. Defaults to the house account so a
            // test that doesn't care about sellers still exercises the real
            // attribution and commission path rather than a null branch.
            'seller_id' => fn () => SellerFactory::house()->id,
            'brand' => $this->faker->company(),
            'mrp' => $price * 2,
            'price' => $price,
            'status' => 'ACTIVE',
            'cod_available' => true,
        ];
    }

    /** A fixed price, for tests that assert on exact totals. */
    public function pricedAt(float $price, ?float $mrp = null): static
    {
        return $this->state(fn () => ['price' => $price, 'mrp' => $mrp ?? $price * 2]);
    }

    public function soldBy(\App\Models\Seller $seller): static
    {
        return $this->state(fn () => ['seller_id' => $seller->id]);
    }

    public function draft(): static
    {
        return $this->state(fn () => ['status' => 'DRAFT']);
    }

    public function codUnavailable(): static
    {
        return $this->state(fn () => ['cod_available' => false]);
    }
}
