<?php

namespace App\Services;

use App\Models\Order;
use App\Models\OrderItem;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Packing and shipping, one order line at a time.
 *
 * A seller can only ever act on their own lines, so a basket with two sellers'
 * goods ships as two parcels on two timelines. The order the customer sees is
 * derived from its lines:
 *
 *   every line packed or shipped  → order PACKED
 *   every line shipped            → order SHIPPED
 *
 * and never moves backwards, and never touches an order that is already out for
 * delivery, delivered or cancelled — from that point the courier (and, for
 * exceptions, staff) own the status.
 */
class FulfilmentService
{
    /** Order statuses in which a line may still be packed or shipped. */
    private const OPEN = ['CONFIRMED', 'PACKED'];

    public function __construct(private readonly NotificationService $notifications) {}

    /** Mark a line packed. Saying it twice changes nothing. */
    public function pack(OrderItem $item): OrderItem
    {
        return DB::transaction(function () use ($item) {
            [$item, $order] = $this->lock($item);

            if ($item->fulfilment_status === 'SHIPPED') {
                $this->refuse('This item has already been shipped.');
            }

            $this->requireOpen($order);
            $this->requireAccepted($item);

            if ($item->fulfilment_status === 'PENDING') {
                $item->forceFill(['fulfilment_status' => 'PACKED', 'packed_at' => now()])->save();
                $this->rollUp($order);
            }

            return $item->fresh();
        });
    }

    /**
     * Hand a line to a courier. A tracking number is the whole point — without
     * one the customer has nothing to follow — so both are required.
     *
     * Saying it again with different details corrects them, until the order is
     * out for delivery.
     */
    public function ship(OrderItem $item, string $courier, string $trackingNo): OrderItem
    {
        return DB::transaction(function () use ($item, $courier, $trackingNo) {
            [$item, $order] = $this->lock($item);

            if ($item->fulfilment_status === 'SHIPPED') {
                // A correction is only meaningful while the parcel is still with
                // the seller's courier, i.e. before the order is handed on.
                if (! in_array($order->status, [...self::OPEN, 'SHIPPED'], true)) {
                    $this->refuse('This order is already out for delivery, so the tracking details can no longer be changed.');
                }
            } else {
                $this->requireOpen($order);
                $this->requireAccepted($item);
            }

            $item->forceFill([
                'fulfilment_status' => 'SHIPPED',
                'packed_at' => $item->packed_at ?? now(),
                'shipped_at' => $item->shipped_at ?? now(),
                'courier' => $courier,
                'tracking_no' => $trackingNo,
            ])->save();

            $this->rollUp($order);

            return $item->fresh();
        });
    }

    /**
     * Staff moved the whole order forward themselves (the platform's own stock,
     * or an exception). Bring its lines into line so nothing still says
     * "to pack" on an order that has already left.
     */
    public function syncLinesToOrderStatus(Order $order): void
    {
        $target = match ($order->status) {
            'PACKED' => 'PACKED',
            'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED' => 'SHIPPED',
            default => null,
        };

        if (! $target) {
            return;
        }

        $order->items()
            ->where('fulfilment_status', '!=', 'SHIPPED')
            ->where('fulfilment_status', '!=', 'CANCELLED')
            ->when($target === 'PACKED', fn ($q) => $q->where('fulfilment_status', 'PENDING'))
            ->update([
                'fulfilment_status' => $target,
                'packed_at' => now(),
                'shipped_at' => $target === 'SHIPPED' ? now() : null,
            ]);
    }

    // ── Internals ───────────────────────────────────────────────────────

    /** Both rows locked, so two sellers acting at once cannot roll up on stale data. */
    private function lock(OrderItem $item): array
    {
        $order = Order::whereKey($item->order_id)->lockForUpdate()->firstOrFail();
        $item = OrderItem::whereKey($item->id)->lockForUpdate()->firstOrFail();

        return [$item, $order];
    }

    private function requireAccepted(OrderItem $item): void
    {
        if ($item->seller_response === 'REJECTED' || $item->fulfilment_status === 'CANCELLED') {
            $this->refuse('This item was cancelled, so there is nothing to pack or ship.');
        }

        if ($item->seller_response === 'PENDING') {
            $this->refuse('Accept this order before packing it.');
        }
    }

    private function requireOpen(Order $order): void
    {
        if (! in_array($order->status, self::OPEN, true)) {
            $this->refuse(match ($order->status) {
                'CANCELLED' => 'This order was cancelled, so there is nothing to pack or ship.',
                'DELIVERED' => 'This order has already been delivered.',
                'SHIPPED', 'OUT_FOR_DELIVERY' => 'This order has already left for delivery.',
                default => 'This order is not ready to be packed yet.',
            });
        }
    }

    private function refuse(string $message): never
    {
        throw ValidationException::withMessages(['fulfilment' => [$message]]);
    }

    /** Re-derive an order's status after its lines changed (a line was cancelled, say). */
    public function settle(Order $order): void
    {
        $this->rollUp($order);
    }

    /** Derive the order's status from its lines, in one direction only. */
    private function rollUp(Order $order): void
    {
        if (! in_array($order->status, self::OPEN, true)) {
            return;
        }

        // A line the shop turned down is not waiting to be packed or shipped.
        $lines = $order->items()->where('fulfilment_status', '!=', 'CANCELLED')->get();
        if ($lines->isEmpty()) {
            return;
        }

        $allShipped = $lines->every(fn (OrderItem $i) => $i->fulfilment_status === 'SHIPPED');
        $allPacked = $lines->every(fn (OrderItem $i) => in_array($i->fulfilment_status, ['PACKED', 'SHIPPED'], true));

        $next = match (true) {
            $allShipped => 'SHIPPED',
            $allPacked && $order->status === 'CONFIRMED' => 'PACKED',
            default => null,
        };

        if (! $next) {
            return;
        }

        $attributes = ['status' => $next];

        // One parcel, one tracking number: surface it on the order too, where the
        // rest of the app already looks. A split order keeps them per line.
        if ($next === 'SHIPPED') {
            $parcels = $lines->map(fn (OrderItem $i) => [$i->courier, $i->tracking_no])->unique(fn ($p) => implode('|', $p));

            if ($parcels->count() === 1 && filled($parcels->first()[1])) {
                [$attributes['courier'], $attributes['tracking_no']] = $parcels->first();
            }
        }

        $order->update($attributes);
        $this->notifications->orderStatusChanged($order->load('user'), $next);
    }
}
