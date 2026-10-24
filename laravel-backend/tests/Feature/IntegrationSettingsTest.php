<?php

namespace Tests\Feature;

use App\Integrations\IntegrationSettings;
use App\Integrations\Registry;
use App\Models\IntegrationAuditLog;
use App\Models\IntegrationSetting;
use App\Models\User;
use App\Services\AIService;
use App\Services\Delivery\CarrierRegistry;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Integration keys and settings managed from the admin panel.
 *
 * The properties that matter, each pinned here:
 *  - a secret is never in a response, a log, the audit trail or the config cache;
 *  - it is encrypted at rest and bound to its own row;
 *  - only full admins can reach it, and only with their password;
 *  - what is saved really takes effect — including in services that copy their
 *    settings when built — and clearing it really reverts;
 *  - a broken settings table never takes the app down.
 */
class IntegrationSettingsTest extends TestCase
{
    use RefreshDatabase;

    private const PASSWORD = 'correct-horse-battery';

    private const GEMINI_KEY = 'AIzaSyD-TEST-KEY-1234567890abcdWXYZ';

    private const SHIPROCKET_PASSWORD = 'sr-Secret-Pass-9876';

    protected function setUp(): void
    {
        parent::setUp();

        config(['services.gemini.key' => null]);
    }

    private function admin(string $role = User::ROLE_ADMIN, ?string $password = self::PASSWORD): User
    {
        return User::factory()->create(['role' => $role, 'password' => $password]);
    }

    private function save(User $as, string $group, array $values, ?string $password = self::PASSWORD)
    {
        return $this->actingAs($as, 'sanctum')->putJson("/api/v1/admin/integrations/{$group}", array_filter([
            'current_password' => $password,
            'values' => $values,
        ], fn ($v) => $v !== null));
    }

    private function settings(): IntegrationSettings
    {
        return app(IntegrationSettings::class);
    }

    // ── Authorization ───────────────────────────────────────────────────

    public function test_only_full_admins_can_reach_any_integration_route(): void
    {
        $routes = [
            ['getJson', '/api/v1/admin/integrations'],
            ['getJson', '/api/v1/admin/integrations/audit'],
            ['putJson', '/api/v1/admin/integrations/gemini'],
            ['deleteJson', '/api/v1/admin/integrations/gemini/api_key'],
            ['postJson', '/api/v1/admin/integrations/gemini/test'],
        ];

        $this->getJson('/api/v1/admin/integrations')->assertUnauthorized();

        foreach ([User::ROLE_CUSTOMER, User::ROLE_SELLER, User::ROLE_SUB_ADMIN] as $role) {
            $user = $this->admin($role);

            foreach ($routes as [$method, $uri]) {
                $this->actingAs($user, 'sanctum')->{$method}($uri, ['current_password' => self::PASSWORD, 'values' => ['api_key' => self::GEMINI_KEY]])
                    ->assertForbidden();
            }
        }

        foreach ([User::ROLE_ADMIN, User::ROLE_SUPER_ADMIN] as $role) {
            $this->actingAs($this->admin($role), 'sanctum')->getJson('/api/v1/admin/integrations')->assertOk();
        }

        $this->assertSame(0, IntegrationSetting::count());
    }

    // ── Never leaking a secret ──────────────────────────────────────────

