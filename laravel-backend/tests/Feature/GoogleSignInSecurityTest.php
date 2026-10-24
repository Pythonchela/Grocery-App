<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Google sign-in must never let a caller choose who they become.
 *
 * The regression this guards: a "demo" token (`demo_google_:<email>:<name>`) was
 * accepted in every environment and taken on trust, so anyone could sign in as
 * any account — the administrator's included — by naming its email.
 */
class GoogleSignInSecurityTest extends TestCase
{
    use RefreshDatabase;

    private function signIn(string $token): TestResponse
    {
        return $this->postJson('/api/v1/auth/google', ['id_token' => $token]);
    }

    private function demo(string $email, string $name = 'Someone'): string
    {
        return "demo_google_:{$email}:{$name}";
    }

    private function admin(string $role = 'ADMIN'): User
    {
        return User::factory()->create(['email' => 'boss@shop.test', 'role' => $role, 'status' => 'ACTIVE']);
    }

    private function inEnvironment(string $env): void
    {
        $this->app['env'] = $env;
    }

    // ── The hole: demo tokens outside a development machine ─────────────

    public function test_a_demo_token_cannot_sign_in_as_an_existing_admin_in_production(): void
    {
        $admin = $this->admin();
        $this->inEnvironment('production');

        $this->signIn($this->demo('boss@shop.test'))->assertStatus(422);

        $this->assertSame(0, $admin->tokens()->count(), 'no session was issued for the admin');
        $this->assertNull($admin->fresh()->google_id, 'nothing was attached to the admin');
    }

    public function test_a_demo_token_cannot_create_an_account_in_production(): void
    {
        $this->inEnvironment('production');

        $this->signIn($this->demo('stranger@example.com'))->assertStatus(422);

        $this->assertNull(User::where('email', 'stranger@example.com')->first());
    }

    public function test_the_alternative_mock_prefix_is_refused_too(): void
    {
        $this->admin();
        $this->inEnvironment('production');

        $this->signIn('mock_google_:boss@shop.test:X')->assertStatus(422);
    }

    public function test_staging_and_unknown_environments_are_safe_by_default(): void
    {
        $this->admin();

        foreach (['staging', 'production', 'prod', 'demo', ''] as $env) {
            $this->inEnvironment($env);
            $this->signIn($this->demo('boss@shop.test'))->assertStatus(422);
        }
    }

    public function test_a_demo_token_is_refused_even_when_google_is_configured(): void
    {
        $this->admin();
        $this->inEnvironment('production');
        config(['services.google.client_id' => 'abc.apps.googleusercontent.com']);
        Http::fake(['oauth2.googleapis.com/*' => Http::response(['error' => 'invalid_token'], 400)]);

        $this->signIn($this->demo('boss@shop.test'))->assertStatus(422);
    }

    public function test_the_refusal_does_not_say_which_emails_exist(): void
    {
        $this->admin();
        $this->inEnvironment('production');

        $existing = $this->signIn($this->demo('boss@shop.test'))->json('errors.id_token.0');
        $missing = $this->signIn($this->demo('nobody@shop.test'))->json('errors.id_token.0');

        $this->assertSame($existing, $missing);
    }

    // ── Development convenience still works where it is meant to ────────

    public function test_the_demo_token_still_works_on_a_development_machine(): void
    {
        foreach (['testing', 'local'] as $env) {
            $this->inEnvironment($env);
            $email = "dev-{$env}@example.com";

            $this->signIn($this->demo($email, 'Dev Shopper'))
                ->assertOk()
                ->assertJsonPath('data.user.email', $email);
        }
    }

    // ── Staff are never signed in, or linked, through Google ────────────

    public function test_a_demo_token_naming_an_admin_is_refused_even_in_development(): void
    {
        $admin = $this->admin();

        $this->signIn($this->demo('boss@shop.test'))->assertStatus(422)->assertJsonValidationErrors('email');

        $this->assertSame(0, $admin->tokens()->count());
        $this->assertNull($admin->fresh()->google_id, 'refused before anything was attached');
    }

    public function test_sub_admins_and_super_admins_are_protected_too(): void
    {
        foreach (['SUB_ADMIN', 'SUPER_ADMIN'] as $i => $role) {
            $user = User::factory()->create(['email' => "staff{$i}@shop.test", 'role' => $role, 'status' => 'ACTIVE']);

            $this->signIn($this->demo("staff{$i}@shop.test"))->assertStatus(422);
            $this->assertSame(0, $user->tokens()->count(), $role);
        }
    }

