<?php

namespace Tests\Feature;

use App\Models\DeviceToken;
use App\Models\Order;
use App\Models\User;
use App\Services\NotificationService;
use App\Services\Push\FcmClient;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Push is an extra channel on top of the stored in-app notification: it must
 * switch itself on only when Firebase credentials exist, never fail the caller,
 * and clean up tokens Google says are dead.
 */
class PushNotificationTest extends TestCase
{
    use RefreshDatabase;

    private const TOKEN = 'dGVzdC1kZXZpY2UtdG9rZW4tMDAwMDAwMDAwMDAwMDAwMA';

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    /** A real RSA key, generated per run, so signing is exercised for real. */
    private function serviceAccountJson(): string
    {
        $key = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);

        if ($key === false) {
            // Some Windows PHP builds ship without an openssl.cnf on their search
            // path; set OPENSSL_CONF to run these locally.
            $this->markTestSkipped('OpenSSL cannot generate a key here: '.openssl_error_string());
        }

        openssl_pkey_export($key, $pem);

        return json_encode([
            'type' => 'service_account',
            'project_id' => 'demo-shop',
            'client_email' => 'push@demo-shop.iam.gserviceaccount.com',
            'private_key' => $pem,
        ]);
    }

    private function enablePush(): void
    {
        config(['services.fcm.service_account' => $this->serviceAccountJson()]);
        Cache::flush();
        // The container may already have built the client without credentials.
        $this->app->forgetInstance(FcmClient::class);
        $this->app->forgetInstance(\App\Services\Push\PushService::class);
    }

    private function fakeGoogle(int $sendStatus = 200, array $sendBody = ['name' => 'projects/demo-shop/messages/1']): void
    {
        Http::fake([
            'oauth2.googleapis.com/*' => Http::response(['access_token' => 'ya29.test', 'expires_in' => 3600]),
            'fcm.googleapis.com/*' => Http::response($sendBody, $sendStatus),
        ]);
    }

    // ── Registration ────────────────────────────────────────────────────

    public function test_a_signed_in_user_can_register_a_device(): void
    {
        $user = $this->customer();

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/v1/devices', ['token' => self::TOKEN, 'platform' => 'android', 'app_version' => '1.2.0'])
            ->assertCreated();

        $this->assertDatabaseHas('device_tokens', ['user_id' => $user->id, 'token' => self::TOKEN]);
    }

    public function test_registering_requires_a_session(): void
    {
        $this->postJson('/api/v1/devices', ['token' => self::TOKEN])->assertUnauthorized();
    }

    public function test_the_same_phone_moves_to_whoever_signs_in_next(): void
    {
        $first = $this->customer();
        $second = $this->customer();

        $this->actingAs($first, 'sanctum')->postJson('/api/v1/devices', ['token' => self::TOKEN])->assertCreated();
        $this->actingAs($second, 'sanctum')->postJson('/api/v1/devices', ['token' => self::TOKEN])->assertCreated();

        $this->assertSame(1, DeviceToken::where('token', self::TOKEN)->count());
        $this->assertSame($second->id, DeviceToken::where('token', self::TOKEN)->value('user_id'));
    }

    public function test_a_device_can_be_removed_only_by_its_owner(): void
    {
        $owner = $this->customer();
        $other = $this->customer();
        DeviceToken::create(['user_id' => $owner->id, 'token' => self::TOKEN, 'platform' => 'android']);

        $this->actingAs($other, 'sanctum')->deleteJson('/api/v1/devices', ['token' => self::TOKEN])->assertOk();
        $this->assertDatabaseHas('device_tokens', ['token' => self::TOKEN]);

        $this->actingAs($owner, 'sanctum')->deleteJson('/api/v1/devices', ['token' => self::TOKEN])->assertOk();
        $this->assertDatabaseMissing('device_tokens', ['token' => self::TOKEN]);
    }

    // ── Delivery ────────────────────────────────────────────────────────

    public function test_nothing_is_sent_while_push_is_not_configured(): void
    {
        Http::fake();
        $user = $this->customer();
        DeviceToken::create(['user_id' => $user->id, 'token' => self::TOKEN, 'platform' => 'android']);

        app(NotificationService::class)->send($user, 'ORDER_UPDATE', 'Shipped', 'On its way');

        Http::assertNothingSent();
        // The in-app notification is still stored.
        $this->assertDatabaseHas('app_notifications', ['user_id' => $user->id, 'title' => 'Shipped']);
    }

    public function test_a_notification_is_pushed_to_each_of_the_users_devices(): void
    {
        $this->enablePush();
        $this->fakeGoogle();
        $user = $this->customer();
        DeviceToken::create(['user_id' => $user->id, 'token' => self::TOKEN, 'platform' => 'android']);
        DeviceToken::create(['user_id' => $user->id, 'token' => self::TOKEN.'2', 'platform' => 'android']);

        $delivered = app(\App\Services\Push\PushService::class)
            ->notify($user, 'Order shipped', 'Arriving Friday', ['order_id' => 'abc', 'count' => 3]);

        $this->assertSame(2, $delivered);

        Http::assertSent(fn ($request) => str_contains($request->url(), 'projects/demo-shop/messages:send')
            && $request['message']['notification']['title'] === 'Order shipped'
            && $request['message']['data']['order_id'] === 'abc'
            // FCM only accepts string values in `data`.
            && $request['message']['data']['count'] === '3'
            && $request->hasHeader('Authorization', 'Bearer ya29.test'));
    }

    public function test_a_notification_sent_through_the_service_triggers_a_push(): void
    {
        $this->enablePush();
        $this->fakeGoogle();
        $user = $this->customer();
        DeviceToken::create(['user_id' => $user->id, 'token' => self::TOKEN, 'platform' => 'android']);

        app(NotificationService::class)->send($user, 'ORDER_UPDATE', 'Confirmed', 'Thanks', ['order_id' => 'o-1']);

        // defer() runs once the response has been sent; in a test, flush it.
        \Illuminate\Support\defer()->invoke();

        Http::assertSent(fn ($request) => str_contains($request->url(), 'messages:send')
            && $request['message']['data']['type'] === 'ORDER_UPDATE');
    }

    public function test_a_user_who_opted_out_of_the_type_gets_no_push(): void
    {
        $this->enablePush();
        $this->fakeGoogle();
        $user = $this->customer();
        $user->update(['notification_preferences' => ['PROMO' => false]]);
        DeviceToken::create(['user_id' => $user->id, 'token' => self::TOKEN, 'platform' => 'android']);

        app(NotificationService::class)->send($user, 'PROMO', 'Sale', 'Everything 50% off');
        \Illuminate\Support\defer()->invoke();

        Http::assertNotSent(fn ($request) => str_contains($request->url(), 'messages:send'));
    }

    public function test_a_token_google_reports_as_dead_is_removed(): void
    {
        $this->enablePush();
        $this->fakeGoogle(404, ['error' => ['status' => 'NOT_FOUND', 'message' => 'Requested entity was not found.']]);
        $user = $this->customer();
        DeviceToken::create(['user_id' => $user->id, 'token' => self::TOKEN, 'platform' => 'android']);

        $delivered = app(\App\Services\Push\PushService::class)->notify($user, 'Hello');

        $this->assertSame(0, $delivered);
        $this->assertDatabaseMissing('device_tokens', ['token' => self::TOKEN]);
    }

    public function test_a_server_error_keeps_the_token_for_next_time(): void
    {
        $this->enablePush();
        $this->fakeGoogle(500, ['error' => ['status' => 'INTERNAL']]);
        $user = $this->customer();
        DeviceToken::create(['user_id' => $user->id, 'token' => self::TOKEN, 'platform' => 'android']);

        app(\App\Services\Push\PushService::class)->notify($user, 'Hello');

        $this->assertDatabaseHas('device_tokens', ['token' => self::TOKEN]);
    }

    public function test_the_access_token_is_reused_between_sends(): void
    {
        $this->enablePush();
        $this->fakeGoogle();
        $user = $this->customer();
        DeviceToken::create(['user_id' => $user->id, 'token' => self::TOKEN, 'platform' => 'android']);

        $push = app(\App\Services\Push\PushService::class);
        $push->notify($user, 'One');
        $push->notify($user, 'Two');

        $tokenRequests = Http::recorded(fn ($request) => str_contains($request->url(), 'oauth2.googleapis.com'));
        $this->assertCount(1, $tokenRequests);
    }

    public function test_the_service_account_file_is_validated(): void
    {
        $this->assertNull(FcmClient::parseServiceAccount(''));
        $this->assertNull(FcmClient::parseServiceAccount('not json'));
        $this->assertNull(FcmClient::parseServiceAccount(json_encode(['project_id' => 'x'])));
        $this->assertNotNull(FcmClient::parseServiceAccount($this->serviceAccountJson()));
    }

    public function test_pasted_keys_with_escaped_line_breaks_are_repaired(): void
    {
        $json = json_decode($this->serviceAccountJson(), true);
        $json['private_key'] = str_replace("\n", '\\n', $json['private_key']);

        $parsed = FcmClient::parseServiceAccount(json_encode($json));

        $this->assertStringContainsString("\n", $parsed['private_key']);
        $this->assertNotFalse(openssl_pkey_get_private($parsed['private_key']));
    }

    // ── Admin: connecting Firebase ──────────────────────────────────────

    private function adminWithPassword(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'password' => 'a-long-admin-password-1']);
    }

    public function test_an_admin_can_save_the_service_account_and_it_is_stored_encrypted(): void
    {
        $json = $this->serviceAccountJson();

        $response = $this->actingAs($this->adminWithPassword(), 'sanctum')
            ->putJson('/api/v1/admin/integrations/push', [
                'current_password' => 'a-long-admin-password-1',
                'values' => ['service_account' => $json],
            ])->assertOk();

        // The private key is never sent back to the browser.
        $this->assertStringNotContainsString('PRIVATE KEY', $response->getContent());

        $stored = (string) \DB::table('integration_settings')->where('key', 'push.service_account')->value('value');
        $this->assertNotSame('', $stored);
        $this->assertStringNotContainsString('client_email', $stored);
        $this->assertStringNotContainsString('demo-shop', $stored);
    }

    public function test_something_that_is_not_a_service_account_is_refused(): void
    {
        $this->actingAs($this->adminWithPassword(), 'sanctum')
            ->putJson('/api/v1/admin/integrations/push', [
                'current_password' => 'a-long-admin-password-1',
                'values' => ['service_account' => '{"hello":"world"}'],
            ])->assertStatus(422);
    }

    public function test_the_connection_test_reports_when_google_accepts_the_account(): void
    {
        $this->fakeGoogle();

        $this->actingAs($this->adminWithPassword(), 'sanctum')
            ->postJson('/api/v1/admin/integrations/push/test', ['values' => ['service_account' => $this->serviceAccountJson()]])
            ->assertOk()
            ->assertJsonPath('data.status', 'ok');
    }

    public function test_the_connection_test_reports_when_google_rejects_the_account(): void
    {
        Http::fake(['oauth2.googleapis.com/*' => Http::response(['error' => 'invalid_grant'], 400)]);

        $this->actingAs($this->adminWithPassword(), 'sanctum')
            ->postJson('/api/v1/admin/integrations/push/test', ['values' => ['service_account' => $this->serviceAccountJson()]])
            ->assertOk()
            ->assertJsonPath('data.status', 'failed');
    }
}
