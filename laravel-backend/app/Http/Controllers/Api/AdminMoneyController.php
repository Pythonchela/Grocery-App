<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PayoutRequest;
use App\Models\Seller;
use App\Models\SellerKycProfile;
use App\Services\PayoutRequestService;
use App\Services\SellerPayoutService;
use App\Services\SellerStatementService;
use Illuminate\Http\Request;

/**
 * Staff side of seller money: payout requests to pay or decline, bank-account
 * changes to confirm, and any seller's statement.
 */
class AdminMoneyController extends Controller
{
    public function __construct(
        private readonly PayoutRequestService $requests,
        private readonly SellerPayoutService $payouts,
        private readonly SellerStatementService $statements,
    ) {}

    public function payoutRequests(Request $request)
    {
        $query = PayoutRequest::with(['seller.kyc', 'seller.user:id,name,email'])->orderByDesc('created_at');

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        $rows = $query->limit(200)->get()->map(function (PayoutRequest $r) {
            $kyc = $r->seller?->kyc;

            return $r->toArray() + [
                'seller_name' => $r->seller?->display_name,
                'seller_email' => $r->seller?->user?->email,
                'withdrawable' => $r->seller ? $this->payouts->withdrawable($r->seller) : 0,
                'bank' => $kyc && $kyc->bank_account_number
                    ? SellerMoneyController::bank($kyc->bank_account_holder, $kyc->bank_name, $kyc->bank_ifsc, $kyc->bank_account_number)
                    : null,
                'bank_change_pending' => (bool) $kyc?->pending_bank_at,
            ];
        });

        return response()->json(['status' => 'success', 'data' => $rows]);
    }

    public function pay(Request $request, string $id)
    {
        $payout = PayoutRequest::find($id);

        if (! $payout) {
            return response()->json(['status' => 'error', 'message' => 'Request not found'], 404);
        }

        $validated = $request->validate(['reference' => 'required|string|max:120']);

        $paid = $this->requests->pay($payout, trim($validated['reference']));
        \App\Services\Audit::record($request->user(), 'payout.paid', $payout, 'Paid a payout request of ₹'.number_format((float) $payout->amount, 2), ['seller_id' => $payout->seller_id, 'reference' => trim($validated['reference'])]);

        return response()->json(['status' => 'success', 'data' => $paid]);
    }

    public function reject(Request $request, string $id)
    {
        $payout = PayoutRequest::find($id);

        if (! $payout) {
            return response()->json(['status' => 'error', 'message' => 'Request not found'], 404);
        }

        $validated = $request->validate(['reason' => 'required|string|max:300']);

        $rejected = $this->requests->reject($payout, trim($validated['reason']));
        \App\Services\Audit::record($request->user(), 'payout.declined', $payout, 'Declined a payout request of ₹'.number_format((float) $payout->amount, 2), ['seller_id' => $payout->seller_id, 'reason' => trim($validated['reason'])]);

        return response()->json(['status' => 'success', 'data' => $rejected]);
    }

    public function bankChanges()
    {
        $rows = SellerKycProfile::with('seller.user:id,name,email')
            ->whereNotNull('pending_bank_at')
            ->orderBy('pending_bank_at')
            ->get()
            ->map(fn (SellerKycProfile $k) => [
                'seller_id' => $k->seller_id,
                'seller_name' => $k->seller?->display_name,
                'seller_email' => $k->seller?->user?->email,
                'requested_at' => $k->pending_bank_at->toIso8601String(),
                'current' => $k->bank_account_number
                    ? SellerMoneyController::bank($k->bank_account_holder, $k->bank_name, $k->bank_ifsc, $k->bank_account_number)
                    : null,
                'proposed' => SellerMoneyController::bank(
                    $k->pending_bank['bank_account_holder'] ?? null,
                    $k->pending_bank['bank_name'] ?? null,
                    $k->pending_bank['bank_ifsc'] ?? null,
                    $k->pending_bank['bank_account_number'] ?? null,
                ),
            ]);

        return response()->json(['status' => 'success', 'data' => $rows]);
    }

    public function approveBank(Request $request, string $sellerId)
    {
        $kyc = SellerKycProfile::where('seller_id', $sellerId)->whereNotNull('pending_bank_at')->first();

        if (! $kyc) {
            return response()->json(['status' => 'error', 'message' => 'No bank change is waiting for this seller.'], 404);
        }

        $new = $kyc->pending_bank;
        $kyc->forceFill([
            'bank_account_holder' => $new['bank_account_holder'] ?? $kyc->bank_account_holder,
            'bank_account_number' => $new['bank_account_number'] ?? $kyc->bank_account_number,
            'bank_ifsc' => $new['bank_ifsc'] ?? $kyc->bank_ifsc,
            'bank_name' => $new['bank_name'] ?? $kyc->bank_name,
            'pending_bank' => null,
            'pending_bank_at' => null,
        ])->save();

        $this->tellSeller($sellerId, 'Bank details confirmed', 'Payouts now go to the new account.');
        \App\Services\Audit::record($request->user(), 'bank.confirmed', ['Seller', $sellerId], 'Confirmed a new payout bank account', ['seller_id' => $sellerId, 'account_last4' => substr((string) ($new['bank_account_number'] ?? ''), -4)]);

        return response()->json(['status' => 'success']);
    }

    public function rejectBank(Request $request, string $sellerId)
    {
        $validated = $request->validate(['reason' => 'required|string|max:300']);
        $kyc = SellerKycProfile::where('seller_id', $sellerId)->whereNotNull('pending_bank_at')->first();

        if (! $kyc) {
            return response()->json(['status' => 'error', 'message' => 'No bank change is waiting for this seller.'], 404);
        }

        $kyc->forceFill(['pending_bank' => null, 'pending_bank_at' => null])->save();
        $this->tellSeller($sellerId, 'Bank change not confirmed', $validated['reason']);
        \App\Services\Audit::record($request->user(), 'bank.declined', ['Seller', $sellerId], 'Declined a bank account change', ['seller_id' => $sellerId, 'reason' => $validated['reason']]);

        return response()->json(['status' => 'success']);
    }

    public function statement(string $sellerId, string $month)
    {
        $seller = Seller::where('is_house', false)->find($sellerId);

        if (! $seller) {
            return response()->json(['status' => 'error', 'message' => 'Seller not found'], 404);
        }

        return response()->json(['status' => 'success', 'data' => $this->statements->forMonth($seller, $month)]);
    }

    public function statementCsv(string $sellerId, string $month)
    {
        $seller = Seller::where('is_house', false)->find($sellerId);

        if (! $seller) {
            return response()->json(['status' => 'error', 'message' => 'Seller not found'], 404);
        }

        return response($this->statements->csv($this->statements->forMonth($seller, $month)), 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="statement-'.$seller->slug.'-'.$month.'.csv"',
        ]);
    }

    private function tellSeller(string $sellerId, string $title, string $body): void
    {
        $user = Seller::with('user')->find($sellerId)?->user;

        if ($user) {
            app(\App\Services\NotificationService::class)->send($user, 'SELLER_PAYOUT', $title, $body, ['seller_payout' => true]);
        }
    }
}
