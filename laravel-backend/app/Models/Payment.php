<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Money a gateway actually captured. One row per gateway payment, whichever
 * gateway it was — `provider` records which, so a refund can go back the way the
 * money came in even after the default gateway changes.
 */
#[Fillable([
    'order_id', 'user_id', 'payment_intent_id', 'provider', 'provider_order_id',
    'provider_payment_id', 'method', 'amount_paise', 'refunded_paise', 'currency',
    'status', 'captured_at', 'meta',
])]
class Payment extends Model
{
    use HasUuids;

    protected function casts(): array
    {
        return [
            'amount_paise' => 'integer',
            'refunded_paise' => 'integer',
            'captured_at' => 'datetime',
            'meta' => 'array',
        ];
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function refunds()
    {
        return $this->hasMany(Refund::class);
    }

    /** What can still be sent back through the gateway. */
    public function refundablePaise(): int
    {
        return max(0, $this->amount_paise - $this->refunded_paise);
    }
}
