<?php

namespace App\Services;

use App\Models\Coupon;
use App\Models\CouponRedemption;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\ProductVariant;
use App\Models\Refund;
use App\Models\Seller;
use App\Services\Options\ProductOptions;
use App\Services\Payments\PaymentService;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * The shop's side of taking an order: accept it, promise a time, or turn it down.
 *
 * Every order line starts either ACCEPTED (the shop takes orders automatically,
 * which is how every shop worked before this existed) or PENDING (the shop
 * confirms each one by hand, inside a window). A PENDING line nobody answers is
 * turned down by the system so the customer is never left waiting on a shop
 * that is not there.
 *
 * Turning a line down undoes exactly that line: its stock goes back, what it
 * credited the seller is taken back, and the customer is refunded what they paid
 * for it. When it was the last live line the whole order is cancelled and the
 * customer gets back everything, delivery charge included.
 */
class SellerOrderDesk
{
    /** Why a shop turns an order down. */
    public const REASONS = ['OUT_OF_STOCK', 'SHOP_CLOSED', 'CANNOT_PREPARE', 'DAMAGED', 'OTHER'];

    /** Only the system uses this one. */
    public const NO_RESPONSE = 'NO_RESPONSE';

    private const OPEN = ['CONFIRMED', 'PACKED'];

    public function __construct(
        private readonly NotificationService $notifications,
        private readonly PaymentService $payments,
        private readonly LoyaltyService $loyalty,
        private readonly FulfilmentService $fulfilment,
    ) {}

    /** Minutes a shop has to answer a new order. */
    /** Share of the lines a shop was asked to answer, in the window, that it took on. */
    public static function acceptanceRate($lines, $since): ?float
    {
        $answered = (clone $lines)->where('created_at', '>=', $since)->where(fn ($q) => $q
            ->where('seller_response', 'ACCEPTED')
            ->orWhere(fn ($r) => $r->where('seller_response', 'REJECTED')->where('rejected_by', '!=', 'ADMIN')));

        $total = (clone $answered)->count();

        if ($total === 0) {
            return null;
        }

        $accepted = (clone $answered)->where('seller_response', 'ACCEPTED')->count();

        return round($accepted * 100 / $total, 1);
    }

    public static function acceptWindowMinutes(): int
    {
        return max(1, (int) config('marketplace.accept_window_minutes', 15));
    }

    /**
     * The acceptance columns a new order line is created with.
     *
     * @return array<string, mixed>
     */
    public static function intakeFor(?Seller $seller): array
    {
        if ($seller && $seller->auto_accept === false) {
            return [
                'seller_response' => 'PENDING',
                'accept_by' => now()->addMinutes(self::acceptWindowMinutes()),
            ];
        }

        $prep = $seller?->prep_minutes;

        return [
            'seller_response' => 'ACCEPTED',
            'accepted_at' => now(),
            'prep_minutes' => $prep,
            'ready_by' => $prep ? now()->addMinutes($prep) : null,
        ];
    }

    /** The shop takes the line on, promising it will be ready in $prepMinutes. */
    public function accept(OrderItem $item, ?int $prepMinutes = null): OrderItem
    {
        return DB::transaction(function () use ($item, $prepMinutes) {
            [$item, $order] = $this->lock($item);

            if ($item->seller_response === 'ACCEPTED') {
                return $item;
            }

            if ($item->seller_response === 'REJECTED') {
                $this->refuse('This order was cancelled, so it can no longer be accepted.');
            }

            $this->requireOpen($order);

            $prep = $prepMinutes ?? $item->seller?->prep_minutes;

            $item->forceFill([
                'seller_response' => 'ACCEPTED',
                'accepted_at' => now(),
                'prep_minutes' => $prep,
                'ready_by' => $prep ? now()->addMinutes($prep) : null,
            ])->save();

            return $item->fresh();
        });
    }

    /**
     * Turn a line down — before it is accepted, or after, up to the moment it is
     * handed to a courier. $by is SELLER, ADMIN or SYSTEM.
     */
    public function decline(OrderItem $item, string $reason, ?string $note = null, string $by = 'SELLER'): OrderItem
    {
        return DB::transaction(function () use ($item, $reason, $note, $by) {
            [$item, $order] = $this->lock($item);

            if ($item->seller_response === 'REJECTED') {
                return $item;
            }

            if ($item->fulfilment_status === 'SHIPPED') {
                $this->refuse('This item has already been shipped, so it cannot be cancelled here.');
            }

            $this->requireOpen($order);

            $item->forceFill([
                'seller_response' => 'REJECTED',
                'fulfilment_status' => 'CANCELLED',
                'rejected_at' => now(),
                'rejection_reason' => $reason,
                'rejection_note' => $note ? mb_substr($note, 0, 300) : null,
                'rejected_by' => $by,
            ])->save();

            $this->undoLine($item, $order, $reason);

            $order->load('user');
            $live = $order->items()->where('seller_response', '!=', 'REJECTED')->count();

            if ($live === 0) {
                $this->cancelWholeOrder($order, $item, $reason, $by);
            } else {
                $refunded = $this->refundLine($item, $order);
                // The rest of the order carries on; it may now be complete.
                $this->fulfilment->settle($order->fresh());
                $this->tellCustomerOfLine($order, $item, $refunded);
            }

            return $item->fresh();
        });
    }

