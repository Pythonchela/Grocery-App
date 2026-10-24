<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Coupon;
use App\Models\CouponRedemption;
use App\Models\Order;
use App\Models\PaymentIntent;
use App\Models\ProductVariant;
use App\Models\Setting;
use App\Services\Contracts\LogisticsProvider;
use App\Services\Delivery\ServiceLevel;
use App\Services\LoyaltyService;
use App\Services\NotificationService;
use App\Services\Payments\PaymentService;
use App\Services\Options\ProductOptions;
use App\Services\Pricing\CartPricingService;
use App\Services\ReferralService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class OrderController extends Controller
{
    /**
     * Transactional, stock-checked, price-verified checkout.
     *
     * Everything with a currency sign on it comes from CartPricingService, and
     * every prepaid order has to present a payment intent the server itself
     * issued for this exact cart. The request supplies what to buy and proof it
     * was paid for; it no longer supplies what it costs or whether it was paid.
     */
    public function store(
        Request $request,
        NotificationService $notifications,
        CartPricingService $pricing,
        PaymentService $payments,
    ) {
        $validated = $request->validate([
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|uuid|exists:products,id',
            'items.*.variant_id' => 'nullable|uuid|exists:product_variants,id',
            'items.*.quantity' => 'required|integer|min:1|max:'.CartPricingService::MAX_QUANTITY_PER_LINE,
            // What the shopper picked: {group_key: [choice ids] | number}.
            'items.*.options' => 'nullable|array',
            'shipping_address' => 'required|array',
            'shipping_address.name' => 'required|string|max:120',
            'shipping_address.phone' => 'required|string|max:20',
            'shipping_address.line1' => 'required|string|max:255',
            'shipping_address.line2' => 'nullable|string|max:255',
            'shipping_address.city' => 'required|string|max:80',
            'shipping_address.state' => 'required|string|max:80',
            'shipping_address.pincode' => 'required|string|regex:/^[0-9]{6}$/',
            // "Leave at the door", "Call on arrival" - read by whoever delivers.
            'shipping_address.instructions' => 'nullable|string|max:200',
            'payment_method' => 'required|in:UPI,CARD,NETBANKING,COD',
            'coupon_code' => 'nullable|string',
            'use_wallet' => 'nullable|boolean',
            'redeem_points' => 'nullable|integer|min:0',
            'service_level' => 'nullable|in:'.implode(',', ServiceLevel::ALL),
            // Prepaid only. Required below rather than here, so COD isn't asked
            // for payment evidence it can't have.
            'payment_intent_id' => 'nullable|uuid',
            // What the gateway's client SDK returned. Its shape is the
            // gateway's business, so it travels as an opaque object; the two
            // flat fields are the older spelling of the same thing.
            'payment' => 'nullable|array',
            'payment_id' => 'nullable|string|max:120',
            'signature' => 'nullable|string|max:512',
        ]);

        $user = $request->user();
        $loyalty = app(LoyaltyService::class);
        $isCod = $validated['payment_method'] === 'COD';
        $pincode = $validated['shipping_address']['pincode'];

        if ($isCod) {
            $blocked = (array) Setting::get('cod.blocked_pincodes', []);
            if (in_array($pincode, $blocked, true)) {
                throw ValidationException::withMessages([
                    'payment_method' => ['Cash on Delivery is not available at this pincode.'],
                ]);
            }
        } elseif (empty($validated['payment_intent_id'])) {
            throw ValidationException::withMessages([
                'payment_intent_id' => ['Start the payment before placing the order.'],
            ]);
        }

        try {
            $order = DB::transaction(function () use ($validated, $user, $loyalty, $pricing, $payments, $isCod, $pincode) {
                // Prices, stock locks, coupon scoping and the delivery quote all
                // happen here, against the database.
                $cart = $pricing->price($validated['items'], $user, [
                    'coupon_code' => $validated['coupon_code'] ?? null,
                    'pincode' => $pincode,
                    'payment_method' => $validated['payment_method'],
                    'service_level' => $validated['service_level'] ?? ServiceLevel::STANDARD,
                    'redeem_points' => $validated['redeem_points'] ?? null,
                    'use_wallet' => $validated['use_wallet'] ?? false,
                    'lock' => true,
                ]);

                $transactionId = null;
                $intent = null;
                $verified = null;

                if (! $isCod) {
                    [$intent, $transactionId, $verified] = $this->confirmPayment(
                        $validated,
                        $user,
                        $cart,
                        $pincode,
                        $payments,
                    );
                }

                foreach ($cart->lines as $line) {
                    $line->variant->decrement('stock', $line->quantity);
                }

                // Options with their own stock (the last two portions, say).
                ProductOptions::reserveStock(array_map(fn ($line) => [
                    'product' => $line->product,
                    'options' => $line->options,
                    'quantity' => $line->quantity,
                ], $cart->lines));

                $pointsEarned = $loyalty->pointsFor($cart->total);

                $order = Order::create([
                    'order_number' => 'ORD-'.strtoupper(Str::random(8)),
                    'user_id' => $user->id,
                    'status' => 'CONFIRMED',
                    'payment_status' => $isCod ? 'PENDING' : 'PAID',
                    'payment_method' => $validated['payment_method'],
                    'transaction_id' => $transactionId,
                    'subtotal' => $cart->subtotal,
                    'discount' => $cart->totalDiscount(),
                    'shipping_charge' => $cart->shipping,
                    'total_amount' => $cart->total,
                    'wallet_applied' => $cart->walletApplicable,
                    'coupon_id' => $cart->coupon?->id,
                    'coupon_code' => $cart->coupon?->code,
                    'shipping_address' => $validated['shipping_address'],
                    'points_redeemed' => $cart->pointsRedeemable,
                    'points_earned' => $pointsEarned,
                    // What we promised and who we intend to hand it to. Stored
                    // so a late delivery can be attributed to a carrier rather
                    // than argued about.
                    'carrier' => $cart->carrier,
                    'service_level' => $cart->serviceLevel,
                    'delivery_fee_paise' => (int) round($cart->shipping * 100),
                    'promised_by' => now()->addMinutes($cart->etaMinutes),
                ]);

                // Each line carries its share of the discount, so a partial
                // return later refunds what was paid rather than the list price.
                // It also carries who sold it and what the platform took.
                $payouts = app(\App\Services\SellerPayoutService::class);

                foreach ($cart->lines as $line) {
                    $item = $order->items()->create($line->toOrderItem());
                    $payouts->creditSale($item, $order);
                }

                if ($cart->pointsRedeemable > 0) {
                    $loyalty->redeem($user, $cart->pointsRedeemable, "Redeemed on order {$order->order_number}", $order);
                }

                if ($cart->walletApplicable > 0) {
                    // Re-checks the balance under a row lock and throws if it
                    // moved since pricing — the transaction then rolls back.
                    WalletController::apply(
                        $user,
                        'DEBIT',
                        $cart->walletApplicable,
                        "Applied to order {$order->order_number}",
                        'ORDER',
                        $order->id,
                    );
                }

                if ($cart->coupon) {
                    $cart->coupon->increment('used_count');
                    CouponRedemption::create([
                        'coupon_id' => $cart->coupon->id,
                        'user_id' => $user->id,
                        'order_id' => $order->id,
                        'discount_amount' => $cart->couponDiscount,
                    ]);
                }

                if ($intent) {
                    // The platform's own record of the money, keyed to whichever
                    // gateway took it — this is what refunds later route by.
                    $payments->recordCapture($intent, $verified, $order);
                    $intent->update(['status' => 'CONSUMED', 'order_id' => $order->id]);
                }

                // Points earned on the order, and referral payout if this is
                // the referee's first qualifying purchase.
                if ($pointsEarned > 0) {
                    $loyalty->credit($user, $pointsEarned, "Earned on order {$order->order_number}", $order);
                }

                app(ReferralService::class)->rewardOnFirstOrder($order);

                return $order;
            });
        } catch (ValidationException|\App\Services\PaymentGatewayException $e) {
            // A provider outage is not a bad request: let it surface as a 502
            // instead of the 422 the RuntimeException branch below would give.
            throw $e;
        } catch (\RuntimeException $e) {
            // Wallet/loyalty balance moved between pricing and commit.
            return response()->json(['status' => 'error', 'message' => $e->getMessage()], 422);
        }

        $notifications->orderPlaced($order->load('user'));

        // The sellers whose goods are in it; a failure here must not lose the order.
        try {
            $notifications->newSellerOrder($order);
        } catch (\Throwable $e) {
            report($e);
        }

        return response()->json([
            'status' => 'success',
            'message' => 'Order placed successfully',
            'data' => $order->load('items.product', 'items.variant'),
        ], 201);
    }

    /**
     * Prove a prepaid order was actually paid for.
     *
     * Four things have to line up: the intent belongs to this user, it hasn't
     * been spent or expired, it was issued for *this* cart at *this* price, and
     * the gateway confirms it captured. Any one of them failing aborts the
     * order — a client-supplied transaction id is not evidence of anything.
     *
     * @return array{0: PaymentIntent, 1: ?string, 2: array}
     */
    private function confirmPayment(
        array $validated,
        $user,
        \App\Services\Pricing\PricedCart $cart,
        string $pincode,
        PaymentService $payments,
    ): array {
        $intent = PaymentIntent::where('id', $validated['payment_intent_id'])
            ->lockForUpdate()
            ->first();

        if (! $intent || $intent->user_id !== $user->id) {
            throw ValidationException::withMessages([
                'payment_intent_id' => ['We could not find that payment. Please start again.'],
            ]);
        }

        if (! $intent->isUsable()) {
            throw ValidationException::withMessages([
                'payment_intent_id' => [$intent->status === 'CONSUMED'
                    ? 'This payment has already been used for another order.'
                    : 'This payment has expired. Please start again.'],
            ]);
        }

        // The cart is re-priced from scratch above, so this compares the quote
        // against a total the client had no hand in.
        if ($intent->amount_paise !== $cart->payablePaise()) {
            throw ValidationException::withMessages([
                'payment_intent_id' => ['Your cart changed after payment started. Please review and try again.'],
            ]);
        }

        if (! hash_equals(
            $intent->cart_fingerprint,
            PaymentIntent::fingerprint($cart, $validated['payment_method'], $pincode),
        )) {
            throw ValidationException::withMessages([
                'payment_intent_id' => ['Your cart changed after payment started. Please review and try again.'],
            ]);
        }

        // Evidence is opaque to the API: whatever the intent's gateway needs,
        // in whatever shape its SDK returned it.
        $evidence = array_merge(
            array_filter([
                'payment_id' => $validated['payment_id'] ?? null,
                'signature' => $validated['signature'] ?? null,
            ]),
            $validated['payment'] ?? [],
        );

        $result = $payments->verify($intent, $evidence);

        if (! ($result['verified'] ?? false)) {
            throw ValidationException::withMessages([
                'payment_intent_id' => ['We could not confirm that payment. You have not been charged.'],
            ]);
        }

        return [$intent, $result['payment_id'], $result];
    }

    /** Page size for the order lists, and the ceiling a caller may ask for. */
    private const DEFAULT_PER_PAGE = 50;

    private const MAX_PER_PAGE = 200;

    /** Admin: list every order. */
    /**
     * Staff: every order, narrowed by what they are looking for.
     *
     * ?status=  ?payment_status=  ?payment_method=  ?seller=<id> (an order with
     * any of that shop's goods)  ?from=  ?to= (dates)  ?search= (order number, or
     * the customer's name, email, phone, city or PIN code).
     *
     * `facets.status` counts the orders in each status for everything *except*
     * the status filter, so the tabs above the list can show how many each holds.
     */
    public function index(Request $request)
    {
        $request->validate([
            'from' => 'nullable|date',
            'to' => 'nullable|date',
            'seller' => 'nullable|uuid',
            'status' => 'nullable|string|max:30',
            'payment_status' => 'nullable|string|max:30',
            'payment_method' => 'nullable|string|max:30',
            'search' => 'nullable|string|max:120',
        ]);

        $query = Order::with(['user', 'items.product', 'items.seller:id,display_name,slug'])->orderBy('created_at', 'desc');

        foreach (['payment_status', 'payment_method'] as $column) {
            if ($request->filled($column)) {
                $query->where($column, $request->input($column));
            }
        }

        if ($request->filled('seller')) {
            $query->whereHas('items', fn ($q) => $q->where('seller_id', $request->seller));
        }

        if ($request->filled('from')) {
            $query->whereDate('created_at', '>=', $request->from);
        }
        if ($request->filled('to')) {
            $query->whereDate('created_at', '<=', $request->to);
        }

        if ($request->filled('search')) {
            $term = trim((string) $request->search);
            $like = '%'.str_replace(['%', '_'], ['\\%', '\\_'], $term).'%';

            $query->where(function ($q) use ($like, $term) {
                $q->where('order_number', 'like', $like)
                    ->orWhere('shipping_address->pincode', $term)
                    ->orWhere('shipping_address->city', 'like', $like)
                    ->orWhere('shipping_address->name', 'like', $like)
                    ->orWhere('shipping_address->phone', 'like', $like)
                    ->orWhere('tracking_no', 'like', $like)
                    ->orWhereHas('user', fn ($u) => $u->where('name', 'like', $like)
                        ->orWhere('email', 'like', $like)
                        ->orWhere('phone', 'like', $like));
            });
        }

        // Counted before the status filter narrows the list.
        $counts = (clone $query)->reorder()->selectRaw('status, COUNT(*) as n')->groupBy('status')->pluck('n', 'status');

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        $response = $this->paginated($query, $request);

        return $response->setData(array_merge(
            (array) $response->getData(true),
            ['facets' => ['status' => $counts]],
        ));
    }

    /** Customer: their own order history. */
    public function mine(Request $request)
    {
        $query = Order::with('items.product')
            ->where('user_id', $request->user()->id)
            ->orderBy('created_at', 'desc');

        return $this->paginated($query, $request);
    }

    /**
     * Both order lists used to be unbounded `->get()` calls that eager-loaded
     * every item and product. Fine on a seed database, fatal on a real one — an
     * admin opening the orders page pulled the entire order history into memory.
     *
     * `count` stays the total match count so existing callers keep their
     * meaning; `meta` carries the paging detail.
     */
    private function paginated($query, Request $request)
    {
        $perPage = min((int) $request->get('per_page', self::DEFAULT_PER_PAGE), self::MAX_PER_PAGE);
        $page = $query->paginate(max(1, $perPage))->withQueryString();

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

    public function show(Request $request, $id)
    {
        $order = Order::with([
            'user', 'items.product', 'items.variant',
            // Where the money went and whether it has arrived. Gateway ids stay
            // out of the customer's view.
            'refunds:id,order_id,return_request_id,destination,amount_paise,status,reason,processed_at,created_at',
        ])->find($id);

        if (! $order) {
            return response()->json(['status' => 'error', 'message' => 'Order not found'], 404);
        }

        if (! $request->user()->isAdmin() && $order->user_id !== $request->user()->id) {
            return response()->json(['status' => 'error', 'message' => 'Forbidden'], 403);
        }

        return response()->json(['status' => 'success', 'data' => $order]);
    }

    /** Admin: update fulfillment status / courier / tracking. */
    public function update(Request $request, $id, NotificationService $notifications)
    {
        $order = Order::with('user')->find($id);

        if (! $order) {
            return response()->json(['status' => 'error', 'message' => 'Order not found'], 404);
        }

        $validated = $request->validate([
            'status' => 'sometimes|in:PENDING,CONFIRMED,PACKED,SHIPPED,OUT_FOR_DELIVERY,DELIVERED,CANCELLED',
            'payment_status' => 'sometimes|in:PENDING,PAID,FAILED,REFUNDED',
            'courier' => 'nullable|string',
            'tracking_no' => 'nullable|string',
            'label_generated' => 'nullable|boolean',
        ]);

        // Stamp delivery time so the return window has a real start date.
        if (($validated['status'] ?? null) === 'DELIVERED' && ! $order->delivered_at) {
            $validated['delivered_at'] = now();
        }

        // Cash on delivery is paid when the courier hands over the parcel and
        // takes the cash. Nothing else ever marked it paid, so a delivered COD
        // order sat at PENDING forever and every report of revenue missed it.
        if (($validated['status'] ?? null) === 'DELIVERED'
            && $order->payment_method === 'COD'
            && $order->payment_status === 'PENDING'
            && ! isset($validated['payment_status'])) {
            $validated['payment_status'] = 'PAID';
        }

        $previousStatus = $order->status;
        $order->update($validated);

        if (isset($validated['status']) && $validated['status'] !== $previousStatus) {
            // Lines follow the order: if staff say it has shipped, no seller's
            // "to pack" list should still show its lines.
            app(\App\Services\FulfilmentService::class)->syncLinesToOrderStatus($order);

            $notifications->orderStatusChanged($order, $validated['status']);
            \App\Services\Audit::record($request->user(), 'order.status_changed', $order, "Moved order {$order->order_number} from {$previousStatus} to {$validated['status']}", ['from' => $previousStatus, 'to' => $validated['status']]);
        }

        return response()->json(['status' => 'success', 'data' => $order->fresh()]);
    }

    /**
     * Customer: cancel before dispatch. Restocks the units, releases the coupon
     * and points, and sends back everything that was paid — to the gateway that
     * took it and to the wallet for the part that came from there.
     */
    public function cancel(
        Request $request,
        $id,
        NotificationService $notifications,
        PaymentService $payments,
        LoyaltyService $loyalty,
    ) {
        $order = Order::with(['items', 'user'])->find($id);

        if (! $order) {
            return response()->json(['status' => 'error', 'message' => 'Order not found'], 404);
        }

        if (! $request->user()->isAdmin() && $order->user_id !== $request->user()->id) {
            return response()->json(['status' => 'error', 'message' => 'Forbidden'], 403);
        }

        if (! $order->isCancellable()) {
            return response()->json([
                'status' => 'error',
                'message' => 'This order has already been dispatched and can no longer be cancelled.',
            ], 422);
        }

        $validated = $request->validate([
            'reason' => 'nullable|string|max:500',
            // Staff say why as a code, so cancellations can be counted by cause.
            'reason_code' => 'nullable|in:'.implode(',', Order::STAFF_CANCEL_CODES),
        ]);
        $byStaff = $request->user()->isAdmin();
        $validated['code'] = $byStaff ? ($validated['reason_code'] ?? 'OTHER') : 'CUSTOMER_REQUEST';
        $validated['by'] = $byStaff ? 'ADMIN' : 'CUSTOMER';

        DB::transaction(function () use ($order, $validated, $payments, $loyalty) {
            // Two cancel requests can pass the check above together. The row
            // lock makes the second wait, and it then finds nothing left to do.
            $locked = Order::whereKey($order->id)->lockForUpdate()->firstOrFail();
            if (! $locked->isCancellable()) {
                throw ValidationException::withMessages(['order' => ['This order can no longer be cancelled.']]);
            }

            $wasPaid = $locked->payment_status === 'PAID';
            $payouts = app(\App\Services\SellerPayoutService::class);

            foreach ($order->items as $item) {
                // A line the shop already turned down was undone, and refunded, when it was.
                if ($item->seller_response === 'REJECTED') {
                    continue;
                }

                if ($item->variant_id) {
                    ProductVariant::where('id', $item->variant_id)->increment('stock', $item->quantity);
                }
                ProductOptions::restock($item, (int) $item->quantity);

                // The sale is undone, so what it credited the seller is undone
                // with it — otherwise a cancelled order still pays out.
                $payouts->debitRefund($item, $order, (int) $item->quantity, $item->netPaidTotal());
            }

            // Loyalty has to unwind in both directions. Points the order earned
            // are taken back, and points it consumed are handed back — a
            // cancelled order should leave the customer exactly where they were.
            $loyalty->revoke(
                $order->user,
                (int) $order->points_earned,
                "Reversed — order {$order->order_number} cancelled",
                $order,
            );

            if ((int) $order->points_redeemed > 0) {
                $loyalty->credit(
                    $order->user,
                    (int) $order->points_redeemed,
                    "Returned — order {$order->order_number} cancelled",
                    $order,
                );
            }

            if ($order->coupon_id) {
                Coupon::where('id', $order->coupon_id)->where('used_count', '>', 0)->decrement('used_count');
                CouponRedemption::where('order_id', $order->id)->delete();
            }

            $locked->update([
                'status' => 'CANCELLED',
                'payment_status' => $wasPaid ? 'REFUNDED' : $locked->payment_status,
                'cancellation_reason' => $validated['reason'] ?? ($validated['by'] === 'ADMIN' ? 'Cancelled by the store' : 'Cancelled by customer'),
                'cancellation_code' => $validated['code'],
                'cancelled_by' => $validated['by'],
                'cancelled_at' => now(),
            ]);

            // A paid order gives back everything the customer put in. An unpaid
            // one (cash on delivery, nothing collected) gives back only what
            // they had already taken from the wallet.
            $refundable = $wasPaid
                ? (float) $order->total_amount + (float) $order->wallet_applied
                : (float) $order->wallet_applied;

            // Money already handed back for lines the shop turned down.
            $refundable = max(0, round($refundable - (int) \App\Models\Refund::where('order_id', $order->id)
                ->where('status', '!=', 'FAILED')->sum('amount_paise') / 100, 2));

            // Last on purpose: the gateway cannot be rolled back, so nothing
            // that might still fail may come after it.
            $payments->refundOrder(
                $order,
                $refundable,
                "Cancellation refund for {$order->order_number}",
                "cancel:{$order->id}",
            );
        });

        $notifications->orderStatusChanged($order->fresh(), 'CANCELLED');

        if ($validated['by'] === 'ADMIN') {
            \App\Services\Audit::record($request->user(), 'order.cancelled', $order, "Cancelled order {$order->order_number}", ['code' => $validated['code'], 'note' => $validated['reason'] ?? null]);
        }

        return response()->json(['status' => 'success', 'data' => $order->fresh()]);
    }

    /** Live courier tracking for an order (mock provider in this environment). */
    public function track(Request $request, $id, LogisticsProvider $logistics)
    {
        $order = Order::find($id);

        if (! $order) {
            return response()->json(['status' => 'error', 'message' => 'Order not found'], 404);
        }

        if (! $request->user()->isAdmin() && $order->user_id !== $request->user()->id) {
            return response()->json(['status' => 'error', 'message' => 'Forbidden'], 403);
        }

        if (! $order->tracking_no) {
            return response()->json([
                'status' => 'success',
                'data' => ['tracking_no' => null, 'message' => 'Not dispatched yet.'],
            ]);
        }

        return response()->json(['status' => 'success', 'data' => $logistics->track($order->tracking_no)]);
    }

    /** Admin: generate a courier shipment + label. */
    public function createShipment($id, \App\Services\Delivery\ShipmentBooker $booker)
    {
        $order = Order::find($id);

        if (! $order) {
            return response()->json(['status' => 'error', 'message' => 'Order not found'], 404);
        }

        try {
            // Booking spends money, so an order that already has a shipment
            // returns it instead of booking another.
            $shipment = $booker->book($order);
        } catch (\RuntimeException $e) {
            // A mixed-seller order cannot be one parcel; say so rather than 500.
            return response()->json(['status' => 'error', 'message' => $e->getMessage()], 422);
        }

        return response()->json(['status' => 'success', 'data' => $order->fresh(), 'shipment' => $shipment]);
    }

    /** Order receipt data — the frontend renders/prints this as a PDF. */
    public function invoice(Request $request, $id)
    {
        $order = Order::with(['items.product', 'items.seller:id,display_name', 'items.variant', 'user'])->find($id);

        if (! $order) {
            return response()->json(['status' => 'error', 'message' => 'Order not found'], 404);
        }

        if (! $request->user()->isAdmin() && $order->user_id !== $request->user()->id) {
            return response()->json(['status' => 'error', 'message' => 'Forbidden'], 403);
        }

        return response()->json([
            'status' => 'success',
            'data' => [
                // Until each ordered item carries its actual HSN and tax rate,
                // this is a payment receipt, not a statutory GST tax invoice.
                'document_type' => 'ORDER_RECEIPT',
                'invoice_number' => 'RCT-'.$order->order_number,
                'issued_at' => $order->created_at->toDateString(),
                'seller' => [
                    'name' => (string) \App\Models\Setting::get('store.legal_name', config('app.name')),
                    'gstin' => (string) \App\Models\Setting::get('store.gstin', ''),
                    'address' => (string) \App\Models\Setting::get('store.address', ''),
                ],
                'order' => $order,
                'totals' => [
                    'subtotal' => (float) $order->subtotal,
                    'discount' => (float) $order->discount,
                    'shipping' => (float) $order->shipping_charge,
                    'wallet_applied' => (float) $order->wallet_applied,
                    'grand_total' => (float) $order->total_amount,
                ],
            ],
        ]);
    }

    public function destroy(Request $request, $id)
    {
        $order = Order::find($id);

        if (! $order) {
            return response()->json(['status' => 'error', 'message' => 'Order not found'], 404);
        }

        \App\Services\Audit::record($request->user(), 'order.deleted', $order, "Deleted order {$order->order_number}");
        $order->delete();

        return response()->json(['status' => 'success', 'message' => 'Order deleted']);
    }
}
