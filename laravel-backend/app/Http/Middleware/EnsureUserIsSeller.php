<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Gates the seller area.
 *
 * Three separate questions, deliberately kept apart: are you signed in, do you
 * have a merchant account, and is that account in good standing. Collapsing
 * them loses the ability to tell a suspended seller *why* they're locked out,
 * which turns a support conversation into a bug report.
 */
class EnsureUserIsSeller
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user) {
            return response()->json(['status' => 'error', 'message' => 'Unauthenticated.'], 401);
        }

        // In a single-business installation staff operate the house shop.
        // It has no seller user_id, so the ordinary relation cannot find it.
        if ($user->isAdmin() && ! \App\Support\StoreMode::vendorsEnabled()) {
            $user->setRelation('seller', \App\Models\Seller::house());

            return $next($request);
        }

        // Freshly resolved, then cached back onto the user — the relation is
        // memoised per instance, and standing can change between requests.
        $seller = $user->seller()->first();
        $user->setRelation('seller', $seller);

        if (! $seller) {
            return response()->json([
                'status' => 'error',
                'message' => 'Forbidden — this area is for registered sellers.',
            ], 403);
        }

        if (! $seller->isActive()) {
            return response()->json([
                'status' => 'error',
                'message' => $seller->status === 'PENDING'
                    ? 'Your seller account is still under review.'
                    : 'Your seller account has been suspended. Contact support.',
            ], 403);
        }

        return $next($request);
    }
}
