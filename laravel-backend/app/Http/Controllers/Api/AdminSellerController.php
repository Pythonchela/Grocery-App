<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Seller;
use App\Models\SellerKycProfile;
use App\Models\User;
use App\Services\SellerPayoutService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Staff-side seller administration: who sells here, on what terms, and what
 * they're owed.
 *
 * Anyone may apply (see SellerOnboardingController), but nobody sells until a
 * reviewer here has seen their documents and approved them. Both routes into an
 * active account — this controller's `update` and the review flow below — check
 * `Seller::mayBeActivated()`, because a single unguarded status write would make
 * the whole KYC process optional.
 */
class AdminSellerController extends Controller
{
    public function index(Request $request)
    {
        $query = Seller::with('user:id,name,email')
            ->withCount('products')
            ->orderByDesc('created_at');

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        $perPage = min((int) $request->get('per_page', 50), 200);
        $page = $query->paginate($perPage)->withQueryString();

        return response()->json([
            'status' => 'success',
            'count' => $page->total(),
            'data' => $page->items(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'per_page' => $page->perPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    public function show($id)
    {
        $seller = Seller::with('user:id,name,email')->withCount('products')->find($id);

        if (! $seller) {
            return response()->json(['status' => 'error', 'message' => 'Seller not found'], 404);
        }

        return response()->json(['status' => 'success', 'data' => $seller]);
    }

    /**
     * How a shop has been doing, for the staff deciding whether to keep, coach or
     * suspend it: volume, how fast it answers, and what comes back.
     */
    public function performance(Request $request, $id)
    {
        $seller = Seller::find($id);

        if (! $seller) {
            return response()->json(['status' => 'error', 'message' => 'Seller not found'], 404);
        }

        $days = in_array((int) $request->query('days'), [7, 30, 90], true) ? (int) $request->query('days') : 30;
        $since = now()->subDays($days);
        $lines = \App\Models\OrderItem::where('seller_id', $seller->id);
        $live = (clone $lines)->where('created_at', '>=', $since)
            ->whereHas('order', fn ($q) => $q->where('status', '!=', 'CANCELLED'));

        $items = (clone $live)->count();
        $returns = \App\Models\ReturnRequest::whereHas('orderItem', fn ($q) => $q->where('seller_id', $seller->id))
            ->where('created_at', '>=', $since)->count();

        return response()->json(['status' => 'success', 'data' => [
            'days' => $days,
            'orders' => (clone $live)->distinct('order_id')->count('order_id'),
            'items' => $items,
            'sales' => round((float) (clone $live)->selectRaw('COALESCE(SUM(price * quantity), 0) as total')->value('total'), 2),
            'earned' => round((float) (clone $live)->sum('seller_earning'), 2),
            'acceptance_rate' => \App\Services\SellerOrderDesk::acceptanceRate($lines, $since),
            'declined' => (clone $lines)->where('rejected_at', '>=', $since)->count(),
            'missed' => (clone $lines)->where('rejected_at', '>=', $since)
                ->where('rejection_reason', \App\Services\SellerOrderDesk::NO_RESPONSE)->count(),
            'late_to_pack_now' => (clone $lines)->where('seller_response', 'ACCEPTED')->where('fulfilment_status', 'PENDING')
                ->where('ready_by', '<', now())
                ->whereHas('order', fn ($q) => $q->whereIn('status', ['CONFIRMED', 'PACKED']))->count(),
            'returns' => $returns,
            'return_rate' => $items > 0 ? round($returns * 100 / $items, 1) : null,
            'products_live' => \App\Models\Product::where('seller_id', $seller->id)->where('status', 'ACTIVE')->count(),
            'products_draft' => \App\Models\Product::where('seller_id', $seller->id)->where('status', 'DRAFT')->count(),
            'products_low_stock' => \App\Models\Product::where('seller_id', $seller->id)->where('status', 'ACTIVE')
                ->whereHas('variants', fn ($q) => $q->where('stock', '<=', 5))->count(),
        ]]);
    }

    /** Onboard a merchant and attach the account that will operate it. */
    public function store(Request $request)
    {
        if (! \App\Support\StoreMode::vendorsEnabled()) {
            return response()->json([
                'status' => 'error',
                'message' => 'This store is set up for a single business, so vendors cannot be added. Change the store type first.',
            ], 403);
        }

        $validated = $request->validate([
            'display_name' => 'required|string|max:120',
            'slug' => 'nullable|string|max:120|unique:sellers,slug',
            'user_id' => 'required|uuid|exists:users,id|unique:sellers,user_id',
            'legal_name' => 'nullable|string|max:200',
            'support_email' => 'nullable|email|max:150',
            'support_phone' => 'nullable|string|max:20',
            'commission_rate' => 'nullable|numeric|min:0|max:100',
            'status' => ['nullable', Rule::in(['PENDING', 'ACTIVE', 'SUSPENDED'])],
        ]);

        $user = User::findOrFail($validated['user_id']);

        // Staff accounts are not merchant accounts. Letting an admin also be a
        // seller means the ownership check in ProductController stops being a
        // real boundary for them.
        if ($user->isAdmin()) {
            return response()->json([
                'status' => 'error',
                'message' => 'A staff account cannot also be a seller.',
            ], 422);
        }

        if ($user->status !== 'ACTIVE') {
            return response()->json(['status' => 'error', 'message' => 'This account is blocked. Unblock it before adding a shop.'], 422);
        }

        $seller = DB::transaction(function () use ($validated, $user) {
            $seller = Seller::create([
                ...$validated,
                'slug' => $validated['slug'] ?? Str::slug($validated['display_name']).'-'.Str::lower(Str::random(4)),
                'commission_rate' => $validated['commission_rate'] ?? 10,
                // Always PENDING, even if the payload asked for ACTIVE. A
                // staff-created seller goes through the same verification as one
                // who applied — otherwise this endpoint is the KYC bypass.
                'status' => 'PENDING',
            ]);

            $seller->kyc()->create([
                'business_type' => 'INDIVIDUAL',
                'legal_name' => $validated['legal_name'] ?? $user->name,
            ]);

            $user->forceFill(['role' => User::ROLE_SELLER])->save();

            return $seller;
        });

        return response()->json(['status' => 'success', 'data' => $seller->fresh(['user', 'kyc'])], 201);
    }

    /** Terms and standing — the fields a seller may not set for themselves. */
    public function update(Request $request, $id)
    {
        $seller = Seller::with('kyc')->find($id);

        if (! $seller) {
            return response()->json(['status' => 'error', 'message' => 'Seller not found'], 404);
        }

        $validated = $request->validate([
            'display_name' => 'sometimes|string|max:120',
            'legal_name' => 'nullable|string|max:200',
            'support_email' => 'nullable|email|max:150',
            'support_phone' => 'nullable|string|max:20',
            'commission_rate' => 'sometimes|numeric|min:0|max:100',
            'status' => ['sometimes', Rule::in(['PENDING', 'ACTIVE', 'SUSPENDED'])],
        ] + Seller::pickupRules() + Seller::shopRules());

        // The activation gate, enforced here as well as in the review flow.
        // Without it this endpoint is a way around KYC entirely — set status to
        // ACTIVE and an unverified account can list products and accrue a
        // payout balance.
        if (($validated['status'] ?? null) === 'ACTIVE' && ! $seller->mayBeActivated()) {
            return response()->json([
                'status' => 'error',
                'message' => 'This seller cannot be activated until their KYC is approved.',
            ], 422);
        }

        // Rate changes apply to future sales only. Past order lines carry the
        // rate they were sold under, so this can never rewrite history.
        $before = $seller->only(['commission_rate', 'status']);
        $seller->update(Seller::cleanShopFields($validated));

        $changed = array_filter(
            ['commission_rate' => [$before['commission_rate'], $seller->fresh()->commission_rate], 'status' => [$before['status'], $seller->fresh()->status]],
            fn ($pair) => (string) $pair[0] !== (string) $pair[1],
        );
        if ($changed !== []) {
            \App\Services\Audit::record($request->user(), 'seller.terms_changed', $seller, "Changed {$seller->display_name}: ".implode(', ', array_keys($changed)), $changed);
        }

        return response()->json(['status' => 'success', 'data' => $seller->fresh()]);
    }

    // ── KYC review ───────────────────────────────────────────────────────

    /** The review queue: applications waiting on a decision, oldest first. */
    public function applications(Request $request)
    {
        $query = SellerKycProfile::with(['seller:id,display_name,slug,status', 'seller.documents'])
            ->where('status', $request->get('status', 'SUBMITTED'))
            ->orderBy('submitted_at');

        $perPage = min((int) $request->get('per_page', 50), 200);
        $page = $query->paginate($perPage)->withQueryString();

        return response()->json([
            'status' => 'success',
            'count' => $page->total(),
            // Masked in the list. A reviewer opens the one they're working on;
            // nobody needs a screen full of other people's PANs.
            'data' => collect($page->items())->map(fn (SellerKycProfile $k) => [
                'id' => $k->id,
                'seller' => $k->seller,
                'submitted_at' => $k->submitted_at,
                'document_count' => $k->seller->documents->count(),
                ...$k->maskedAttributes(),
            ])->values(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'per_page' => $page->perPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    /**
     * The full application, unmasked, for the reviewer who has to check the
     * numbers against the uploaded documents.
     */
    public function reviewDetail(Request $request, $id)
    {
        $seller = Seller::with(['kyc', 'documents', 'user:id,name,email'])->find($id);

        if (! $seller || ! $seller->kyc) {
            return response()->json(['status' => 'error', 'message' => 'Application not found'], 404);
        }

        Log::info('Seller KYC revealed', [
            'seller_id' => $seller->id,
            'reviewer_id' => $request->user()->id,
        ]);

        return response()->json([
            'status' => 'success',
            'data' => [
                'seller' => $seller->only(['id', 'display_name', 'slug', 'status', 'commission_rate']),
                'operator' => $seller->user,
                'kyc' => $seller->kyc->revealFor($request->user()),
                'documents' => $seller->documents,
            ],
        ]);
    }

    /** Approve the application and switch the shop on. */
    public function approveKyc(Request $request, $id)
    {
        $seller = Seller::with('kyc')->find($id);

        if (! $seller || ! $seller->kyc) {
            return response()->json(['status' => 'error', 'message' => 'Application not found'], 404);
        }

        if ($seller->kyc->status !== 'SUBMITTED') {
            return response()->json([
                'status' => 'error',
                'message' => 'Only a submitted application can be approved.',
            ], 422);
        }

        DB::transaction(function () use ($seller, $request) {
            $seller->kyc->forceFill([
                'status' => 'APPROVED',
                'reviewed_at' => now(),
                'reviewed_by' => $request->user()->id,
                'rejection_reason' => null,
            ])->save();

            $seller->update(['status' => 'ACTIVE']);
        });

        \App\Services\Audit::record($request->user(), 'seller.kyc_approved', $seller, "Approved {$seller->display_name}'s application");
        $seller->load('user');
        app(\App\Services\NotificationService::class)->sellerApplicationDecided($seller, true);

        return response()->json([
            'status' => 'success',
            'data' => $seller->fresh('kyc'),
        ]);
    }

    /**
     * Turn it down with a reason.
     *
     * The seller stays PENDING and the KYC goes to REJECTED, which reopens the
     * form — a rejection is a request to correct something, not a dead end.
     */
    public function rejectKyc(Request $request, $id)
    {
        $seller = Seller::with('kyc')->find($id);

        if (! $seller || ! $seller->kyc) {
            return response()->json(['status' => 'error', 'message' => 'Application not found'], 404);
        }

        if ($seller->kyc->status !== 'SUBMITTED') {
            return response()->json([
                'status' => 'error',
                'message' => 'Only a submitted application can be rejected.',
            ], 422);
        }

        $validated = $request->validate([
            'reason' => 'required|string|max:1000',
        ]);

        $seller->kyc->forceFill([
            'status' => 'REJECTED',
            'reviewed_at' => now(),
            'reviewed_by' => $request->user()->id,
            'rejection_reason' => $validated['reason'],
        ])->save();

        \App\Services\Audit::record($request->user(), 'seller.kyc_rejected', $seller, "Turned down {$seller->display_name}'s application", ['reason' => $validated['reason']]);
        $seller->load('user');
        app(\App\Services\NotificationService::class)->sellerApplicationDecided($seller, false, $validated['reason']);

        return response()->json(['status' => 'success', 'data' => $seller->fresh('kyc')]);
    }

    /** Manual ledger correction — goodwill, chargeback, negotiated settlement. */
    public function adjustPayout(Request $request, $id, SellerPayoutService $payouts)
    {
        $seller = Seller::find($id);

        if (! $seller) {
            return response()->json(['status' => 'error', 'message' => 'Seller not found'], 404);
        }

        $validated = $request->validate([
            'amount' => 'required|numeric|not_in:0',
            'note' => 'required|string|max:255',
        ]);

        $entry = $payouts->adjust($seller, (float) $validated['amount'], $validated['note']);
        \App\Services\Audit::record($request->user(), 'payout.adjusted', $seller, "Adjusted {$seller->display_name}'s balance by ₹".number_format((float) $validated['amount'], 2), ['note' => $validated['note']]);

        return response()->json(['status' => 'success', 'data' => $entry]);
    }
}
