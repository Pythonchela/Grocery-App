<?php

namespace App\Providers;

use App\Services\Contracts\LogisticsProvider;
use App\Services\Contracts\PaymentGateway;
use App\Services\Delivery\Carriers\DelhiveryCarrier;
use App\Services\Delivery\Carriers\OlaCarrier;
use App\Services\Delivery\Carriers\PorterCarrier;
use App\Services\Delivery\Carriers\RapidoCarrier;
use App\Services\Delivery\Carriers\ShiprocketCarrier;
use App\Services\Delivery\CarrierRegistry;
use App\Services\Delivery\DeliveryAllocator;
use App\Services\Delivery\MultiCarrierLogistics;
use App\Services\Payments\PaymentGatewayManager;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Console\Events\CommandStarting;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // One instance per request: it remembers the environment's own values so
        // that clearing an admin-set value can put them back.
        $this->app->singleton(\App\Integrations\IntegrationSettings::class);

        // Every gateway named in config/payments.php whose credentials are
        // present, plus the sandbox (offered only while none is configured).
        // Nothing outside this manager knows which gateways exist.
        $this->app->singleton(PaymentGatewayManager::class, function () {
            $gateways = array_filter(array_map(
                fn (string $class) => $class::fromConfig(),
                config('payments.gateways', []),
            ));

            // The sandbox gateway approves every payment without moving money, so
            // outside local/testing it must be switched on deliberately.
            $allowSandbox = config('payments.allow_sandbox') ?? ! app()->isProduction();

            return new PaymentGatewayManager($gateways, config('payments.default'), (bool) $allowSandbox);
        });

        // Code that only wants "a gateway for a new payment" can still ask for
        // the contract; refunds must not — they go through the payment's own.
        $this->app->bind(PaymentGateway::class, fn ($app) => $app->make(PaymentGatewayManager::class)->default());

        $this->registerDeliveryCarriers();
        $this->app->singleton(\App\Services\Contracts\SearchEngine::class, \App\Services\PostgresSearchEngine::class);

        // Bulk-import parser: use the LLM driver when a key is configured,
        // otherwise the heuristic one. GeminiProductParser also falls back to
        // heuristic at runtime if a call fails, so import never hard-stops.
        $this->app->singleton(\App\Services\Contracts\ProductParser::class, function () {
            return filled(config('services.gemini.key'))
                ? new \App\Services\Import\GeminiProductParser()
                : new \App\Services\Import\HeuristicProductParser();
        });
        $this->app->singleton(\App\Services\AIService::class, function ($app) {
            return new \App\Services\AIService();
        });
    }

    /**
     * Delivery partners, the registry that holds them, and the allocator that
     * chooses between them.
     *
     * Which partners are live is a config question (`DELIVERY_CARRIERS`), so
     * signing a new courier is an env change plus one adapter class — nothing
     * in the controllers or the clients moves. Every adapter runs in sandbox
     * until its credentials are present, and says so in every response.
     */
    protected function registerDeliveryCarriers(): void
    {
        $this->app->singleton(CarrierRegistry::class, fn () => new CarrierRegistry([
            new RapidoCarrier(),
            new OlaCarrier(),
            new PorterCarrier(),
            new ShiprocketCarrier(),
            new DelhiveryCarrier(),
        ]));

        $this->app->singleton(
            DeliveryAllocator::class,
            fn ($app) => new DeliveryAllocator($app->make(CarrierRegistry::class)),
        );

        // The pre-existing single-courier interface now resolves to the
        // multi-carrier implementation, so the order/return/serviceability
        // controllers gain carrier selection without being rewritten.
        $this->app->singleton(LogisticsProvider::class, fn ($app) => new MultiCarrierLogistics(
            $app->make(CarrierRegistry::class),
            $app->make(DeliveryAllocator::class),
        ));
    }

    public function boot(): void
    {
        $this->registerRateLimiters();
        $this->applyIntegrationSettingsInConsole();
    }

    /**
     * Console processes (the scheduler, and the commands it runs) send email and
     * touch storage too, so they need the admin-managed settings as much as web
     * requests do — otherwise a back-in-stock email would go out through the
     * .env mailer while the admin panel says something else.
     *
     * Skipped for the commands that write config to disk or run before the settings
     * table exists (IntegrationSettings::NEVER_APPLY_COMMANDS): applying before
     * `config:cache` would bake decrypted secrets into the cached file.
     */
    protected function applyIntegrationSettingsInConsole(): void
    {
        Event::listen(CommandStarting::class, function (CommandStarting $event) {
            if ($event->command === null || in_array($event->command, \App\Integrations\IntegrationSettings::NEVER_APPLY_COMMANDS, true)) {
                return;
            }

            try {
                app(\App\Integrations\IntegrationSettings::class)->apply();
            } catch (\Throwable $e) {
                // Same rule as the web middleware: never stop the command.
                Log::warning('[Integrations] settings not applied; using the environment', ['reason' => $e::class]);
            }
        });
    }

    /**
     * Named rate limiters, applied in routes/api.php.
     *
     * Credential and OTP endpoints are limited on two keys at once: a per-identity
     * key (email / phone) so one account can't be ground down from a botnet, and a
     * per-IP key so one host can't sweep many identities. Laravel applies every
     * Limit in the returned array, so whichever trips first wins.
     */
    protected function registerRateLimiters(): void
    {
        RateLimiter::for('login', fn (Request $request) => [
            Limit::perMinute(5)->by('login:' . strtolower((string) $request->input('email')) . '|' . $request->ip()),
            Limit::perHour(30)->by('login-ip:' . $request->ip()),
        ]);

        RateLimiter::for('register', fn (Request $request) => [
            Limit::perHour(10)->by('register-ip:' . $request->ip()),
        ]);

        // An OTP is 6 digits with a 5-minute life and no attempt counter of its
        // own, so the throttle is the only thing standing between an attacker and
        // a full sweep of the code space. Verify is deliberately tighter than send.
        RateLimiter::for('otp-send', fn (Request $request) => [
            Limit::perMinutes(5, 3)->by('otp-send:' . $request->input('phone')),
            Limit::perHour(20)->by('otp-send-ip:' . $request->ip()),
        ]);

        RateLimiter::for('otp-verify', fn (Request $request) => [
            Limit::perMinutes(5, 5)->by('otp-verify:' . $request->input('phone')),
            Limit::perHour(30)->by('otp-verify-ip:' . $request->ip()),
        ]);

        // Blanket ceiling for everything else — generous enough that normal
        // browsing never sees it, low enough to blunt scraping and abuse.
        RateLimiter::for('api', fn (Request $request) => [
            Limit::perMinute(120)->by($request->user()?->id ?: $request->ip()),
        ]);

        // Changing integration credentials: a few deliberate edits at most. (Wrong
        // passwords are counted separately, and far more tightly, in the controller.)
        RateLimiter::for('integrations-write', fn (Request $request) => [
            Limit::perMinute(10)->by('integrations-write:'.($request->user()?->id ?: $request->ip())),
        ]);

        // Connection tests call a third party, so they are capped too.
        RateLimiter::for('integrations-test', fn (Request $request) => [
            Limit::perMinute(10)->by('integrations-test:'.($request->user()?->id ?: $request->ip())),
            Limit::perHour(60)->by('integrations-test-hour:'.($request->user()?->id ?: $request->ip())),
        ]);

        // Writes that cost money, storage or someone's inbox.
        RateLimiter::for('sensitive-write', fn (Request $request) => [
            Limit::perMinute(20)->by($request->user()?->id ?: $request->ip()),
        ]);
    }
}
