<?php

namespace App\Http\Middleware;

use App\Integrations\IntegrationSettings;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

/**
 * Applies the admin-managed settings over the environment for this request.
 *
 * Why middleware, and not a service provider's boot():
 *
 *  - Global middleware runs before routing, so it is ahead of any controller
 *    that could resolve a service which copies its settings at construction.
 *  - It runs for HTTP requests only. Console commands never pass through
 *    middleware, which is what keeps decrypted secrets out of
 *    `php artisan config:cache`: a boot-time overlay would run there too and
 *    write every secret into bootstrap/cache/config.php in plaintext.
 *
 * It must never break a request. If the settings cannot be read (the table is not
 * migrated yet, the database is briefly down), the request carries on with the
 * environment's values, which is exactly how the app behaved before this existed.
 */
class ApplyIntegrationSettings
{
    public function __construct(private readonly IntegrationSettings $settings) {}

    public function handle(Request $request, Closure $next): Response
    {
        try {
            $this->settings->apply();
        } catch (Throwable $e) {
            // The class name and message only — never the context, which could
            // include a value.
            Log::warning('[Integrations] settings not applied; using the environment', [
                'reason' => $e::class,
            ]);
        }

        return $next($request);
    }
}