    public function test_a_real_google_identity_with_an_admins_email_does_not_sign_in_as_the_admin(): void
    {
        $admin = $this->admin();
        config(['services.google.client_id' => 'abc.apps.googleusercontent.com']);
        Http::fake(['oauth2.googleapis.com/*' => Http::response([
            'aud' => 'abc.apps.googleusercontent.com', 'iss' => 'https://accounts.google.com', 'exp' => time() + 600,
            'email' => 'boss@shop.test', 'email_verified' => 'true', 'sub' => 'real-google-sub-1', 'name' => 'Boss',
        ])]);
        $this->inEnvironment('production');

        $this->signIn('a-real-looking-token')->assertStatus(422)->assertJsonValidationErrors('email');

        $this->assertSame(0, $admin->tokens()->count());
        $this->assertNull($admin->fresh()->google_id);
    }

    public function test_an_admin_account_that_already_carries_a_google_id_cannot_use_it_to_sign_in(): void
    {
        // e.g. left behind by an earlier abuse of the demo token.
        $admin = $this->admin();
        $admin->forceFill(['google_id' => 'google_sub_leftover'])->save();
        config(['services.google.client_id' => 'abc.apps.googleusercontent.com']);
        Http::fake(['oauth2.googleapis.com/*' => Http::response([
            'aud' => 'abc.apps.googleusercontent.com', 'iss' => 'accounts.google.com', 'exp' => time() + 600,
            'email' => 'whoever@example.com', 'email_verified' => 'true', 'sub' => 'google_sub_leftover', 'name' => 'X',
        ])]);

        $this->signIn('a-real-looking-token')->assertStatus(422);

        $this->assertSame(0, $admin->tokens()->count());
    }

    // ── Ordinary Google sign-in keeps working ───────────────────────────

    private function fakeGoogleFor(string $email, string $sub = 'real-sub-42'): void
    {
        config(['services.google.client_id' => 'abc.apps.googleusercontent.com']);
        Http::fake(['oauth2.googleapis.com/*' => Http::response([
            'aud' => 'abc.apps.googleusercontent.com', 'iss' => 'https://accounts.google.com', 'exp' => time() + 600,
            'email' => $email, 'email_verified' => 'true', 'sub' => $sub, 'name' => 'Priya',
        ])]);
    }

    public function test_a_genuine_google_token_creates_a_customer_in_production(): void
    {
        $this->inEnvironment('production');
        $this->fakeGoogleFor('priya@example.com');

        $this->signIn('genuine-token')
            ->assertOk()
            ->assertJsonPath('data.user.email', 'priya@example.com')
            ->assertJsonStructure(['data' => ['token']]);

        $this->assertSame('CUSTOMER', User::where('email', 'priya@example.com')->value('role'));
    }

    public function test_a_genuine_google_token_links_to_an_existing_customer_by_email(): void
    {
        $customer = User::factory()->create(['email' => 'priya@example.com', 'role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $this->inEnvironment('production');
        $this->fakeGoogleFor('priya@example.com');

        $this->signIn('genuine-token')->assertOk();

        $this->assertSame('real-sub-42', $customer->fresh()->google_id);
        $this->assertSame(1, User::where('email', 'priya@example.com')->count(), 'no duplicate account');
    }

    public function test_a_blocked_customer_still_cannot_sign_in(): void
    {
        User::factory()->create(['email' => 'priya@example.com', 'role' => 'CUSTOMER', 'status' => 'BLOCKED']);
        $this->inEnvironment('production');
        $this->fakeGoogleFor('priya@example.com');

        $this->signIn('genuine-token')->assertStatus(422);
    }

    public function test_a_token_for_someone_elses_google_app_is_refused(): void
    {
        $this->inEnvironment('production');
        config(['services.google.client_id' => 'ours.apps.googleusercontent.com']);
        Http::fake(['oauth2.googleapis.com/*' => Http::response([
            'aud' => 'someone-else.apps.googleusercontent.com', 'iss' => 'https://accounts.google.com', 'exp' => time() + 600,
            'email' => 'priya@example.com', 'email_verified' => 'true', 'sub' => 's', 'name' => 'P',
        ])]);

        $this->signIn('token-from-another-app')->assertStatus(422);
    }
}
