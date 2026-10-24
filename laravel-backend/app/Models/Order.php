<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'order_number', 'user_id', 'status', 'payment_status', 'payment_method', 'transaction_id',
    'subtotal', 'discount', 'shipping_charge', 'total_amount', 'shipping_address',
    'courier', 'carrier', 'service_level', 'delivery_fee_paise', 'promised_by',
    'tracking_no', 'label_generated',
    'coupon_id', 'coupon_code', 'wallet_applied',
    'cancellation_reason', 'cancellation_code', 'cancelled_by', 'cancelled_at', 'delivered_at',
    'points_earned', 'points_redeemed',
])]
class Order extends Model
{
    use HasFactory, HasUuids;

    public const STAGES = ['PENDING', 'CONFIRMED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED'];

    /** Reasons staff can give when they cancel an order; the shop's own refusals are recorded by the system. */
    public const STAFF_CANCEL_CODES = [
        'CUSTOMER_REQUEST', 'SELLER_UNRESPONSIVE', 'OUT_OF_STOCK', 'ADDRESS_UNSERVICEABLE',
        'PAYMENT_ISSUE', 'FRAUD_SUSPECTED', 'DUPLICATE_ORDER', 'OTHER',
    ];

    protected $appends = ['tracking_mode'];

    /** 'live_map' or 'status_updates' - how the apps should show where this order is. */
    public function getTrackingModeAttribute(): string
    {
        return \App\Services\Delivery\Tracking\TrackingMode::for($this);
    }

    protected function casts(): array
    {
        return [
            'shipping_address' => 'array',
            'label_generated' => 'boolean',
            'subtotal' => 'decimal:2',
            'discount' => 'decimal:2',
            'shipping_charge' => 'decimal:2',
            'total_amount' => 'decimal:2',
            'wallet_applied' => 'decimal:2',
            // Read as a date by the tracking endpoint; left as a string it crashed
            // every dispatched order's tracking with a 500.
            'promised_by' => 'datetime',
            'cancelled_at' => 'datetime',
            'delivered_at' => 'datetime',
        ];
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function items()
    {
        return $this->hasMany(OrderItem::class);
    }

    public function coupon()
    {
        return $this->belongsTo(Coupon::class);
    }

    /** Gateway payments taken for this order (none for cash on delivery). */
    public function payments()
    {
        return $this->hasMany(Payment::class);
    }

    /** Every refund on the order, gateway and wallet alike. */
    public function refunds()
    {
        return $this->hasMany(Refund::class);
    }

    public function returnRequests()
    {
        return $this->hasMany(ReturnRequest::class);
    }

    /** Customers may only cancel before the order physically leaves the warehouse. */
    public function isCancellable(): bool
    {
        if (! in_array($this->status, ['PENDING', 'CONFIRMED', 'PACKED'], true)) {
            return false;
        }

        // One seller may have shipped while another has not, which leaves the
        // order still CONFIRMED. Cancelling then would refund the customer for a
        // parcel that is already on its way to them.
        return ! $this->items()->where('fulfilment_status', 'SHIPPED')->exists();
    }

    public function isReturnable(int $windowDays = 7): bool
    {
        if ($this->status !== 'DELIVERED') {
            return false;
        }

        $deliveredAt = $this->delivered_at ?? $this->updated_at;

        return $deliveredAt->diffInDays(now()) <= $windowDays;
    }
}