    /** Turn down every line nobody answered in time. Returns how many. */
    public function expireUnanswered(): int
    {
        $count = 0;

        OrderItem::where('seller_response', 'PENDING')
            ->where('accept_by', '<=', now())
            ->orderBy('accept_by')
            ->limit(200)
            ->get()
            ->each(function (OrderItem $item) use (&$count) {
                try {
                    $this->decline($item, self::NO_RESPONSE, 'The shop did not respond in time.', 'SYSTEM');
                    $count++;
                } catch (ValidationException) {
                    // The order moved on (cancelled by the customer, say): nothing to expire.
                    $item->forceFill(['seller_response' => 'REJECTED'])->save();
                }
            });

        return $count;
    }

    // ── Internals ───────────────────────────────────────────────────────

    private function lock(OrderItem $item): array
    {
        $order = Order::whereKey($item->order_id)->lockForUpdate()->firstOrFail();
        $item = OrderItem::whereKey($item->id)->lockForUpdate()->firstOrFail();

        return [$item, $order];
    }

    private function requireOpen(Order $order): void
    {
        if (! in_array($order->status, self::OPEN, true)) {
            $this->refuse($order->status === 'CANCELLED'
                ? 'This order was already cancelled.'
                : 'This order is no longer open for changes.');
        }
    }

    private function refuse(string $message): never
    {
        throw ValidationException::withMessages(['fulfilment' => [$message]]);
    }

    /** Put the stock back and take back what the sale paid the seller. */
    private function undoLine(OrderItem $item, Order $order, string $reason): void
    {
        if ($item->variant_id) {
            ProductVariant::where('id', $item->variant_id)->increment('stock', $item->quantity);

            // "Out of stock" means exactly that: stop selling it until the shop restocks.
            if ($reason === 'OUT_OF_STOCK') {
                ProductVariant::where('id', $item->variant_id)->update(['stock' => 0]);
            }
        }

        ProductOptions::restock($item, (int) $item->quantity);

        app(SellerPayoutService::class)->debitRefund($item, $order, (int) $item->quantity, $item->netPaidTotal());
    }

    private function alreadyRefunded(Order $order): float
    {
        return (int) Refund::where('order_id', $order->id)->where('status', '!=', 'FAILED')->sum('amount_paise') / 100;
    }

    /** What the customer put in towards this line, capped by what is still refundable. */
    private function refundLine(OrderItem $item, Order $order): float
    {
        $paid = $order->payment_status === 'PAID';
        $line = $item->netPaidTotal();

        $amount = $paid
            ? $line
            : min($line, max(0.0, (float) $order->wallet_applied - $this->alreadyRefunded($order)));

        if ($amount > 0) {
            $this->payments->refundOrder($order, $amount, "Item cancelled on {$order->order_number}", "reject:{$item->id}");
        }

        return $amount;
    }

    private function cancelWholeOrder(Order $order, OrderItem $last, string $reason, string $by): void
    {
        $paid = $order->payment_status === 'PAID';

        $this->loyalty->revoke($order->user, (int) $order->points_earned, "Reversed — order {$order->order_number} cancelled", $order);

        if ((int) $order->points_redeemed > 0) {
            $this->loyalty->credit($order->user, (int) $order->points_redeemed, "Returned — order {$order->order_number} cancelled", $order);
        }

        if ($order->coupon_id) {
            Coupon::where('id', $order->coupon_id)->where('used_count', '>', 0)->decrement('used_count');
            CouponRedemption::where('order_id', $order->id)->delete();
        }

        $tender = $paid ? (float) $order->total_amount + (float) $order->wallet_applied : (float) $order->wallet_applied;
        $remaining = round($tender - $this->alreadyRefunded($order), 2);

        $order->update([
            'status' => 'CANCELLED',
            'payment_status' => $paid ? 'REFUNDED' : $order->payment_status,
            'cancellation_reason' => $reason === self::NO_RESPONSE
                ? 'The shop did not respond in time'
                : 'The shop could not fulfil this order',
            'cancelled_at' => now(),
            'cancellation_code' => $reason === self::NO_RESPONSE ? 'SELLER_NO_RESPONSE' : 'SELLER_DECLINED',
            'cancelled_by' => $by,
        ]);

        if ($remaining > 0) {
            $this->payments->refundOrder($order, $remaining, "Cancellation refund for {$order->order_number}", "reject-final:{$order->id}");
        }

        $this->notifications->orderStatusChanged($order->fresh(), 'CANCELLED');
    }

    private function tellCustomerOfLine(Order $order, OrderItem $item, float $refunded): void
    {
        $title = $item->product?->title ?? 'An item';
        $money = $refunded > 0 ? ' ₹'.number_format($refunded, 2).' is on its way back to you.' : '';

        $this->notifications->send(
            $order->user,
            'ORDER_UPDATE',
            "{$title} was cancelled on order {$order->order_number}",
            'The shop could not fulfil it.'.$money.' The rest of your order is on track.',
            ['order_id' => $order->id, 'order_number' => $order->order_number],
        );
    }
}
