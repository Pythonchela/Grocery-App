<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PayoutRequest;
use App\Models\Seller;
use App\Services\PayoutRequestService;
use App\Services\SellerPayoutService;
use App\Services\SellerStatementService;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * A seller's own money: what they can ask for, what they asked for, their bank
 * account, and their monthly statements. Every query is scoped to the caller's
 * own seller row.
 */
class SellerMoneyController extends Controller
{
    private const IFSC = '/^[A-Z]{4}0[A-Z0-9]{6}$/';

    public function __construct(
        private readonly PayoutRequestService $requests,
        private readonly SellerPayoutService $payouts,
        private readonly SellerStatementService $statements,
    ) {}

    private function seller(Request $request): Seller
    {
        return $request->user()->seller;
    }

    /** Everything the Earnings screen needs about getting paid, in one call. */
    public function show(Request $request)
    {
        $seller = $this->seller($request)->load('kyc');
        $kyc = $seller->kyc;

        return response()->json(['status' => 'success', 'data' => [
            'balance' => (float) $seller->payout_balance,
            'pending' => $this->payouts->pending($seller),
            'withdrawable' => $this->payouts->withdrawable($seller),
            'minimum_payout' => PayoutRequestService::minimum(),
            'blocker' => $this->requests->blocker($seller),
            'bank' => $kyc && $kyc->bank_account_number ? self::bank($kyc->bank_account_holder, $kyc->bank_name, $kyc->bank_ifsc, $kyc->bank_account_number) : null,
            'pending_bank' => $kyc?->pending_bank_at ? self::bank(
                $kyc->pending_bank['bank_account_holder'] ?? null,
                $kyc->pending_bank['bank_name'] ?? null,
                $kyc->pending_bank['bank_ifsc'] ?? null,
                $kyc->pending_bank['bank_account_number'] ?? null,
            ) + ['requested_at' => $kyc->pending_bank_at->toIso8601String()] : null,
            'requests' => PayoutRequest::where('seller_id', $seller->id)->orderByDesc('created_at')->limit(20)->get(),
        ]]);
    }

    public function requestPayout(Request $request)
    {
        $validated = $request->validate([
            'amount' => 'nullable|numeric|gt:0|max:10000000',
            'note' => 'nullable|string|max:300',
        ]);

        $payout = $this->requests->request($this->seller($request), isset($validated['amount']) ? (float) $validated['amount'] : null, $validated['note'] ?? null);

        return response()->json(['status' => 'success', 'data' => $payout], 201);
    }

    public function cancelPayout(Request $request, string $id)
    {
        $payout = PayoutRequest::where('seller_id', $this->seller($request)->id)->find($id);

        if (! $payout) {
            return response()->json(['status' => 'error', 'message' => 'Request not found'], 404);
        }

        return response()->json(['status' => 'success', 'data' => $this->requests->cancel($payout)]);
    }

    /**
     * Ask to change the bank account payouts go to. Nothing changes until staff
     * confirm it: a stolen login must not be able to redirect the money.
     */
    public function changeBank(Request $request)
    {
        $seller = $this->seller($request)->load('kyc');

        if (! $seller->kyc?->isApproved()) {
            throw ValidationException::withMessages(['bank' => ['Finish your verification first; bank details are part of the application.']]);
        }

        $request->merge(['bank_ifsc' => strtoupper(trim((string) $request->input('bank_ifsc')))]);

        $validated = $request->validate([
            'bank_account_holder' => 'required|string|max:150',
            'bank_account_number' => ['required', 'string', 'regex:/^[0-9]{9,18}$/'],
            'bank_ifsc' => ['required', 'string', 'regex:'.self::IFSC],
            'bank_name' => 'nullable|string|max:120',
        ], [
            'bank_account_number.regex' => 'An account number is 9 to 18 digits.',
            'bank_ifsc.regex' => 'That does not look like an IFSC code (for example HDFC0001234).',
        ]);

        $seller->kyc->forceFill(['pending_bank' => $validated, 'pending_bank_at' => now()])->save();

        return response()->json(['status' => 'success', 'message' => 'Sent for confirmation. Payouts continue to the current account until it is confirmed.'], 202);
    }

    public function withdrawBankChange(Request $request)
    {
        $kyc = $this->seller($request)->kyc;
        $kyc?->forceFill(['pending_bank' => null, 'pending_bank_at' => null])->save();

        return response()->json(['status' => 'success']);
    }

    public function statementMonths(Request $request)
    {
        return response()->json(['status' => 'success', 'data' => $this->statements->months($this->seller($request))]);
    }

    public function statement(Request $request, string $month)
    {
        return response()->json(['status' => 'success', 'data' => $this->statements->forMonth($this->seller($request), $month)]);
    }

    public function statementCsv(Request $request, string $month)
    {
        $statement = $this->statements->forMonth($this->seller($request), $month);

        return response($this->statements->csv($statement), 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="statement-'.$month.'.csv"',
        ]);
    }

    /** Enough to recognise an account, never the number itself. */
    public static function bank(?string $holder, ?string $bank, ?string $ifsc, ?string $number): array
    {
        return [
            'holder' => $holder,
            'bank' => $bank,
            'ifsc' => $ifsc,
            'account_last4' => $number ? substr($number, -4) : null,
        ];
    }
}
