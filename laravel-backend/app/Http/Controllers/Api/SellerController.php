<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\OrderItem;
use App\Models\Product;
use App\Models\Seller;
use App\Models\SellerLedgerEntry;
use App\Models\Review;
use App\Models\ProductQuestion;
use App\Models\ReturnRequest;
use App\Services\Delivery\ShipmentBooker;
use App\Services\FulfilmentService;
use App\Services\SellerOrderDesk;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * What a merchant can see of their own shop.
 *
 * Every query here is scoped to the caller's seller id without exception. That
 * scoping is the entire security model of a marketplace: the difference between
 * a seller dashboard and a data breach is one missing where-clause.
 */
class SellerController extends Controller
{
    private const DEFAULT_PER_PAGE = 50;

    private const MAX_PER_PAGE = 200;

    private function seller(Request $request): Seller
    {
        return $request->user()->seller;
    }

    /** The merchant's own profile and what they're owed. */
    public function me(Request $request)
    {
        $seller = $this->seller($request);

        return response()->json([
            'status' => 'success',
            'data' => [
                'id' => $seller->id,
                'display_name' => $seller->display_name,
                'slug' => $seller->slug,
                'legal_name' => $seller->legal_name,
                'support_email' => $seller->support_email,
                'support_phone' => $seller->support_phone,
                'commission_rate' => (float) $seller->commission_rate,
                'status' => $seller->status,
                'payout_balance' => (float) $seller->payout_balance,
                'product_count' => $seller->products()->count(),
                // Tells the app whether "ship" books the courier itself or asks
                // the seller to type the courier and tracking number.
                'auto_book' => ShipmentBooker::automatic(),
            ] + $seller->pickupFields() + $seller->shopFields(),
        ]);
    }

    /** Contact details only. Commission and status are not theirs to set. */
    public function update(Request $request)
    {
        $validated = $request->validate([
            'display_name' => 'sometimes|string|max:120',
            'legal_name' => 'nullable|string|max:200',
            'support_email' => 'nullable|email|max:150',
            'support_phone' => 'nullable|string|max:20',
            // "Back in 90 minutes": sets a timed pause. 0 reopens the shop now.
            'pause_minutes' => 'nullable|integer|min:0|max:10080',
        ] + Seller::pickupRules() + Seller::shopRules());

        $seller = $this->seller($request);

        if (array_key_exists('pause_minutes', $validated)) {
            $minutes = (int) $validated['pause_minutes'];
            $validated['paused_until'] = $minutes > 0 ? now()->addMinutes($minutes) : null;
            if ($minutes === 0) {
                $validated['accepting_orders'] = true;
            }
        }
        unset($validated['pause_minutes']);

        $seller->update(Seller::cleanShopFields($validated));

        return response()->json(['status' => 'success', 'data' => $seller->fresh()]);
    }

    /** Their catalog — every status, since drafts are theirs to manage. */
    public function products(Request $request)
    {
        $query = Product::where('seller_id', $this->seller($request)->id)
            ->with(['category', 'variants'])
            ->withCardAggregates()
            ->orderByDesc('created_at');

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        $search = trim((string) $request->query('search', ''));
        if ($search !== '') {
            $term = '%'.mb_substr($search, 0, 100).'%';
            $query->where(fn ($q) => $q->where('title', 'like', $term)
                ->orWhereHas('variants', fn ($v) => $v->where('sku', 'like', $term)));
        }

        return $this->paginated($query, $request);
    }

