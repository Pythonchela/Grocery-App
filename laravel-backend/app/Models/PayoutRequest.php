<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A seller's request to be paid what is withdrawable. Staff pay it by bank
 * transfer and record the reference (PAID), or decline with a reason (REJECTED).
 */
#[Fillable([
    'seller_id', 'amount', 'status', 'note', 'decision_note', 'reference',
    'ledger_entry_id', 'requested_at', 'decided_at',
])]
class PayoutRequest extends Model
{
    use HasUuids;

    public const REQUESTED = 'REQUESTED';
    public const PAID = 'PAID';
    public const REJECTED = 'REJECTED';
    public const CANCELLED = 'CANCELLED';

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'requested_at' => 'datetime',
            'decided_at' => 'datetime',
        ];
    }

    public function seller()
    {
        return $this->belongsTo(Seller::class);
    }
}
