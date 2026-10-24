<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Seller;
use App\Models\SellerLedgerEntry;
use App\Services\SellerPayoutService;
use Illuminate\Http\Request;

/**
 * Who is owed what, and how much of it can be paid today.
 *
 * Sellers are paid by bank transfer outside the app. This is where staff see the
 * figures and then record that a transfer was made, so the balance the seller
 * sees goes down by exactly what they were sent.
 */
class AdminPayoutController extends Controller
{
    public function __construct(private readonly SellerPayoutService $payouts) {}

    /**
     * Every vendor with their balance split three ways: what they are owed in
     * all, what is still pending (not delivered, or inside the return window),
     * and what can be paid out now. The owner's own shop is not paid.
     */
    public function index(Request $request)
    {
        $sellers = Seller::with(['user:id,name,email', 'kyc'])
            ->where('is_house', false)
            ->orderByDesc('payout_balance')
            ->get();

        $lastPayouts = SellerLedgerEntry::where('type', 'PAYOUT')
            ->orderByDesc('created_at')
            ->get()
            ->unique('seller_id')
            ->keyBy('seller_id');

        $rows = $sellers->map(function (Seller $s) use ($lastPayouts) {
            $last = $lastPayouts->get($s->id);

            return [
                'id' => $s->id,
                'name' => $s->display_name,
                'status' => $s->status,
                'email' => $s->user?->email,
                'balance' => (float) $s->payout_balance,
                'pending' => $this->payouts->pending($s),
                'withdrawable' => $this->payouts->withdrawable($s),
                'last_payout' => $last ? [
                    'amount' => abs((float) $last->net),
                    'at' => $last->created_at,
                    'note' => $last->note,
                ] : null,
                'bank' => $this->bank($s),
            ];
        })->values();

        return response()->json([
            'status' => 'success',
            'data' => $rows,
            'totals' => [
                'owed' => round($rows->sum('balance'), 2),
                'pending' => round($rows->sum('pending'), 2),
                'withdrawable' => round($rows->sum('withdrawable'), 2),
            ],
        ]);
    }

    /** Record a transfer: debits the balance by exactly [amount], never more than is payable. */
    public function store(Request $request, string $id)
    {
        $seller = Seller::where('is_house', false)->find($id);

        if (! $seller) {
            return response()->json(['status' => 'error', 'message' => 'Seller not found'], 404);
        }

        $validated = $request->validate([
            'amount' => 'required|numeric|gt:0|max:10000000',
            // The bank's reference for the transfer (UTR), so the payout can be traced.
            'reference' => 'required|string|max:120',
        ]);

        $entry = $this->payouts->recordPayout($seller, (float) $validated['amount'], trim($validated['reference']));
        \App\Services\Audit::record($request->user(), 'payout.recorded', $seller, 'Recorded a payout of ₹'.number_format((float) $validated['amount'], 2)." to {$seller->display_name}", ['reference' => trim($validated['reference'])]);

        return response()->json(['status' => 'success', 'data' => $entry, 'seller' => [
            'balance' => (float) $seller->fresh()->payout_balance,
            'withdrawable' => $this->payouts->withdrawable($seller->fresh()),
        ]], 201);
    }

    /** Enough to find the account, without printing the number in a list. */
    private function bank(Seller $s): ?array
    {
        $kyc = $s->kyc;

        if (! $kyc || ! $kyc->bank_account_number) {
            return null;
        }

        $number = (string) $kyc->bank_account_number;

        return [
            'holder' => $kyc->bank_account_holder,
            'bank' => $kyc->bank_name,
            'ifsc' => $kyc->bank_ifsc,
            'account_last4' => substr($number, -4),
        ];
    }
}