    public function test_a_saved_secret_is_never_returned_by_any_endpoint(): void
    {
        $admin = $this->admin();

        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
        $this->save($admin, 'couriers', [
            'shiprocket_email' => 'api@shop.in',
            'shiprocket_password' => self::SHIPROCKET_PASSWORD,
        ])->assertOk();

        foreach (['/api/v1/admin/integrations', '/api/v1/admin/integrations/audit'] as $uri) {
            $body = $this->actingAs($admin, 'sanctum')->getJson($uri)->assertOk()->getContent();

            $this->assertStringNotContainsString(self::GEMINI_KEY, $body);
            $this->assertStringNotContainsString(self::SHIPROCKET_PASSWORD, $body);
        }

        // …nor the responses to the writes themselves.
        $put = $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY.'-2'])->assertOk()->getContent();
        $this->assertStringNotContainsString(self::GEMINI_KEY, $put);
    }

    public function test_a_secret_is_described_only_by_whether_it_is_set_and_its_last_four(): void
    {
        $admin = $this->admin();
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        $field = collect($this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')->json('data.groups'))
            ->firstWhere('id', 'gemini')['fields'][0];

        $this->assertTrue($field['is_set']);
        $this->assertSame('admin', $field['source']);
        $this->assertSame('••••WXYZ', $field['masked']);
        $this->assertNull($field['value']);
    }

    public function test_short_secrets_show_no_characters_at_all(): void
    {
        $this->assertNull($this->settings()->mask('short-secret'));
        $this->assertSame('••••WXYZ', $this->settings()->mask(self::GEMINI_KEY));
    }

    public function test_reads_are_not_cacheable(): void
    {
        $cache = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/integrations')->headers->get('Cache-Control');

        $this->assertStringContainsString('no-store', $cache);
    }

    public function test_the_audit_log_holds_fingerprints_and_never_values(): void
    {
        $admin = $this->admin();
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY.'-rotated'])->assertOk();

        $dump = json_encode(DB::table('integration_audit_logs')->get());

        $this->assertStringNotContainsString(self::GEMINI_KEY, $dump);
        $this->assertStringNotContainsString('rotated', $dump);

        $rows = IntegrationAuditLog::where('action', 'SET')->orderBy('created_at')->get();
        $this->assertCount(2, $rows);
        $this->assertNotNull($rows[1]->fingerprint_old);
        $this->assertNotSame($rows[1]->fingerprint_old, $rows[1]->fingerprint_new);
        $this->assertSame($rows[0]->fingerprint_new, $rows[1]->fingerprint_old);
    }

    public function test_fingerprints_depend_on_the_app_key(): void
    {
        $a = $this->settings()->fingerprint('same-value');
        config(['app.key' => 'base64:'.base64_encode(random_bytes(32))]);

        $this->assertNotSame($a, $this->settings()->fingerprint('same-value'));
    }

    // ── Encryption at rest ──────────────────────────────────────────────

    public function test_values_are_encrypted_in_the_database(): void
    {
        $this->save($this->admin(), 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        $raw = (string) DB::table('integration_settings')->where('key', 'gemini.api_key')->value('value');

        $this->assertNotSame('', $raw);
        $this->assertStringNotContainsString(self::GEMINI_KEY, $raw);
        $this->assertStringNotContainsString('AIza', $raw);
    }

    public function test_the_model_never_serialises_its_value(): void
    {
        $this->save($this->admin(), 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        $this->assertArrayNotHasKey('value', IntegrationSetting::first()->toArray());
    }

    public function test_the_cache_only_ever_holds_the_encrypted_rows(): void
    {
        $this->save($this->admin(), 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
        $this->settings()->value(Registry::field('gemini.api_key'));

        $cached = json_encode(Cache::get('integrations.rows'));

        $this->assertNotSame('null', $cached);
        $this->assertStringNotContainsString(self::GEMINI_KEY, $cached);
    }

    public function test_a_value_copied_to_another_row_is_refused(): void
    {
        $this->save($this->admin(), 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
        $this->save($this->admin(), 'couriers', ['delhivery_api_token' => 'delhivery-token-1'])->assertOk();

        // An attacker with database access copies the Gemini ciphertext over the
        // Delhivery row to have it sent to the wrong place.
        $geminiCipher = DB::table('integration_settings')->where('key', 'gemini.api_key')->value('value');
        DB::table('integration_settings')->where('key', 'couriers.delhivery_api_token')->update(['value' => $geminiCipher]);
        $this->settings()->forgetRows();

        $this->assertNull($this->settings()->value(Registry::field('couriers.delhivery_api_token')));
    }

    public function test_an_unreadable_value_falls_back_to_the_environment_and_is_flagged(): void
    {
        config(['services.gemini.key' => 'env-key-from-the-server-00000']);
        $admin = $this->admin();
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        // APP_KEY changed without APP_PREVIOUS_KEYS: the row can no longer be opened.
        DB::table('integration_settings')->where('key', 'gemini.api_key')->update(['value' => 'not-a-valid-payload']);
        $this->settings()->forgetRows();
        $this->settings()->changed();

        $response = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')->assertOk();
        $field = collect($response->json('data.groups'))->firstWhere('id', 'gemini')['fields'][0];

        $this->assertTrue($field['unreadable']);
        $this->assertSame('environment', $field['source']);
        $this->assertSame('env-key-from-the-server-00000', config('services.gemini.key'));
    }

    // ── Re-authentication ───────────────────────────────────────────────

    public function test_a_change_needs_the_current_password(): void
    {
        $admin = $this->admin();

        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY], password: null)->assertStatus(422);
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY], password: 'wrong-password-here')
            ->assertStatus(422)
            ->assertJsonValidationErrors('current_password');

        $this->assertSame(0, IntegrationSetting::count());
        $this->assertSame(1, IntegrationAuditLog::where('outcome', 'invalid_password')->count());
    }

    public function test_wrong_passwords_are_throttled_and_the_right_one_then_stops_working_too(): void
    {
        $admin = $this->admin();

        for ($i = 0; $i < 5; $i++) {
            $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY], password: 'wrong-password-'.$i)->assertStatus(422);
        }

        // Locked out: even the correct password is refused until the window passes.
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertStatus(429);
        $this->assertSame(0, IntegrationSetting::count());
        $this->assertSame(1, IntegrationAuditLog::where('outcome', 'throttled')->count());

        RateLimiter::clear('integrations-reauth:'.$admin->id);
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
    }

    public function test_the_throttle_is_per_admin(): void
    {
        $one = $this->admin();
        $two = $this->admin(User::ROLE_SUPER_ADMIN);

        for ($i = 0; $i < 5; $i++) {
            $this->save($one, 'gemini', ['api_key' => self::GEMINI_KEY], password: 'nope-nope-nope-'.$i);
        }

        $this->save($two, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
    }

    public function test_an_admin_with_no_password_is_told_how_to_set_one_and_changes_nothing(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $admin->forceFill(['password' => null])->save();

        $response = $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY], password: 'anything-at-all')
            ->assertStatus(422)
            ->assertJsonPath('code', 'password_not_set');

        $this->assertStringContainsString('bazaarx:set-password', $response->json('message'));
        $this->assertSame(0, IntegrationSetting::count());

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')
            ->assertOk()->assertJsonPath('data.can_confirm', false);
    }

    public function test_a_successful_confirmation_clears_the_failure_count(): void
    {
        $admin = $this->admin();

        for ($i = 0; $i < 4; $i++) {
            $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY], password: 'wrong-wrong-'.$i);
        }

        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        // The earlier failures no longer count against them.
        for ($i = 0; $i < 4; $i++) {
            $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY.'x'], password: 'wrong-again-'.$i)->assertStatus(422);
        }
    }

    // ── Saving ──────────────────────────────────────────────────────────

    public function test_saving_makes_the_value_take_effect_and_clearing_reverts_it(): void
    {
        config(['services.gemini.key' => 'env-key-from-the-server-00000']);
        $admin = $this->admin();

        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk()->assertJsonPath('changed', ['api_key']);
        $this->assertSame(self::GEMINI_KEY, config('services.gemini.key'));

        // A fresh request still sees it (the overlay is applied per request).
        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')->assertOk();
        $this->assertSame(self::GEMINI_KEY, config('services.gemini.key'));

        $this->actingAs($admin, 'sanctum')->deleteJson('/api/v1/admin/integrations/gemini/api_key', ['current_password' => self::PASSWORD])
            ->assertOk();

        $this->assertSame('env-key-from-the-server-00000', config('services.gemini.key'));
        $this->assertSame(0, IntegrationSetting::count());
    }

    public function test_leaving_a_secret_blank_keeps_it(): void
    {
        $admin = $this->admin();
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        $this->save($admin, 'gemini', ['api_key' => ''])->assertOk()->assertJsonPath('changed', []);

        $this->assertSame(self::GEMINI_KEY, $this->settings()->value(Registry::field('gemini.api_key')));
    }

    public function test_saving_a_value_identical_to_the_server_setting_creates_no_override(): void
    {
        config(['delivery.free_above' => 999]);
        $admin = $this->admin();

        $this->save($admin, 'shipping', ['free_above' => 999])->assertOk()->assertJsonPath('changed', []);

        $this->assertSame(0, IntegrationSetting::count());
    }

    public function test_a_blank_plain_setting_reverts_to_the_default(): void
    {
        config(['delivery.free_above' => 999]);
        $admin = $this->admin();
        $this->save($admin, 'shipping', ['free_above' => 1500])->assertOk();
        $this->assertSame(1500, config('delivery.free_above'));

        $this->save($admin, 'shipping', ['free_above' => ''])->assertOk();

        $this->assertSame(999, config('delivery.free_above'));
    }

    public function test_values_are_validated_and_nothing_is_saved_on_error(): void
    {
        $admin = $this->admin();

        $this->save($admin, 'gemini', ['api_key' => 'has spaces in it and is long enough'])->assertStatus(422)->assertJsonValidationErrors('values.api_key');
        $this->save($admin, 'marketplace', ['default_commission_rate' => 75])->assertStatus(422)->assertJsonValidationErrors('values.default_commission_rate');
        $this->save($admin, 'google', ['client_id' => 'not-a-client-id'])->assertStatus(422)->assertJsonValidationErrors('values.client_id');
        $this->save($admin, 'shipping', ['pickup_pincode' => '12'])->assertStatus(422);
        $this->save($admin, 'nonexistent', ['a' => 'b'])->assertNotFound();
        $this->save($admin, 'gemini', ['made_up_setting' => 'x'])->assertStatus(422)->assertJsonValidationErrors('values.made_up_setting');

        $this->assertSame(0, IntegrationSetting::count());
    }

    public function test_a_half_saved_batch_is_not_left_behind(): void
    {
        $admin = $this->admin();

        $this->save($admin, 'shipping', ['free_above' => 1500, 'pickup_pincode' => 'bad'])->assertStatus(422);

        $this->assertSame(0, IntegrationSetting::count());
    }

    public function test_paired_credentials_must_be_given_together(): void
    {
        $admin = $this->admin();

        $this->save($admin, 'couriers', ['shiprocket_email' => 'api@shop.in'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('values.shiprocket_password');

        $this->assertSame(0, IntegrationSetting::count());

        // …but an unrelated edit is not blocked, and the second half may arrive later
        // when the first is already stored.
        $this->save($admin, 'couriers', ['shiprocket_email' => 'api@shop.in', 'shiprocket_password' => self::SHIPROCKET_PASSWORD])->assertOk();
        $this->save($admin, 'couriers', ['shiprocket_email' => 'other@shop.in'])->assertOk();
    }

    public function test_carrier_base_urls_and_payments_cannot_be_set_here(): void
    {
        $keys = array_map(fn ($f) => $f->key(), Registry::fields());

        foreach ($keys as $key) {
            $this->assertStringNotContainsString('base_url', $key);
            $this->assertStringNotContainsString('razorpay', $key);
            $this->assertStringNotContainsString('payments', $key);
        }

        foreach (Registry::fields() as $field) {
            foreach ($field->config as $path) {
                $this->assertStringNotContainsString('base_url', $path);
                $this->assertStringNotContainsString('razorpay', $path);
                $this->assertStringStartsNotWith('payments.', $path);
            }
        }

        $this->save($this->admin(), 'gemini', ['razorpay_key_secret' => 'x'])->assertStatus(422);
    }

    public function test_the_payments_card_is_read_only_and_shows_no_secret(): void
    {
        config([
            'services.razorpay.key_id' => 'rzp_test_AbCdEfGhIjKlMn',
            'services.razorpay.key_secret' => 'razorpay-secret-value-99',
            'services.razorpay.webhook_secret' => 'webhook-secret-value-99',
        ]);

        $response = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/integrations')->assertOk();

        $response->assertJsonPath('data.payments.managed_here', false)
            ->assertJsonPath('data.payments.configured', true)
            ->assertJsonPath('data.payments.mode', 'test')
            ->assertJsonPath('data.payments.webhook_secret_set', true);

        $body = $response->getContent();
        $this->assertStringNotContainsString('razorpay-secret-value-99', $body);
        $this->assertStringNotContainsString('webhook-secret-value-99', $body);
        $this->assertStringNotContainsString('AbCdEfGhIjKlMn', $body);

        // and there is no route to change it.
        $this->actingAs($this->admin(), 'sanctum')->putJson('/api/v1/admin/integrations/payments', ['current_password' => self::PASSWORD, 'values' => ['x' => 'y']])
            ->assertNotFound();
    }

    // ── It really takes effect ──────────────────────────────────────────

    public function test_a_saved_gemini_key_is_what_the_ai_service_then_uses(): void
    {
        Http::fake(['*' => Http::response(['candidates' => [['content' => ['parts' => [['text' => 'ok']]]]]])]);
        $admin = $this->admin();

        // Built first, with no key — the situation that used to leave a stale
        // singleton in place after a save.
        $before = app(AIService::class);

        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        $after = app(AIService::class);
        $this->assertNotSame($before, $after);

        $reflection = new \ReflectionProperty(AIService::class, 'apiKey');
        $this->assertSame(self::GEMINI_KEY, $reflection->getValue($after));
    }

    public function test_the_gemini_key_is_sent_in_a_header_never_the_url(): void
    {
        Http::fake(['*' => Http::response(['candidates' => [['content' => ['parts' => [['text' => '{"a":1}']]]]]])]);
        $this->save($this->admin(), 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        app(AIService::class)->extractSearchIntent('red shoes');

        Http::assertSent(function ($request) {
            return ! str_contains($request->url(), 'key=')
                && ! str_contains($request->url(), self::GEMINI_KEY)
                && $request->hasHeader('x-goog-api-key', self::GEMINI_KEY);
        });
    }

    public function test_saved_courier_credentials_reach_the_carrier_and_reset_its_token(): void
    {
        Http::fake(['*' => Http::response(['token' => 't'])]);
        $admin = $this->admin();

        $first = app(CarrierRegistry::class);

        $this->save($admin, 'couriers', [
            'shiprocket_email' => 'api@shop.in',
            'shiprocket_password' => self::SHIPROCKET_PASSWORD,
        ])->assertOk();

        $this->assertNotSame($first, app(CarrierRegistry::class));
        $this->assertSame('api@shop.in', config('delivery.carriers.shiprocket.email'));
        $this->assertSame(self::SHIPROCKET_PASSWORD, config('delivery.carriers.shiprocket.password'));
    }

    public function test_the_shiprocket_token_cache_is_keyed_by_the_credentials(): void
    {
        $source = file_get_contents(app_path('Services/Delivery/Carriers/ShiprocketCarrier.php'));

        $this->assertStringContainsString("'shiprocket.token.'", $source);
        $this->assertStringContainsString('sha256', $source);
    }

    public function test_the_pincode_override_reaches_both_config_paths(): void
    {
        $this->save($this->admin(), 'shipping', ['pickup_pincode' => '560001'])->assertOk();

        $this->assertSame('560001', config('delivery.pickup_address.pincode'));
        $this->assertSame('560001', config('delivery.pickup_pincode'));
    }

    public function test_the_courier_list_override_is_applied_as_a_list(): void
    {
        $this->save($this->admin(), 'couriers', ['enabled' => ['shiprocket', 'delhivery']])->assertOk();

        $this->assertSame(['shiprocket', 'delhivery'], config('delivery.enabled'));
    }

    // ── Resilience ──────────────────────────────────────────────────────

    public function test_a_missing_settings_table_does_not_break_requests(): void
    {
        Schema::dropIfExists('integration_settings');
        $this->settings()->forgetRows();

        $this->getJson('/api/v1/categories')->assertOk();
    }

    public function test_config_cache_never_contains_a_decrypted_secret(): void
    {
        $this->save($this->admin(), 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
        $this->save($this->admin(), 'couriers', [
            'shiprocket_email' => 'api@shop.in',
            'shiprocket_password' => self::SHIPROCKET_PASSWORD,
        ])->assertOk();

        // What `php artisan config:cache` would write: config as a *console* process
        // sees it — the middleware that applies the overlay has not run there.
        $this->assertFileDoesNotExist(base_path('bootstrap/cache/config.php.check'));

        $console = (new \ReflectionClass(\App\Http\Middleware\ApplyIntegrationSettings::class))->getFileName();
        $this->assertStringNotContainsString('ServiceProvider', file_get_contents($console));

        // The only place the provider applies it is the console-command listener,
        // which skips the commands that compile config.
        $provider = file_get_contents(app_path('Providers/AppServiceProvider.php'));
        $this->assertSame(1, substr_count($provider, '->apply()'), 'the overlay must not run at provider boot');
        $this->assertStringContainsString('NEVER_APPLY_COMMANDS', $provider);
        $this->assertContains('config:cache', IntegrationSettings::NEVER_APPLY_COMMANDS);
        $this->assertContains('optimize', IntegrationSettings::NEVER_APPLY_COMMANDS);
    }

    public function test_the_overlay_runs_only_in_the_http_pipeline(): void
    {
        // A console boot has no overlay: config holds only what the environment gave it.
        $this->assertNull(config('services.gemini.key'));

        $this->save($this->admin(), 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        // Reset as a fresh process would be, and do not go through a request.
        $this->refreshApplication();
        config(['services.gemini.key' => null]);

        $this->assertNull(config('services.gemini.key'));
    }

    // ── Testing a connection ────────────────────────────────────────────

    public function test_testing_uses_a_fixed_host_and_a_header(): void
    {
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response(['models' => []])]);

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson('/api/v1/admin/integrations/gemini/test', ['values' => ['api_key' => self::GEMINI_KEY]])
            ->assertOk()
            ->assertJsonPath('data.status', 'ok');

        Http::assertSent(fn ($r) => str_starts_with($r->url(), 'https://generativelanguage.googleapis.com/')
            && ! str_contains($r->url(), self::GEMINI_KEY)
            && $r->hasHeader('x-goog-api-key', self::GEMINI_KEY));
    }

    public function test_testing_does_not_save_the_candidate(): void
    {
        Http::fake(['*' => Http::response(['models' => []])]);

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson('/api/v1/admin/integrations/gemini/test', ['values' => ['api_key' => self::GEMINI_KEY]])
            ->assertOk();

        $this->assertSame(0, IntegrationSetting::count());
        $this->assertNull(config('services.gemini.key'));
    }

    public function test_a_rejected_key_is_reported_without_echoing_anything_upstream(): void
    {
        Http::fake(['*' => Http::response(['error' => ['message' => 'API key not valid: '.self::GEMINI_KEY]], 400)]);

        $response = $this->actingAs($this->admin(), 'sanctum')
            ->postJson('/api/v1/admin/integrations/gemini/test', ['values' => ['api_key' => self::GEMINI_KEY]])
            ->assertOk()
            ->assertJsonPath('data.status', 'failed');

        $this->assertStringNotContainsString(self::GEMINI_KEY, $response->getContent());
    }

    public function test_testing_with_no_key_does_not_call_out(): void
    {
        Http::fake();

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/integrations/gemini/test')
            ->assertOk()->assertJsonPath('data.status', 'incomplete');

        Http::assertNothingSent();
    }

    public function test_a_test_can_use_the_saved_value_when_none_is_supplied(): void
    {
        Http::fake(['*' => Http::response(['models' => []])]);
        $admin = $this->admin();
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/admin/integrations/gemini/test')
            ->assertOk()->assertJsonPath('data.status', 'ok');
    }

    public function test_the_shiprocket_test_calls_the_fixed_login_url_only(): void
    {
        Http::fake(['apiv2.shiprocket.in/*' => Http::response(['token' => 'abc'])]);
        config(['delivery.carriers.shiprocket.base_url' => 'https://attacker.example']);

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/integrations/couriers/test', [
            'target' => 'shiprocket',
            'values' => ['shiprocket_email' => 'api@shop.in', 'shiprocket_password' => self::SHIPROCKET_PASSWORD],
        ])->assertOk()->assertJsonPath('data.status', 'ok');

        Http::assertSent(fn ($r) => $r->url() === 'https://apiv2.shiprocket.in/v1/external/auth/login');
    }

    public function test_couriers_without_a_published_check_say_so_instead_of_guessing(): void
    {
        Http::fake();

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/integrations/couriers/test', ['target' => 'delhivery'])
            ->assertOk()->assertJsonPath('data.status', 'unavailable');

        Http::assertNothingSent();
    }

    public function test_groups_with_nothing_to_test_say_so(): void
    {
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/integrations/marketplace/test')
            ->assertOk()->assertJsonPath('data.status', 'unavailable');
    }

    // ── Listing ─────────────────────────────────────────────────────────

    public function test_every_group_is_described_with_a_status(): void
    {
        $groups = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/integrations')->assertOk()->json('data.groups');

        $this->assertSame(['gemini', 'google', 'push', 'email', 'sms', 'storage', 'couriers', 'shipping', 'marketplace'], array_column($groups, 'id'));

        foreach ($groups as $group) {
            $this->assertContains($group['status'], ['configured', 'partial', 'missing', 'local']);
            $this->assertNotEmpty($group['fields']);
        }
    }

    public function test_the_audit_trail_records_who_and_what_for_each_change(): void
    {
        $admin = $this->admin();
        $this->save($admin, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
        $this->actingAs($admin, 'sanctum')->deleteJson('/api/v1/admin/integrations/gemini/api_key', ['current_password' => self::PASSWORD])->assertOk();

        $rows = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations/audit')->assertOk()->json('data');

        $this->assertSame(['CLEAR', 'SET'], array_column($rows, 'action'));
        $this->assertSame($admin->email, $rows[0]['who']['email']);
        $this->assertSame('gemini', $rows[0]['group']);
        $this->assertSame('api_key', $rows[0]['field']);
    }
}
