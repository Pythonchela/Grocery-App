<?php

namespace Database\Factories;

use App\Models\Seller;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/** @extends Factory<Seller> */
class SellerFactory extends Factory
{
    protected $model = Seller::class;

    public function definition(): array
    {
        $name = $this->faker->unique()->company();

        return [
            'user_id' => null,
            'display_name' => $name,
            'slug' => Str::slug($name).'-'.Str::lower(Str::random(4)),
            'commission_rate' => 10,
            'status' => 'ACTIVE',
        ];
    }

    public function commission(float $rate): static
    {
        return $this->state(fn () => ['commission_rate' => $rate]);
    }

    public function suspended(): static
    {
        return $this->state(fn () => ['status' => 'SUSPENDED']);
    }

    public function pending(): static
    {
        return $this->state(fn () => ['status' => 'PENDING']);
    }

    /**
     * The platform's own inventory.
     *
     * Resolved rather than created blindly: the migration seeds exactly one
     * house seller, and a second would make `Seller::house()` ambiguous.
     */
    public static function house(): Seller
    {
        if ($existing = Seller::where('is_house', true)->first()) {
            return $existing;
        }

        $seller = Seller::factory()->create([
            'display_name' => config('app.name').' Retail',
            'slug' => 'house',
            'commission_rate' => 0,
        ]);

        // forceFill, because `is_house` is deliberately not mass-assignable:
        // it's a privilege flag, and no payload should be able to mint one.
        $seller->forceFill(['is_house' => true])->save();

        return $seller;
    }
}
