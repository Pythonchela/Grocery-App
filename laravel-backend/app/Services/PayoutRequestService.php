<?php

namespace App\Services;

use App\Models\PayoutRequest;
use App\Models\Seller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Asking to be paid, and being paid.
 *
 * A seller may have one request open at a time, for no more than is withdrawable
 * and no less than the marketplace's minimum. Paying one goes through
 * SellerPayoutService::recordPayout, so the same rule that stops staff paying out
 * a pending sale stops a request from doing it too.
 */
class PayoutRequestService
{
    public function __construct(
        private readonly SellerPayoutService $payouts,
        private readonly NotificationService $notifications,
    ) {}

    public static function minimum(): float
    {
        return max(0.0, (float) config('marketplace.min_payout_amount', 100));
    }

    /** Why this seller cannot ask right now, or null when they can. */
    public function blocker(Seller $seller): ?string
    {
        if ($seller->is_house) {
            return 'The store\'s own shop is not paid out.';
        }

        $kyc = $seller->kyc;

        if (! $kyc?->isApproved() || blank($kyc->bank_account_number)) {
            return 'Add and verify your bank account before asking to be paid.';
        }

        if ($kyc->pending_bank_at) {
            return 'Your new bank details are waiting to be confirmed. You can ask to be paid once they are.';
        }

        if (PayoutRequest::where('seller_id', $seller->id)->where('status', PayoutRequest::REQUESTED)->exists()) {
            return 'You already have a payout request waiting.';
        }

        return null;
    }

    public function request(Seller $seller, ?float $amount, ?string $note = null): PayoutRequest
    {
        return DB::transaction(function () use ($seller, $amount, $note) {
            $locked = Seller::whereKey($seller->id)->lockForUpdate()->firstOrFail();

            if ($reason = $this->blocker($locked)) {
                throw ValidationException::withMessages(['amount' => [$reason]]);
            }

            $available = $this->payouts->withdrawable($locked);
            $amount = round($amount ?? $available, 2);
            $minimum = self::minimum();

            if ($amount <= 0 || $amount > $available + 0.004) {
                throw ValidationException::withMessages(['amount' => [$available <= 0
                    ? 'There is nothing to pay out yet. Earnings become payable once orders are delivered and the return window has passed.'
                    : 'You can ask for at most ₹'.number_format($available, 2).' right now.']]);
            }

            if ($amount < $minimum) {
                throw ValidationException::withMessages(['amount' => ['The smallest payout you can ask for is ₹'.number_format($minimum, 2).'.']]);
            }

            return PayoutRequest::create([
                'seller_id' => $locked->id,
                'amount' => $amount,
                'status' => PayoutRequest::REQUESTED,
                'note' => $note ? mb_substr($note, 0, 300) : null,
                'requested_at' => now(),
            ]);
        });
    }

    public function cancel(PayoutRequest $request): PayoutRequest
    {
        if ($request->status !== PayoutRequest::REQUESTED) {
            throw ValidationException::withMessages(['request' => ['This request has already been handled.']]);
        }

        $request->forceFill(['status' => PayoutRequest::CANCELLED, 'decided_at' => now()])->save();

        return $request;
    }

    /** Staff made the transfer: record it against the balance and close the request. */
    public function pay(PayoutRequest $request, string $reference): PayoutRequest
    {
        return DB::transaction(function () use ($request, $reference) {
            $locked = PayoutRequest::whereKey($request->id)->lockForUpdate()->firstOrFail();

            if ($locked->status !== PayoutRequest::REQUESTED) {
                throw ValidationException::withMessages(['request' => ['This request has already been handled.']]);
            }

            $seller = Seller::with('user')->findOrFail($locked->seller_id);
            $entry = $this->payouts->recordPayout($seller, (float) $locked->amount, $reference);

            $locked->forceFill([
                'status' => PayoutRequest::PAID,
                'reference' => $reference,
                'ledger_entry_id' => $entry->id,
                'decided_at' => now(),
            ])->save();

            $this->tell($seller, 'Payout of ₹'.number_format((float) $locked->amount, 2).' sent', 'Bank reference '.$reference.'.');

            return $locked;
        });
    }

    public function reject(PayoutRequest $request, string $reason): PayoutRequest
    {
        return DB::transaction(function () use ($request, $reason) {
            $locked = PayoutRequest::whereKey($request->id)->lockForUpdate()->firstOrFail();

            if ($locked->status !== PayoutRequest::REQUESTED) {
                throw ValidationException::withMessages(['request' => ['This request has already been handled.']]);
            }

            $locked->forceFill([
                'status' => PayoutRequest::REJECTED,
                'decision_note' => mb_substr($reason, 0, 300),
                'decided_at' => now(),
            ])->save();

            $this->tell(Seller::with('user')->findOrFail($locked->seller_id), 'Payout request declined', $reason);

            return $locked;
        });
    }

    private function tell(Seller $seller, string $title, string $body): void
    {
        if ($seller->user) {
            $this->notifications->send($seller->user, 'SELLER_PAYOUT', $title, $body, ['seller_payout' => true]);
        }
    }
}
