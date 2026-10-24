<?php

namespace Database\Factories;

use App\Models\Coupon;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/** @extends Factory<Coupon> */
class CouponFactory extends Factory
{
    protected $model = Coupon::class;

    public function definition(): array
    {
        return [
            'code' => 'TEST'.Str::upper(Str::random(6)),
            'description' => 'Test coupon',
            'type' => 'PERCENT',
            'value' => 10,
            'min_order' => 0,
            'max_discount' => null,
            'usage_limit' => null,
            'per_user_limit' => null,
            'target_type' => 'ALL',
            'target_ids' => null,
            'is_active' => true,
        ];
    }

    public function percent(float $value, ?float $maxDiscount = null): static
    {
        return $this->state(fn () => ['type' => 'PERCENT', 'value' => $value, 'max_discount' => $maxDiscount]);
    }

    public function flat(float $value): static
    {
        return $this->state(fn () => ['type' => 'FLAT', 'value' => $value]);
    }

    /** Restricted to specific products — the case that used to leak. */
    public function forProducts(array $productIds): static
    {
        return $this->state(fn () => ['target_type' => 'PRODUCT', 'target_ids' => $productIds]);
    }

    public function forCategories(array $categoryIds): static
    {
        return $this->state(fn () => ['target_type' => 'CATEGORY', 'target_ids' => $categoryIds]);
    }
}
