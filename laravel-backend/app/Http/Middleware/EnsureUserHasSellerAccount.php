<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Entry to the onboarding area.
 *
 * Deliberately weaker than the `seller` middleware: it asks only whether a
 * merchant account exists, not whether it is active. An applicant whose account
 * is PENDING has to be able to reach exactly these routes — requiring ACTIVE
 * here would lock every new seller out of the flow that makes them active.
 *
 * Nothing behind this can list a product, see an order, or move money.
 */
class EnsureUserHasSellerAccount
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user) {
            return response()->json(['status' => 'error', 'message' => 'Unauthenticated.'], 401);
        }

        // Queried rather than read off `$user->seller`, which caches: a user
        // instance loaded before the account existed answers null forever
        // afterwards. The result is put back on the model so nothing
        // downstream pays for the lookup twice.
        $seller = $user->seller()->first();
        $user->setRelation('seller', $seller);

        if (! $seller) {
            return response()->json([
                'status' => 'error',
                'message' => 'You have not applied to sell yet.',
                'code' => 'no_seller_account',
            ], 403);
        }

        return $next($request);
    }
}
