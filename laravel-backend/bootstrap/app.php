<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Admin-managed integration settings, applied before anything else can read
        // config (see the class for why this is middleware and not a provider).
        $middleware->prepend(\App\Http\Middleware\ApplyIntegrationSettings::class);

        $middleware->alias([
            // 'admin' = may use the admin panel (sub-admins included).
            // 'manage-users' = may change who has access. Stacked on top of
            // 'admin' for the handful of routes sub-admins must not reach.
            'admin' => \App\Http\Middleware\EnsureUserIsAdmin::class,
            'manage-users' => \App\Http\Middleware\EnsureUserCanManageUsers::class,
            'auth.optional' => \App\Http\Middleware\OptionalSanctumAuth::class,
            // 'seller' = runs a merchant account in good standing. Separate
            // from 'admin' on purpose: a seller manages their own shop, never
            // the store.
            'seller' => \App\Http\Middleware\EnsureUserIsSeller::class,
            // Entry to catalog writes for staff *or* an active seller. Per-row
            // ownership is still enforced in the controller.
            'can-manage-catalog' => \App\Http\Middleware\EnsureUserCanManageCatalog::class,
            // 'seller.account' = has a merchant account, in any standing. Only
            // the onboarding flow uses it; everything else wants 'seller'.
            'seller.account' => \App\Http\Middleware\EnsureUserHasSellerAccount::class,
        ]);

        // This is a JSON-only API — there is no 'login' web route to redirect
        // guests to. Without this, unauthenticated requests that don't send an
        // explicit `Accept: application/json` header (most fetch() calls don't)
        // crash with a 500 (RouteNotFoundException) instead of a clean 401.
        $middleware->redirectGuestsTo(fn () => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Error tracking. A no-op until SENTRY_LARAVEL_DSN is set. Only exceptions
        // Laravel itself reports arrive here (validation failures, 404s and auth
        // errors are already excluded), and every event is scrubbed on the way out
        // (App\Monitoring\SentryScrubber).
        \Sentry\Laravel\Integration::handles($exceptions);

        // Never echo these back into a form or an error page.
        $exceptions->dontFlash([
            'current_password', 'password_confirmation', 'api_key', 'key_secret',
            'client_secret', 'webhook_secret', 'token', 'id_token', 'values',
        ]);

        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*'),
        );

        // The provider was unreachable or refused us. Say so plainly (502)
        // rather than 500 — the message is customer-safe by construction.
        $exceptions->render(fn (\App\Services\PaymentGatewayException $e, Request $request) => $request->is('api/*')
            ? response()->json(['status' => 'error', 'message' => $e->getMessage()], 502)
            : null);
    })->create();