    /** Daily operating numbers, scoped to this shop's order lines. */
    public function overview(Request $request)
    {
        $seller = $this->seller($request);
        $lines = OrderItem::where('seller_id', $seller->id);
        $since = now()->subDays(30);

        return response()->json(['status' => 'success', 'data' => [
            'to_pack' => (clone $lines)->where('fulfilment_status', 'PENDING')->where('seller_response', 'ACCEPTED')
                ->whereHas('order', fn ($q) => $q->whereIn('status', ['CONFIRMED', 'PACKED']))->count(),
            'new_orders' => (clone $lines)->where('seller_response', 'PENDING')
                ->whereHas('order', fn ($q) => $q->whereIn('status', ['CONFIRMED', 'PACKED']))->count(),
            'late_to_pack' => (clone $lines)->where('seller_response', 'ACCEPTED')->where('fulfilment_status', 'PENDING')
                ->where('ready_by', '<', now())
                ->whereHas('order', fn ($q) => $q->whereIn('status', ['CONFIRMED', 'PACKED']))->count(),
            'acceptance_rate_30d' => $this->acceptanceRate($lines, $since),
            'turned_down_30d' => (clone $lines)->where('rejected_at', '>=', $since)->count(),
            'missed_30d' => (clone $lines)->where('rejected_at', '>=', $since)->where('rejection_reason', SellerOrderDesk::NO_RESPONSE)->count(),
            'packed' => (clone $lines)->where('fulfilment_status', 'PACKED')
                ->whereHas('order', fn ($q) => $q->whereIn('status', ['CONFIRMED', 'PACKED']))->count(),
            'sold_30d' => (clone $lines)->where('created_at', '>=', $since)
                ->whereHas('order', fn ($q) => $q->where('status', '!=', 'CANCELLED'))->sum('seller_earning'),
            'orders_30d' => (clone $lines)->where('created_at', '>=', $since)
                ->whereHas('order', fn ($q) => $q->where('status', '!=', 'CANCELLED'))
                ->distinct('order_id')->count('order_id'),
            'low_stock' => Product::where('seller_id', $seller->id)->where('status', 'ACTIVE')
                ->whereHas('variants', fn ($q) => $q->where('stock', '<=', 5))->count(),
            'returns_open' => ReturnRequest::whereHas('orderItem', fn ($q) => $q->where('seller_id', $seller->id))
                ->whereIn('status', ['REQUESTED', 'PICKUP_SCHEDULED', 'PICKED_UP'])->count(),
            'questions_open' => ProductQuestion::whereHas('product', fn ($q) => $q->where('seller_id', $seller->id))
                ->where('status', 'APPROVED')->whereDoesntHave('answers', fn ($q) => $q->where('is_official', true))->count(),
        ]]);
    }

    public function reviews(Request $request)
    {
        $query = Review::whereHas('product', fn ($q) => $q->where('seller_id', $this->seller($request)->id))
            ->with(['product:id,title', 'user:id,name'])->orderByDesc('created_at');

        return $this->paginated($query, $request);
    }

    public function replyToReview(Request $request, $id)
    {
        $validated = $request->validate(['reply' => 'required|string|max:2000']);
        $review = Review::whereHas('product', fn ($q) => $q->where('seller_id', $this->seller($request)->id))
            ->where('status', 'APPROVED')->findOrFail($id);
        $review->update(['admin_reply' => $validated['reply'], 'admin_replied_at' => now()]);

        return response()->json(['status' => 'success', 'data' => $review->fresh()]);
    }

    public function questions(Request $request)
    {
        $query = ProductQuestion::whereHas('product', fn ($q) => $q->where('seller_id', $this->seller($request)->id))
            ->where('status', 'APPROVED')->with(['product:id,title', 'user:id,name', 'answers.user:id,name'])
            ->orderByDesc('created_at');

        return $this->paginated($query, $request);
    }

    /** Sellers need visibility; staff retain approval and refund authority. */
    public function returns(Request $request)
    {
        $query = ReturnRequest::whereHas('orderItem', fn ($q) => $q->where('seller_id', $this->seller($request)->id))
            ->with(['orderItem.product:id,title', 'order:id,order_number', 'user:id,name'])
            ->orderByDesc('created_at');

        return $this->paginated($query, $request);
    }

    /** Seller records what they know; only staff decide pickup and refund. */
    public function reviewReturn(Request $request, string $id)
    {
        $row = ReturnRequest::whereHas('orderItem', fn ($q) => $q->where('seller_id', $this->seller($request)->id))
            ->findOrFail($id);
        if (! in_array($row->status, ['REQUESTED', 'PICKUP_SCHEDULED', 'PICKED_UP'], true)) {
            throw ValidationException::withMessages(['status' => ['This return is already closed.']]);
        }
        $data = $request->validate([
            'seller_recommendation' => 'required|in:ACCEPT,REJECT,NEEDS_REVIEW',
            'seller_note' => 'required|string|min:3|max:2000',
        ]);
        $row->update($data + ['seller_reviewed_at' => now()]);

        return response()->json(['status' => 'success', 'data' => $row->fresh()]);
    }

