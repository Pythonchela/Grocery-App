<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * One movement of money back to a customer — to their original payment method
 * (SOURCE) or to their wallet (WALLET). Kept for every refund, not just the
 * gateway ones, so "how much of this order has been refunded" has one answer.
 */
#[Fillable([
    'payment_id', 'order_id', 'return_request_id', 'destination', 'provider',
    'provider_refund_id', 'amount_paise', 'status', 'reason', 'failure_reason',
    'reference', 'processed_at',
])]
class Refund extends Model
{
    use HasUuids;

    public const SOURCE = 'SOURCE';
    public const WALLET = 'WALLET';

    protected function casts(): array
    {
        return ['amount_paise' => 'integer', 'processed_at' => 'datetime'];
    }

    public function payment()
    {
        return $this->belongsTo(Payment::class);
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }
}
