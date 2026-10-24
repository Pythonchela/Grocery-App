<?php

namespace App\Services;

use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Seller;
use App\Models\SellerLedgerEntry;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * The only place a seller's payout balance changes.
 *
 * Modelled on WalletController::apply — one entry point, a row lock, and a
 * ledger row written in the same transaction as the balance it explains. A
 * balance that can be moved from several places is a balance nobody can
 * reconcile.
 */
class SellerPayoutService
{
    /** Credit a seller for a line they sold. */
    public function creditSale(OrderItem $item, Order $order): ?SellerLedgerEntry
    {
        if (! $item->seller_id) {
            return null;
        }

        return $this->record(
            sellerId: $item->seller_id,
            type: 'SALE',
            gross: (float) $item->netPaidTotal(),
            commission: (float) $item->commission_amount,
            net: (float) $item->seller_earning,
            order: $order,
            item: $item,
            note: "Sale on {$order->order_number}",
            taxes: [
                'gst' => (float) $item->gst_on_commission,
                'tcs' => (float) $item->tcs,
                'tds' => (float) $item->tds,
            ],
        );
    }

    /**
     * Debit a seller for units coming back.
     *
     * The commission is reversed in the same proportion as the refund: the
     * platform doesn't keep its cut of a sale that didn't stick. Partial
     * returns refund per unit, so the split is apportioned by quantity rather
     * than recomputed from the rate — recomputing would drift against the rate
     * that was snapshotted at purchase.
     */
    public function debitRefund(OrderItem $item, Order $order, int $quantity, float $refundAmount): ?SellerLedgerEntry
    {
        if (! $item->seller_id || $quantity <= 0) {
            return null;
        }

        $share = min(1.0, $quantity / max(1, (int) $item->quantity));
        $commission = round((float) $item->commission_amount * $share, 2);
        $taxes = [
            'gst' => round((float) $item->gst_on_commission * $share, 2),
            'tcs' => round((float) $item->tcs * $share, 2),
            'tds' => round((float) $item->tds * $share, 2),
        ];
        $net = round($refundAmount - $commission - array_sum($taxes), 2);

        return $this->record(
            sellerId: $item->seller_id,
            type: 'REFUND',
            gross: -$refundAmount,
            commission: -$commission,
            net: -$net,
            order: $order,
            item: $item,
            note: "Refund on {$order->order_number}",
            taxes: array_map(fn ($t) => -$t, $taxes),
        );
    }

    // ── What can actually be paid out ───────────────────────────────────

    /**
     * What a seller has earned on orders that are not yet safe to pay out: not
     * delivered, or delivered less than the return window ago. Until then the
     * goods can still come back (or never arrive), and a refund would be taken
     * from money that has already left.
     *
     * Read from the ledger rather than stored, so it can never drift from it:
     * every sale and refund tied to an order that has not cleared the window.
     * Never below zero.
     */
    public function pending(Seller $seller): float
    {
        $clearedBefore = now()->subDays(\App\Http\Controllers\Api\ReturnController::RETURN_WINDOW_DAYS);

        $sum = (float) SellerLedgerEntry::where('seller_id', $seller->id)
            ->whereIn('type', ['SALE', 'REFUND'])
            ->whereHas('order', fn ($q) => $q->where(
                fn ($q) => $q->where('status', '!=', 'DELIVERED')
                    ->orWhereNull('delivered_at')
                    ->orWhere('delivered_at', '>', $clearedBefore)
            ))
            ->sum('net');

        return max(0.0, round($sum, 2));
    }

    /** What may be paid out now: the balance, less what is still pending. Never below zero. */
    public function withdrawable(Seller $seller): float
    {
        return max(0.0, round((float) $seller->payout_balance - $this->pending($seller), 2));
    }

    /**
     * Record that a seller was paid [$amount] (a bank transfer made outside the
     * app, identified by [$reference], e.g. the UTR). It debits the balance, and
     * can never take more than is withdrawable: paying out a pending sale is
     * exactly the mistake this exists to prevent.
     *
     * @throws ValidationException
     */
    public function recordPayout(Seller $seller, float $amount, string $reference): SellerLedgerEntry
    {
        return DB::transaction(function () use ($seller, $amount, $reference) {
            // Locked, so two payouts recorded at once cannot both spend the same money.
            $locked = Seller::whereKey($seller->id)->lockForUpdate()->firstOrFail();
            $available = $this->withdrawable($locked);

            if ($amount <= 0 || round($amount, 2) > $available + 0.004) {
                throw ValidationException::withMessages([
                    'amount' => [$available <= 0
                        ? 'There is nothing to pay out yet. Earnings become payable once the orders are delivered and the return window has passed.'
                        : 'The most that can be paid out now is ₹'.number_format($available, 2).'.'],
                ]);
            }

            return $this->record(
                sellerId: $locked->id,
                type: 'PAYOUT',
                gross: -$amount,
                commission: 0.0,
                net: -$amount,
                order: null,
                item: null,
                note: 'Payout '.$reference,
            );
        });
    }

    /** Manual correction — goodwill, chargeback, negotiated adjustment. */
    public function adjust(Seller $seller, float $net, string $note): SellerLedgerEntry
    {
        return $this->record(
            sellerId: $seller->id,
            type: 'ADJUSTMENT',
            gross: $net,
            commission: 0.0,
            net: $net,
            order: null,
            item: null,
            note: $note,
        );
    }

    private function record(
        string $sellerId,
        string $type,
        float $gross,
        float $commission,
        float $net,
        ?Order $order,
        ?OrderItem $item,
        string $note,
        array $taxes = [],
    ): SellerLedgerEntry {
        return DB::transaction(function () use ($sellerId, $type, $gross, $commission, $net, $order, $item, $note, $taxes) {
            $seller = Seller::whereKey($sellerId)->lockForUpdate()->firstOrFail();

            $balance = round((float) $seller->payout_balance + $net, 2);

            // Assigned directly rather than via update(): payout_balance is
            // deliberately not mass-assignable, so no request payload can set
            // what a seller is owed.
            $seller->payout_balance = $balance;
            $seller->save();

            return SellerLedgerEntry::create([
                'seller_id' => $seller->id,
                'order_id' => $order?->id,
                'order_item_id' => $item?->id,
                'type' => $type,
                'gross' => $gross,
                'commission' => $commission,
                'net' => $net,
                'balance_after' => $balance,
                'note' => $note,
                'gst' => $taxes['gst'] ?? 0,
                'tcs' => $taxes['tcs'] ?? 0,
                'tds' => $taxes['tds'] ?? 0,
            ]);
        });
    }
}
