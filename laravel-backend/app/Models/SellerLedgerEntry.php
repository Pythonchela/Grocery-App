<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * One movement in what a seller is owed.
 *
 * Signed and append-only: a sale credits, a refund debits, and the balance is
 * the running sum. Nothing here is ever edited or deleted, so "why is my payout
 * this number" is always answerable by reading rows rather than by trusting a
 * total someone recomputed.
 */
#[Fillable([
    'seller_id', 'order_id', 'order_item_id', 'type',
    'gross', 'commission', 'net', 'balance_after', 'note',
    'gst', 'tcs', 'tds',
])]
class SellerLedgerEntry extends Model
{
    use HasFactory, HasUuids;

    protected function casts(): array
    {
        return [
            'gross' => 'decimal:2',
            'commission' => 'decimal:2',
            'gst' => 'decimal:2',
            'tcs' => 'decimal:2',
            'tds' => 'decimal:2',
            'net' => 'decimal:2',
            'balance_after' => 'decimal:2',
        ];
    }

    public function seller()
    {
        return $this->belongsTo(Seller::class);
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function orderItem()
    {
        return $this->belongsTo(OrderItem::class);
    }
}
