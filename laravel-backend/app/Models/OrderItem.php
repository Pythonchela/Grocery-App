<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'order_id', 'product_id', 'variant_id', 'quantity', 'price', 'mrp', 'discount_allocated',
    'seller_id', 'commission_rate', 'commission_amount', 'seller_earning', 'selected_options',
    // The shop's answer to the order; see App\Services\SellerOrderDesk.
    'seller_response', 'accept_by', 'accepted_at', 'prep_minutes', 'ready_by',
    // What was deducted from the seller besides commission (see Seller::splitOf).
    'gst_on_commission', 'tcs', 'tds',
])]
class OrderItem extends Model
{
    use HasFactory, HasUuids;

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'mrp' => 'decimal:2',
            'discount_allocated' => 'decimal:2',
            'commission_rate' => 'decimal:2',
            'commission_amount' => 'decimal:2',
            'seller_earning' => 'decimal:2',
            'gst_on_commission' => 'decimal:2',
            'tcs' => 'decimal:2',
            'tds' => 'decimal:2',
            'selected_options' => 'array',
            'packed_at' => 'datetime',
            'shipped_at' => 'datetime',
            'accept_by' => 'datetime',
            'accepted_at' => 'datetime',
            'ready_by' => 'datetime',
            'rejected_at' => 'datetime',
        ];
    }

    public function seller()
    {
        return $this->belongsTo(Seller::class);
    }

    /** What was paid for this whole line, after its share of the discount. */
    public function netPaidTotal(): float
    {
        return round(max(0, ((float) $this->price * $this->quantity) - (float) $this->discount_allocated), 2);
    }

    /**
     * What was actually paid for this line, after its share of the order-level
     * discount. This — not `price` — is what a refund is worth.
     */
    public function netPaidPerUnit(): float
    {
        if ($this->quantity <= 0) {
            return 0.0;
        }

        $net = ((float) $this->price * $this->quantity) - (float) $this->discount_allocated;

        return round(max(0, $net) / $this->quantity, 2);
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    public function variant()
    {
        return $this->belongsTo(ProductVariant::class, 'variant_id');
    }

    public function returnRequests()
    {
        return $this->hasMany(ReturnRequest::class);
    }
}
