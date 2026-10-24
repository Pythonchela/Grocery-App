<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'code', 'description', 'type', 'value', 'min_order', 'max_discount',
    'usage_limit', 'per_user_limit', 'target_type', 'target_ids',
    'starts_at', 'expires_at', 'is_active', 'seller_id',
])]
class Coupon extends Model
{
    use HasFactory, HasUuids;

    protected function casts(): array
    {
        return [
            'target_ids' => 'array',
            'is_active' => 'boolean',
            'starts_at' => 'datetime',
            'expires_at' => 'datetime',
            'value' => 'decimal:2',
            'min_order' => 'decimal:2',
        ];
    }

    public function redemptions()
    {
        return $this->hasMany(CouponRedemption::class);
    }

    public function seller()
    {
        return $this->belongsTo(Seller::class);
    }

    /**
     * Validate against a cart. Returns an error string, or null when usable.
     * Kept on the model so checkout and the "apply coupon" preview endpoint
     * can never drift apart on the rules.
     */
    public function validateFor(User $user, float $subtotal, array $productIds, array $categoryIds): ?string
    {
        if (! $this->is_active) {
            return 'This coupon is no longer active.';
        }

        $now = now();
        if ($this->starts_at && $now->lt($this->starts_at)) {
            return 'This coupon is not active yet.';
        }
        if ($this->expires_at && $now->gt($this->expires_at)) {
            return 'This coupon has expired.';
        }
        if ($this->usage_limit !== null && $this->used_count >= $this->usage_limit) {
            return 'This coupon has reached its usage limit.';
        }
        if ($subtotal < (float) $this->min_order) {
            return 'Add ₹'.number_format((float) $this->min_order - $subtotal, 2).' more to use this coupon.';
        }

        if ($this->per_user_limit !== null) {
            $used = $this->redemptions()->where('user_id', $user->id)->count();
            if ($used >= $this->per_user_limit) {
                return 'You have already used this coupon.';
            }
        }

        if ($this->target_type === 'PRODUCT' && empty(array_intersect($this->target_ids ?? [], $productIds))) {
            return 'This coupon does not apply to the items in your cart.';
        }
        if ($this->target_type === 'CATEGORY' && empty(array_intersect($this->target_ids ?? [], $categoryIds))) {
            return 'This coupon does not apply to the items in your cart.';
        }

        return null;
    }

    /**
     * Whether this coupon covers a given line.
     *
     * `validateFor` asks "may this cart use the coupon at all"; this asks "does
     * this particular item get the discount". Keeping them separate is what
     * stops a targeted coupon from discounting the whole basket once one
     * qualifying item is present.
     */
    public function covers(string $productId, ?string $categoryId, ?string $sellerId = null): bool
    {
        if ($this->seller_id !== null && $this->seller_id !== $sellerId) {
            return false;
        }

        return match ($this->target_type) {
            'PRODUCT' => in_array($productId, $this->target_ids ?? [], true),
            'CATEGORY' => $categoryId !== null && in_array($categoryId, $this->target_ids ?? [], true),
            default => true,
        };
    }

    /**
     * The discount this coupon yields on a given base.
     *
     * The base is the *eligible* subtotal, not the cart subtotal — see
     * CartPricingService::applyCoupon().
     */
    public function discountFor(float $subtotal): float
    {
        $discount = $this->type === 'PERCENT'
            ? $subtotal * ((float) $this->value / 100)
            : (float) $this->value;

        if ($this->max_discount !== null) {
            $discount = min($discount, (float) $this->max_discount);
        }

        return round(min($discount, $subtotal), 2);
    }
}
