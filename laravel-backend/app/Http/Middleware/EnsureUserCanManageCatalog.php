<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Who may create or change a product: staff, or an active seller.
 *
 * This grants *entry* to the catalog write endpoints, not permission over any
 * particular product. Ownership is enforced in ProductController, per row —
 * passing this middleware never means a seller may touch someone else's
 * listing.
 */
class EnsureUserCanManageCatalog
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user) {
            return response()->json(['status' => 'error', 'message' => 'Unauthenticated.'], 401);
        }

        if ($user->isAdmin()) {
            return $next($request);
        }

        $seller = $user->seller()->first();
        $user->setRelation('seller', $seller);

        if ($seller && $seller->isActive()) {
            return $next($request);
        }

        return response()->json([
            'status' => 'error',
            'message' => $seller
                ? 'Your seller account is not active.'
                : 'Forbidden — admin or seller access required.',
        ], 403);
    }
}
