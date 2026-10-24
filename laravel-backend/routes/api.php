<?php

use App\Http\Controllers\Api\AddressController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CategoryController;
use App\Http\Controllers\Api\CouponController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\OrderController;
use App\Http\Controllers\Api\ProductController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\ReturnController;
use App\Http\Controllers\Api\ReviewController;
use App\Http\Controllers\Api\ServiceabilityController;
use App\Http\Controllers\Api\UploadController;
use App\Http\Controllers\Api\WalletController;
use App\Http\Controllers\Api\WishlistController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| BazaarX Laravel REST API Routes
|--------------------------------------------------------------------------
*/

// Blanket ceiling on the whole API. The credential and OTP endpoints below add
// their own, much tighter limiters on top — see AppServiceProvider.
Route::prefix('v1')->middleware('throttle:api')->group(function () {

    // ── Payment gateway callbacks ────────────────────────────────────────
    // One endpoint for every gateway; the driver named in the URL authenticates
    // its own payloads. Public because the gateway is not a logged-in user.
    Route::post('/webhooks/payments/{provider}', [\App\Http\Controllers\Api\PaymentWebhookController::class, 'handle']);

    // What kind of store this is (single business, vendors, shops first...), and
    // the shops themselves, for apps that let shoppers pick a shop first.
    Route::get('/config', [\App\Http\Controllers\Api\ShopController::class, 'config']);
    Route::get('/shops', [\App\Http\Controllers\Api\ShopController::class, 'index']);
    Route::get('/shops/{shop}', [\App\Http\Controllers\Api\ShopController::class, 'show']);

    // Delivery partners push shipment updates here; each is authenticated by its own secret.
    Route::post('/webhooks/delivery/{carrier}', [\App\Http\Controllers\Api\DeliveryWebhookController::class, 'handle']);

    // ── Auth ─────────────────────────────────────────────────────────────
    Route::post('/auth/register', [\App\Http\Controllers\Api\AuthController::class, 'register'])
        ->middleware('throttle:register');
    Route::post('/auth/login', [\App\Http\Controllers\Api\AuthController::class, 'login'])
        ->middleware('throttle:login');
    Route::post('/auth/otp/send', [\App\Http\Controllers\Api\AuthController::class, 'sendOtp'])
        ->middleware('throttle:otp-send');
    Route::post('/auth/otp/verify', [\App\Http\Controllers\Api\AuthController::class, 'verifyOtp'])
        ->middleware('throttle:otp-verify');
    // Throttled like a login: the ID token is a bearer credential, and an
    // unthrottled verify endpoint is a free oracle for probing them.
    Route::post('/auth/google', [\App\Http\Controllers\Api\AuthController::class, 'google'])
        ->middleware('throttle:login');
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [AuthController::class, 'logout']);
        Route::get('/auth/me', [AuthController::class, 'me']);
    });

    // ── Categories — public reads, admin writes ──────────────────────────
    Route::get('/categories', [CategoryController::class, 'index']);
    Route::get('/categories/{id}', [CategoryController::class, 'show']);
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::post('/categories', [CategoryController::class, 'store']);
        Route::put('/categories/{id}', [CategoryController::class, 'update']);
        Route::delete('/categories/{id}', [CategoryController::class, 'destroy']);
        Route::get('/admin/category-requests', [\App\Http\Controllers\Api\CategoryRequestController::class, 'adminIndex']);
        Route::put('/admin/category-requests/{id}', [\App\Http\Controllers\Api\CategoryRequestController::class, 'decide']);
    });

    // ── Products — public reads, admin writes ────────────────────────────
    // Optional auth: the listing is public, but staff need to see drafts and
    // discontinued lines here to manage them. Without it `$request->user()` is
    // always null on these routes and an admin sees the shopper's catalog.
    Route::get('/products', [ProductController::class, 'index'])
        ->middleware('auth.optional');
    Route::get('/products/{id}', [ProductController::class, 'show'])
        ->middleware('auth.optional');
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        // AI-assisted bulk import: preview parses + scores, commit writes.
        Route::post('/admin/products/import/preview', [\App\Http\Controllers\Api\ProductImportController::class, 'preview']);
        Route::post('/admin/products/import/commit', [\App\Http\Controllers\Api\ProductImportController::class, 'commit']);
    });

    // Catalog writes are open to staff and to active sellers. The middleware
    // grants entry; ProductController enforces per-row ownership, so a seller
    // reaching these routes still cannot touch another seller's listing.
    Route::middleware(['auth:sanctum', 'can-manage-catalog'])->group(function () {
        Route::post('/products', [ProductController::class, 'store']);
        Route::put('/products/{id}', [ProductController::class, 'update']);
        Route::delete('/products/{id}', [ProductController::class, 'destroy']);
        // Stock levels only - no variant list to rebuild. Ownership is enforced
        // per variant inside the controller, like the product routes above.
        Route::put('/inventory', [\App\Http\Controllers\Api\InventoryController::class, 'update']);
        Route::post('/uploads', [UploadController::class, 'store'])
            ->middleware('throttle:sensitive-write');
    });

    // ── Seller onboarding ────────────────────────────────────────────────
    // Open to any signed-in customer, but it only ever produces a PENDING
    // account — nothing here can switch a shop on.
    Route::middleware('auth:sanctum')->post('/sellers/apply', [\App\Http\Controllers\Api\SellerOnboardingController::class, 'apply'])
        ->middleware('throttle:sensitive-write');

    // Reachable while PENDING, which is the whole point: this is the flow that
    // makes an account active. 'seller.account' checks existence, not standing.
    Route::middleware(['auth:sanctum', 'seller.account'])->prefix('seller/onboarding')->group(function () {
        Route::get('/', [\App\Http\Controllers\Api\SellerOnboardingController::class, 'show']);
        Route::put('/kyc', [\App\Http\Controllers\Api\SellerOnboardingController::class, 'saveKyc']);
        Route::post('/documents', [\App\Http\Controllers\Api\SellerOnboardingController::class, 'uploadDocument'])
            ->middleware('throttle:sensitive-write');
        Route::delete('/documents/{id}', [\App\Http\Controllers\Api\SellerOnboardingController::class, 'deleteDocument']);
        Route::post('/submit', [\App\Http\Controllers\Api\SellerOnboardingController::class, 'submit'])
            ->middleware('throttle:sensitive-write');
    });

    // Identity documents are never on a public URL. This streams one to the
    // seller it belongs to, or to staff reviewing it, and to nobody else.
    Route::middleware('auth:sanctum')
        ->get('/seller/documents/{id}/download', [\App\Http\Controllers\Api\SellerOnboardingController::class, 'downloadDocument']);

    // ── Sellers ──────────────────────────────────────────────────────────
    // The merchant's own shop. Every query inside is scoped to their seller id.
    Route::middleware(['auth:sanctum', 'seller'])->prefix('seller')->group(function () {
        Route::get('/me', [\App\Http\Controllers\Api\SellerController::class, 'me']);
        Route::put('/me', [\App\Http\Controllers\Api\SellerController::class, 'update']);
        Route::get('/products', [\App\Http\Controllers\Api\SellerController::class, 'products']);
        Route::get('/category-requests', [\App\Http\Controllers\Api\CategoryRequestController::class, 'sellerIndex']);
        Route::post('/category-requests', [\App\Http\Controllers\Api\CategoryRequestController::class, 'sellerStore']);
        Route::get('/order-items', [\App\Http\Controllers\Api\SellerController::class, 'orderItems']);
        // Packing and shipping their own lines. Each answers with the updated
        // line; the order's status is rolled up from its lines server-side.
        Route::post('/order-items/{id}/pack', [\App\Http\Controllers\Api\SellerController::class, 'packItem'])
            ->middleware('throttle:sensitive-write');
        Route::post('/order-items/{id}/accept', [\App\Http\Controllers\Api\SellerController::class, 'acceptItem'])
            ->middleware('throttle:sensitive-write');
        Route::post('/order-items/{id}/reject', [\App\Http\Controllers\Api\SellerController::class, 'rejectItem'])
            ->middleware('throttle:sensitive-write');
        Route::put('/products/{id}/availability', [\App\Http\Controllers\Api\SellerController::class, 'setAvailability']);
        Route::post('/order-items/{id}/ship', [\App\Http\Controllers\Api\SellerController::class, 'shipItem'])
            ->middleware('throttle:sensitive-write');
        Route::get('/ledger', [\App\Http\Controllers\Api\SellerController::class, 'ledger']);
        Route::get('/money', [\App\Http\Controllers\Api\SellerMoneyController::class, 'show']);
        Route::post('/payout-requests', [\App\Http\Controllers\Api\SellerMoneyController::class, 'requestPayout'])
            ->middleware('throttle:sensitive-write');
        Route::delete('/payout-requests/{id}', [\App\Http\Controllers\Api\SellerMoneyController::class, 'cancelPayout']);
        Route::post('/bank', [\App\Http\Controllers\Api\SellerMoneyController::class, 'changeBank'])
            ->middleware('throttle:sensitive-write');
        Route::delete('/bank/pending', [\App\Http\Controllers\Api\SellerMoneyController::class, 'withdrawBankChange']);
        Route::get('/statements', [\App\Http\Controllers\Api\SellerMoneyController::class, 'statementMonths']);
        Route::get('/statements/{month}', [\App\Http\Controllers\Api\SellerMoneyController::class, 'statement']);
        Route::get('/statements/{month}/csv', [\App\Http\Controllers\Api\SellerMoneyController::class, 'statementCsv']);
        Route::get('/overview', [\App\Http\Controllers\Api\SellerController::class, 'overview']);
        Route::get('/reviews', [\App\Http\Controllers\Api\SellerController::class, 'reviews']);
        Route::put('/reviews/{id}/reply', [\App\Http\Controllers\Api\SellerController::class, 'replyToReview']);
        Route::get('/questions', [\App\Http\Controllers\Api\SellerController::class, 'questions']);
        Route::get('/returns', [\App\Http\Controllers\Api\SellerController::class, 'returns']);
        Route::put('/returns/{id}/review', [\App\Http\Controllers\Api\SellerController::class, 'reviewReturn']);
        Route::get('/coupons', [CouponController::class, 'sellerIndex']);
        Route::post('/coupons', [CouponController::class, 'sellerStore']);
        Route::put('/coupons/{id}', [CouponController::class, 'sellerUpdate']);
        Route::delete('/coupons/{id}', [CouponController::class, 'sellerDestroy']);
        Route::post('/products/import/preview', [\App\Http\Controllers\Api\ProductImportController::class, 'preview']);
        Route::post('/products/import/commit', [\App\Http\Controllers\Api\ProductImportController::class, 'commit']);
    });

    // Onboarding and commercial terms are staff-only — there is deliberately no
    // public seller signup, since a self-registered storefront can list products
    // and accrue a payout balance.
    Route::middleware(['auth:sanctum', 'admin', 'manage-users'])->group(function () {
        Route::get('/admin/sellers', [\App\Http\Controllers\Api\AdminSellerController::class, 'index']);
        // Before /{id}, or "applications" is swallowed as a seller id.
        Route::get('/admin/sellers/applications', [\App\Http\Controllers\Api\AdminSellerController::class, 'applications']);
        Route::get('/admin/sellers/{id}/review', [\App\Http\Controllers\Api\AdminSellerController::class, 'reviewDetail']);
        Route::get('/admin/sellers/{id}/performance', [\App\Http\Controllers\Api\AdminSellerController::class, 'performance']);
        Route::post('/admin/sellers/{id}/kyc/approve', [\App\Http\Controllers\Api\AdminSellerController::class, 'approveKyc']);
        Route::post('/admin/sellers/{id}/kyc/reject', [\App\Http\Controllers\Api\AdminSellerController::class, 'rejectKyc']);
        Route::get('/admin/sellers/{id}', [\App\Http\Controllers\Api\AdminSellerController::class, 'show']);
        Route::post('/admin/sellers', [\App\Http\Controllers\Api\AdminSellerController::class, 'store']);
        Route::put('/admin/sellers/{id}', [\App\Http\Controllers\Api\AdminSellerController::class, 'update']);
        Route::post('/admin/sellers/{id}/payout-adjustment', [\App\Http\Controllers\Api\AdminSellerController::class, 'adjustPayout']);
        // What each vendor is owed, what is payable now, and recording a transfer.
        Route::get('/admin/audit-logs', [\App\Http\Controllers\Api\AuditLogController::class, 'index']);
        Route::get('/admin/payouts', [\App\Http\Controllers\Api\AdminPayoutController::class, 'index']);
        Route::get('/admin/payout-requests', [\App\Http\Controllers\Api\AdminMoneyController::class, 'payoutRequests']);
        Route::post('/admin/payout-requests/{id}/pay', [\App\Http\Controllers\Api\AdminMoneyController::class, 'pay']);
        Route::post('/admin/payout-requests/{id}/reject', [\App\Http\Controllers\Api\AdminMoneyController::class, 'reject']);
        Route::get('/admin/bank-changes', [\App\Http\Controllers\Api\AdminMoneyController::class, 'bankChanges']);
        Route::post('/admin/sellers/{id}/bank-change/approve', [\App\Http\Controllers\Api\AdminMoneyController::class, 'approveBank']);
        Route::post('/admin/sellers/{id}/bank-change/reject', [\App\Http\Controllers\Api\AdminMoneyController::class, 'rejectBank']);
        Route::get('/admin/sellers/{id}/statements/{month}', [\App\Http\Controllers\Api\AdminMoneyController::class, 'statement']);
        Route::get('/admin/sellers/{id}/statements/{month}/csv', [\App\Http\Controllers\Api\AdminMoneyController::class, 'statementCsv']);
        Route::post('/admin/sellers/{id}/payouts', [\App\Http\Controllers\Api\AdminPayoutController::class, 'store']);
    });

    // ── Reels ────────────────────────────────────────────────────────────
    // Optional feature: only products a seller opted into appear here. Public,
    // read-only, and returns an empty list rather than an error when nobody
    // has ever attached a clip.
    Route::get('/reels', [\App\Http\Controllers\Api\ReelController::class, 'index']);

    // ── Delivery ─────────────────────────────────────────────────────────
    Route::post('/serviceability', [ServiceabilityController::class, 'check'])
        ->middleware('throttle:sensitive-write');

    // Rate-shops every enabled carrier for this cart and destination. Public,
    // because a shopper needs the delivery promise before signing in.
    Route::post('/delivery/quote', [\App\Http\Controllers\Api\DeliveryController::class, 'quote'])
        ->middleware('throttle:sensitive-write');

    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/delivery/orders/{id}/track', [\App\Http\Controllers\Api\DeliveryController::class, 'track']);
    });

    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/delivery/carriers', [\App\Http\Controllers\Api\DeliveryController::class, 'carriers']);
        Route::get('/admin/orders/{id}/tracking', [\App\Http\Controllers\Api\DeliveryController::class, 'adminTrack']);
    });

    // ── Reviews ──────────────────────────────────────────────────────────
    // Public read, but the optional-auth middleware lets a signed-in user's
    // own votes come back in the same payload.
    Route::get('/products/{productId}/reviews', [ReviewController::class, 'index'])
        ->middleware('auth.optional');
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/products/{productId}/reviews', [ReviewController::class, 'store'])
            ->middleware('throttle:sensitive-write');
        Route::post('/reviews/{id}/vote', [ReviewController::class, 'vote'])
            ->middleware('throttle:sensitive-write');
        Route::get('/reviews/mine', [ReviewController::class, 'mine']);
        Route::get('/reviews/reviewable', [ReviewController::class, 'reviewable']);
    });
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/reviews/pending', [ReviewController::class, 'pending']);
        Route::put('/admin/reviews/{id}/moderate', [ReviewController::class, 'moderate']);
        Route::put('/admin/reviews/{id}/reply', [ReviewController::class, 'reply']);
    });

    // ── Cart ─────────────────────────────────────────────────────────────
    // Public: a shopper builds a cart before signing in, and a cart showing
    // last month's price is a broken promise whether or not they have an
    // account. Read-only — it prices what you send, it stores nothing.
    Route::post('/cart/price', [\App\Http\Controllers\Api\CartController::class, 'price']);

    // ── Orders ───────────────────────────────────────────────────────────
    Route::middleware('auth:sanctum')->group(function () {
        // Step one of a prepaid checkout: the server prices the cart and opens
        // a payment for exactly that amount. `/orders/checkout` will not mark an
        // order paid without one of these coming back to it.
        Route::post('/payments/intent', [\App\Http\Controllers\Api\PaymentIntentController::class, 'store'])
            ->middleware('throttle:sensitive-write');
        Route::post('/orders/checkout', [OrderController::class, 'store'])
            ->middleware('throttle:sensitive-write');
        Route::get('/orders/mine', [OrderController::class, 'mine']);
        Route::get('/orders/{id}', [OrderController::class, 'show']);
        Route::get('/orders/{id}/invoice', [OrderController::class, 'invoice']);
        Route::get('/orders/{id}/track', [OrderController::class, 'track']);
        Route::post('/orders/{id}/cancel', [OrderController::class, 'cancel']);
    });
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/support/tickets', [\App\Http\Controllers\Api\AdminSupportController::class, 'index']);
        Route::get('/admin/support/agents', [\App\Http\Controllers\Api\AdminSupportController::class, 'agents']);
        Route::get('/admin/support/tickets/{id}', [\App\Http\Controllers\Api\AdminSupportController::class, 'show']);
        Route::post('/admin/support/tickets/{id}/messages', [\App\Http\Controllers\Api\AdminSupportController::class, 'reply']);
        Route::put('/admin/support/tickets/{id}', [\App\Http\Controllers\Api\AdminSupportController::class, 'update']);
        Route::get('/admin/live-orders', [\App\Http\Controllers\Api\AdminLiveOrderController::class, 'index']);
        Route::post('/admin/order-items/{id}/reject', [\App\Http\Controllers\Api\AdminLiveOrderController::class, 'rejectItem']);
        Route::get('/admin/orders', [OrderController::class, 'index']);
        Route::put('/admin/orders/{id}', [OrderController::class, 'update']);
        Route::post('/admin/orders/{id}/shipment', [OrderController::class, 'createShipment']);
        Route::delete('/admin/orders/{id}', [OrderController::class, 'destroy']);
    });

    // ── Addresses ────────────────────────────────────────────────────────
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/support/tickets', [\App\Http\Controllers\Api\SupportController::class, 'index']);
        Route::post('/support/tickets', [\App\Http\Controllers\Api\SupportController::class, 'store'])
            ->middleware('throttle:sensitive-write');
        Route::get('/support/tickets/{id}', [\App\Http\Controllers\Api\SupportController::class, 'show']);
        Route::post('/support/tickets/{id}/messages', [\App\Http\Controllers\Api\SupportController::class, 'reply'])
            ->middleware('throttle:sensitive-write');
        Route::post('/support/tickets/{id}/close', [\App\Http\Controllers\Api\SupportController::class, 'close']);
        Route::post('/support/tickets/{id}/rating', [\App\Http\Controllers\Api\SupportController::class, 'rate']);
        Route::get('/addresses', [AddressController::class, 'index']);
        Route::post('/addresses', [AddressController::class, 'store']);
        Route::put('/addresses/{id}', [AddressController::class, 'update']);
        Route::delete('/addresses/{id}', [AddressController::class, 'destroy']);
    });

    // ── Profile & wallet ─────────────────────────────────────────────────
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/profile', [ProfileController::class, 'show']);
        Route::put('/profile', [ProfileController::class, 'update']);
        Route::put('/profile/password', [ProfileController::class, 'changePassword']);
        Route::put('/profile/notifications', [ProfileController::class, 'notificationPreferences']);
        Route::get('/wallet', [WalletController::class, 'show']);
    });
    // ── Users & staff — full admins only ─────────────────────────────────
    // `manage-users` stacks on top of `admin`: a sub-admin runs the store but
    // cannot decide who else gets in, nor move money into an account.
    Route::middleware(['auth:sanctum', 'admin', 'manage-users'])->group(function () {
        Route::post('/admin/users/{userId}/wallet', [WalletController::class, 'adjust']);
        Route::get('/admin/users', [\App\Http\Controllers\Api\AdminUserController::class, 'index']);
        Route::post('/admin/users/staff', [\App\Http\Controllers\Api\AdminUserController::class, 'storeStaff']);
        Route::put('/admin/users/{id}/role', [\App\Http\Controllers\Api\AdminUserController::class, 'updateRole']);
        Route::put('/admin/users/{id}/status', [\App\Http\Controllers\Api\AdminUserController::class, 'updateStatus']);
        Route::put('/admin/users/{id}/password', [\App\Http\Controllers\Api\AdminUserController::class, 'resetStaffPassword']);

        // Integration credentials and settings (Gemini, Google sign-in, couriers,
        // shipping, marketplace). Full admins only, like everything in this group,
        // and every change also re-asks for the admin's password.
        Route::get('/admin/integrations', [\App\Http\Controllers\Api\IntegrationController::class, 'index']);
        Route::get('/admin/integrations/audit', [\App\Http\Controllers\Api\IntegrationController::class, 'audit']);
        Route::put('/admin/integrations/{group}', [\App\Http\Controllers\Api\IntegrationController::class, 'update'])
            ->middleware('throttle:integrations-write');
        Route::delete('/admin/integrations/{group}/{field}', [\App\Http\Controllers\Api\IntegrationController::class, 'destroy'])
            ->middleware('throttle:integrations-write');
        Route::post('/admin/integrations/{group}/test', [\App\Http\Controllers\Api\IntegrationController::class, 'test'])
            ->middleware('throttle:integrations-test');
    });

    // ── Wishlists ────────────────────────────────────────────────────────
    Route::get('/wishlists/shared/{token}', [WishlistController::class, 'viewShared']);
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/wishlists', [WishlistController::class, 'index']);
        Route::post('/wishlists', [WishlistController::class, 'store']);
        Route::put('/wishlists/{id}', [WishlistController::class, 'update']);
        Route::delete('/wishlists/{id}', [WishlistController::class, 'destroy']);
        Route::post('/wishlists/{id}/share', [WishlistController::class, 'share']);
        Route::post('/wishlist-items', [WishlistController::class, 'addItem']);
        Route::delete('/wishlist-items/{itemId}', [WishlistController::class, 'removeItem']);
    });

    // ── Deals ────────────────────────────────────────────────────────────
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/devices', [\App\Http\Controllers\Api\DeviceController::class, 'store'])
            ->middleware('throttle:sensitive-write');
        Route::delete('/devices', [\App\Http\Controllers\Api\DeviceController::class, 'destroy']);
    });
    Route::get('/deals/bundles', [\App\Http\Controllers\Api\BundleDealController::class, 'index']);
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/bundles', [\App\Http\Controllers\Api\BundleDealController::class, 'adminIndex']);
        Route::post('/admin/bundles', [\App\Http\Controllers\Api\BundleDealController::class, 'store']);
        Route::put('/admin/bundles/{id}', [\App\Http\Controllers\Api\BundleDealController::class, 'update']);
        Route::delete('/admin/bundles/{id}', [\App\Http\Controllers\Api\BundleDealController::class, 'destroy']);
    });

    // ── Coupons ──────────────────────────────────────────────────────────
    Route::middleware('auth:sanctum')->post('/coupons/preview', [CouponController::class, 'preview']);
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/coupons', [CouponController::class, 'index']);
        Route::post('/admin/coupons', [CouponController::class, 'store']);
        Route::put('/admin/coupons/{id}', [CouponController::class, 'update']);
        Route::delete('/admin/coupons/{id}', [CouponController::class, 'destroy']);
    });

    // ── Returns & refunds ────────────────────────────────────────────────
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/returns/mine', [ReturnController::class, 'mine']);
        Route::post('/returns', [ReturnController::class, 'store']);
    });
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/returns', [ReturnController::class, 'index']);
        Route::post('/admin/returns/{id}/approve', [ReturnController::class, 'approve']);
        Route::post('/admin/returns/{id}/reject', [ReturnController::class, 'reject']);
        Route::post('/admin/returns/{id}/picked-up', [ReturnController::class, 'markPickedUp']);
        Route::post('/admin/returns/{id}/refund', [ReturnController::class, 'refund']);
    });

    // ── Notifications ────────────────────────────────────────────────────
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/notifications', [NotificationController::class, 'index']);
        Route::put('/notifications/{id}/read', [NotificationController::class, 'markRead']);
        Route::put('/notifications/read-all', [NotificationController::class, 'markAllRead']);
    });
    Route::middleware(['auth:sanctum', 'admin'])
        ->post('/admin/notifications/broadcast', [\App\Http\Controllers\Api\NotificationController::class, 'broadcast']);

    // ── Q&A ──────────────────────────────────────────────────────────────
    Route::get('/products/{productId}/questions', [\App\Http\Controllers\Api\QuestionController::class, 'index']);
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/products/{productId}/questions', [\App\Http\Controllers\Api\QuestionController::class, 'store'])
            ->middleware('throttle:sensitive-write');
        Route::post('/questions/{id}/answer', [\App\Http\Controllers\Api\QuestionController::class, 'answer'])
            ->middleware('throttle:sensitive-write');
    });
    // Unauthenticated by design, so the throttle is the only thing stopping
    // one host from inflating an answer's helpful count on its own.
    Route::post('/answers/{id}/helpful', [\App\Http\Controllers\Api\QuestionController::class, 'voteHelpful'])
        ->middleware('throttle:sensitive-write');
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/questions', [\App\Http\Controllers\Api\QuestionController::class, 'pending']);
        Route::put('/admin/questions/{id}/moderate', [\App\Http\Controllers\Api\QuestionController::class, 'moderate']);
    });

    // ── Recommendations ──────────────────────────────────────────────────
    Route::get('/recommendations/trending', [\App\Http\Controllers\Api\RecommendationController::class, 'trending']);
    Route::get('/products/{productId}/related', [\App\Http\Controllers\Api\RecommendationController::class, 'relatedTo']);
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/recommendations/personalized', [\App\Http\Controllers\Api\RecommendationController::class, 'personalized']);
    });

    // ── Loyalty & referrals ──────────────────────────────────────────────
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/loyalty', [\App\Http\Controllers\Api\LoyaltyController::class, 'show']);
        Route::post('/loyalty/quote', [\App\Http\Controllers\Api\LoyaltyController::class, 'quote']);
        Route::get('/referrals', [\App\Http\Controllers\Api\LoyaltyController::class, 'referrals']);
    });

    // ── Theme ────────────────────────────────────────────────────────────
    // Public read: the storefront needs the overrides before first paint, and
    // they contain nothing sensitive. Writes are staff-only but NOT restricted
    // to full admins — appearance is store operations, not access control.
    Route::get('/theme', [\App\Http\Controllers\Api\ThemeController::class, 'show']);
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/theme', [\App\Http\Controllers\Api\ThemeController::class, 'schema']);
        Route::put('/admin/theme', [\App\Http\Controllers\Api\ThemeController::class, 'update']);
        Route::post('/admin/theme/reset', [\App\Http\Controllers\Api\ThemeController::class, 'reset']);
        Route::post('/admin/theme/logo', [\App\Http\Controllers\Api\ThemeController::class, 'uploadLogo'])
            ->middleware('throttle:sensitive-write');
        Route::delete('/admin/theme/logo', [\App\Http\Controllers\Api\ThemeController::class, 'removeLogo']);
    });

    // ── Storefront builder & platform settings ───────────────────────────
    Route::get('/storefront/sections', [\App\Http\Controllers\Api\StorefrontController::class, 'index']);
    Route::get('/settings', [\App\Http\Controllers\Api\StorefrontController::class, 'settings']);
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::post('/admin/storefront/sections', [\App\Http\Controllers\Api\StorefrontController::class, 'store']);
        Route::put('/admin/storefront/sections/{id}', [\App\Http\Controllers\Api\StorefrontController::class, 'update']);
        Route::delete('/admin/storefront/sections/{id}', [\App\Http\Controllers\Api\StorefrontController::class, 'destroy']);
        Route::put('/admin/storefront/reorder', [\App\Http\Controllers\Api\StorefrontController::class, 'reorder']);
        Route::put('/admin/settings', [\App\Http\Controllers\Api\StorefrontController::class, 'updateSettings']);
    });

    // ── Analytics ────────────────────────────────────────────────────────
    Route::middleware(['auth:sanctum', 'admin'])->group(function () {
        Route::get('/admin/analytics', [\App\Http\Controllers\Api\AnalyticsController::class, 'index']);
    });

});