    /**
     * The lines they sold, not the orders those lines sat in.
     *
     * A seller sees their own items and where to ship them — never the rest of
     * a shared basket, and never another seller's lines on the same order.
     */
    public function orderItems(Request $request)
    {
        $query = OrderItem::where('seller_id', $this->seller($request)->id)
            ->with(['product:id,title,images', 'variant:id,color,size', 'order:id,order_number,status,payment_status,payment_method,shipping_address,created_at'])
            ->orderByDesc('created_at');

        if ($request->filled('status')) {
            $query->whereHas('order', fn ($q) => $q->where('status', $request->status));
        }

        // Where a line is in the seller's own workflow. Combines the line's
        // fulfilment state with its order's status, because a line still
        // "pending" on a cancelled order is not something to pack.
        if ($request->filled('stage')) {
            $open = ['CONFIRMED', 'PACKED'];

            match ($request->stage) {
                // Waiting for the shop to say yes or no; the oldest first, since that clock is running.
                'new' => $query->where('seller_response', 'PENDING')
                    ->reorder('accept_by')
                    ->whereHas('order', fn ($q) => $q->whereIn('status', $open)),
                'to_pack' => $query->where('fulfilment_status', 'PENDING')->where('seller_response', 'ACCEPTED')
                    ->whereHas('order', fn ($q) => $q->whereIn('status', $open)),
                'packed' => $query->where('fulfilment_status', 'PACKED')
                    ->whereHas('order', fn ($q) => $q->whereIn('status', $open)),
                'shipped' => $query->where('fulfilment_status', 'SHIPPED')
                    ->whereHas('order', fn ($q) => $q->whereIn('status', ['CONFIRMED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY'])),
                'delivered' => $query->whereHas('order', fn ($q) => $q->where('status', 'DELIVERED')),
                'cancelled' => $query->where(fn ($q) => $q->where('fulfilment_status', 'CANCELLED')
                    ->orWhereHas('order', fn ($o) => $o->where('status', 'CANCELLED'))),
                default => null,
            };
        }

        return $this->paginated($query, $request);
    }

    /** Take an order on, promising it will be ready in so many minutes. */
    public function acceptItem(Request $request, $id, SellerOrderDesk $desk)
    {
        $item = $this->ownItem($request, $id);

        if (! $item) {
            return response()->json(['status' => 'error', 'message' => 'Order item not found'], 404);
        }

        $validated = $request->validate(['prep_minutes' => 'nullable|integer|min:1|max:1440']);

        return $this->fulfilmentResponse($desk->accept($item, $validated['prep_minutes'] ?? null));
    }

    /** Turn an order down (or cancel it before it is shipped), with a reason the customer can be told. */
    public function rejectItem(Request $request, $id, SellerOrderDesk $desk)
    {
        $item = $this->ownItem($request, $id);

        if (! $item) {
            return response()->json(['status' => 'error', 'message' => 'Order item not found'], 404);
        }

        $validated = $request->validate([
            'reason' => 'required|in:'.implode(',', SellerOrderDesk::REASONS),
            'note' => 'nullable|string|max:300',
        ]);

        return $this->fulfilmentResponse($desk->decline($item, $validated['reason'], $validated['note'] ?? null, 'SELLER'));
    }

    /**
     * Switch one item on or off for the day without touching its stock. Off with
     * an `until` time, it comes back on by itself.
     */
    public function setAvailability(Request $request, $id)
    {
        $product = Product::where('seller_id', $this->seller($request)->id)->find($id);

        if (! $product) {
            return response()->json(['status' => 'error', 'message' => 'Product not found'], 404);
        }

        if (! in_array($product->status, ['ACTIVE', 'OUT_OF_STOCK'], true)) {
            throw ValidationException::withMessages(['available' => ['Only a live item can be switched on or off.']]);
        }

        $validated = $request->validate([
            'available' => 'required|boolean',
            'until' => 'nullable|date|after:now',
        ]);

        $product->forceFill($validated['available']
            ? ['status' => 'ACTIVE', 'available_again_at' => null]
            : ['status' => 'OUT_OF_STOCK', 'available_again_at' => $validated['until'] ?? null]
        )->save();

        return response()->json(['status' => 'success', 'data' => $product->fresh()]);
    }

    /**
     * Mark one of their lines packed.
     *
     * Scoped to the caller's own lines before anything else: another seller's
     * line answers 404, exactly like one that doesn't exist, so ids can't be
     * probed.
     */
    public function packItem(Request $request, $id, FulfilmentService $fulfilment)
    {
        $item = $this->ownItem($request, $id);

        if (! $item) {
            return response()->json(['status' => 'error', 'message' => 'Order item not found'], 404);
        }

        return $this->fulfilmentResponse($fulfilment->pack($item));
    }

