<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * What the owner sets in Settings reaches the website and the app, but only the part
 * that is public by nature (a Google client id). Anything secret stays server-side:
 * these tests save real-looking secrets and look for them in everything a stranger
 * can fetch.
 */
class SettingsExposureTest extends TestCase
{
    use RefreshDatabase;

    private const PASSWORD = 'correct-horse-battery';

    private const WEB_ID = '1234567890-webclientabc.apps.googleusercontent.com';

    private const ANDROID_ID = '1234567890-androidclientxyz.apps.googleusercontent.com';

    private const GEMINI_KEY = 'AIzaSyD-SENTINEL-KEY-1234567890abcdWXYZ';

    private const SHIPROCKET_PASSWORD = 'sr-SENTINEL-Pass-9876';

    private function owner(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'password' => self::PASSWORD]);
    }

    private function save(User $as, string $group, array $values)
    {
        return $this->actingAs($as, 'sanctum')->putJson("/api/v1/admin/integrations/{$group}", [
            'current_password' => self::PASSWORD,
            'values' => $values,
        ]);
    }

    public function test_the_google_client_ids_set_in_settings_reach_the_apps_without_a_rebuild(): void
    {
        $this->save($this->owner(), 'google', [
            'client_id' => self::WEB_ID,
            'android_client_id' => self::ANDROID_ID,
        ])->assertOk();

        $this->app['auth']->forgetGuards();

        $config = $this->getJson('/api/v1/config')->assertOk();

        $config->assertJsonPath('data.google_web_client_id', self::WEB_ID);
        $config->assertJsonPath('data.google_server_client_id', self::WEB_ID);
    }

    public function test_a_store_with_no_google_setup_says_so(): void
    {
        config(['services.google.client_id' => null, 'services.google.web_client_id' => null]);

        $this->getJson('/api/v1/config')->assertOk()
            ->assertJsonPath('data.google_web_client_id', null)
            ->assertJsonPath('data.google_server_client_id', null);
    }

    public function test_a_badly_formed_client_id_is_refused(): void
    {
        $this->save($this->owner(), 'google', ['client_id' => '"><script>alert(1)</script>'])
            ->assertStatus(422);

        $this->save($this->owner(), 'google', ['client_id' => 'https://evil.example/not-an-id'])
            ->assertStatus(422);
    }

    public function test_no_secret_saved_in_settings_is_in_anything_a_stranger_can_fetch(): void
    {
        $owner = $this->owner();
        $this->save($owner, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();
        $this->save($owner, 'couriers', [
            'shiprocket_email' => 'api@shop.in',
            'shiprocket_password' => self::SHIPROCKET_PASSWORD,
        ])->assertOk();
        $this->save($owner, 'google', ['client_id' => self::WEB_ID])->assertOk();

        // A visitor with no account, then a shopper.
        $this->app['auth']->forgetGuards();
        $shopper = User::factory()->create(['role' => User::ROLE_CUSTOMER, 'status' => 'ACTIVE']);

        foreach (['/api/v1/config', '/api/v1/theme', '/api/v1/settings', '/api/v1/products', '/api/v1/categories', '/api/v1/storefront'] as $uri) {
            $this->assertNoSecrets($this->getJson($uri)->getContent(), "guest {$uri}");
            $this->assertNoSecrets($this->actingAs($shopper, 'sanctum')->getJson($uri)->getContent(), "shopper {$uri}");
        }
    }

    public function test_only_a_full_admin_can_read_the_settings_screen_and_it_still_hides_secrets(): void
    {
        $owner = $this->owner();
        $this->save($owner, 'gemini', ['api_key' => self::GEMINI_KEY])->assertOk();

        $subAdmin = User::factory()->create(['role' => User::ROLE_SUB_ADMIN, 'password' => self::PASSWORD]);
        $shopper = User::factory()->create(['role' => User::ROLE_CUSTOMER, 'password' => self::PASSWORD]);

        $this->actingAs($subAdmin, 'sanctum')->getJson('/api/v1/admin/integrations')->assertForbidden();
        $this->actingAs($shopper, 'sanctum')->getJson('/api/v1/admin/integrations')->assertForbidden();

        $body = $this->actingAs($owner, 'sanctum')->getJson('/api/v1/admin/integrations')->assertOk()->getContent();
        $this->assertStringNotContainsString(self::GEMINI_KEY, $body);
    }

    private function assertNoSecrets(string $body, string $where): void
    {
        foreach ([self::GEMINI_KEY, self::SHIPROCKET_PASSWORD, 'SENTINEL'] as $secret) {
            $this->assertStringNotContainsString($secret, $body, "a secret appeared in {$where}");
        }
    }
}