    /**
     * Hand one of their lines to a courier.
     *
     * With a courier and tracking number given, those are recorded as typed (the
     * seller booked it themselves). With neither, the courier is booked for them,
     * unless automatic booking is switched off, in which case both are required.
     */
    public function shipItem(Request $request, $id, FulfilmentService $fulfilment, ShipmentBooker $booker)
    {
        $item = $this->ownItem($request, $id);

        if (! $item) {
            return response()->json(['status' => 'error', 'message' => 'Order item not found'], 404);
        }

        $validated = $request->validate([
            'courier' => 'nullable|string|max:80',
            'tracking_no' => 'nullable|string|max:80',
        ]);

        $courier = trim((string) ($validated['courier'] ?? ''));
        $tracking = trim((string) ($validated['tracking_no'] ?? ''));

        if ($courier === '' && $tracking === '') {
            if (! ShipmentBooker::automatic()) {
                throw ValidationException::withMessages([
                    'courier' => 'Choose or enter the courier.',
                    'tracking_no' => 'Enter the tracking number.',
                ]);
            }

            try {
                $booking = $booker->book($item->order()->firstOrFail());
            } catch (\Throwable $e) {
                report($e);

                // Say what went wrong and what to do instead; the seller is
                // standing next to a parcel and needs a way forward.
                throw ValidationException::withMessages([
                    'fulfilment' => 'The courier could not be booked automatically ('.$this->bookingReason($e).'). You can enter the courier and tracking number yourself.',
                ]);
            }

            $courier = (string) ($booking['courier'] ?? '');
            $tracking = (string) ($booking['tracking_no'] ?? '');
        } elseif ($courier === '' || $tracking === '') {
            throw ValidationException::withMessages([
                $courier === '' ? 'courier' : 'tracking_no' => $courier === '' ? 'Choose or enter the courier.' : 'Enter the tracking number.',
            ]);
        }

        return $this->fulfilmentResponse($fulfilment->ship($item, $courier, $tracking));
    }

    /** A short, plain reason for a failed booking. */
    private function bookingReason(\Throwable $e): string
    {
        return $e instanceof \RuntimeException
            ? rtrim($e->getMessage(), '. ')
            : 'the courier service did not respond';
    }

    private function ownItem(Request $request, $id): ?OrderItem
    {
        return OrderItem::where('seller_id', $this->seller($request)->id)->find($id);
    }

    private function fulfilmentResponse(OrderItem $item)
    {
        $item->load(['product:id,title,images', 'variant:id,color,size', 'order:id,order_number,status,payment_status,shipping_address,created_at']);

        return response()->json(['status' => 'success', 'data' => $item]);
    }

    /** The payout ledger, newest first. */
    public function ledger(Request $request)
    {
        $seller = $this->seller($request);

        $query = SellerLedgerEntry::where('seller_id', $seller->id)->orderByDesc('created_at');

        $response = $this->paginated($query, $request);

        $payouts = app(\App\Services\SellerPayoutService::class);

        return $response->setData(array_merge(
            (array) $response->getData(true),
            [
                'balance' => (float) $seller->payout_balance,
                // Part of the balance is not payable yet: the orders are not
                // delivered, or are still inside the return window.
                'pending' => $payouts->pending($seller),
                'withdrawable' => $payouts->withdrawable($seller),
            ],
        ));
    }

    /** Share of the lines they were asked to answer, in the window, that they took on. */
    private function acceptanceRate($lines, $since): ?float
    {
        return SellerOrderDesk::acceptanceRate($lines, $since);
    }

    private function paginated($query, Request $request)
    {
        $perPage = min((int) $request->get('per_page', self::DEFAULT_PER_PAGE), self::MAX_PER_PAGE);
        $page = $query->paginate(max(1, $perPage))->withQueryString();

        return response()->json([
            'status' => 'success',
            'count' => $page->total(),
            'data' => $page->items(),
            // So a countdown on the client does not depend on the device clock.
            'server_time' => now()->toIso8601String(),
            'meta' => [
                'current_page' => $page->currentPage(),
                'per_page' => $page->perPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
            ],
        ]);
    }
}
