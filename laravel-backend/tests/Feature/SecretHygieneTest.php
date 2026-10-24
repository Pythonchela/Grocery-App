<?php

namespace Tests\Feature;

use App\Logging\RedactingFormatter;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Monolog\Formatter\LineFormatter;
use Monolog\Level;
use Monolog\LogRecord;
use Tests\TestCase;

/** Credentials must not reach log files, and an admin with no password can be given one. */
class SecretHygieneTest extends TestCase
{
    use RefreshDatabase;

    private const KEY = 'AIzaSyD-TEST-KEY-1234567890abcdWXYZ';

    private function line(string $message, array $context = []): string
    {
        $formatter = new RedactingFormatter(new LineFormatter(null, null, true, true));

        return $formatter->format(new LogRecord(new \DateTimeImmutable, 'test', Level::Error, $message, $context));
    }

    public function test_a_known_secret_is_redacted_wherever_it_appears(): void
    {
        config(['services.gemini.key' => self::KEY]);

        $line = $this->line('request failed', ['note' => 'sent '.self::KEY.' to google', 'exception' => new \RuntimeException('bad key '.self::KEY)]);

        $this->assertStringNotContainsString(self::KEY, $line);
        $this->assertStringContainsString('[redacted]', $line);
    }

    public function test_query_string_credentials_are_redacted_even_when_not_known(): void
    {
        $line = $this->line('GET https://api.example.com/v1?key=totally-unknown-123&page=2 failed');

        $this->assertStringNotContainsString('totally-unknown-123', $line);
        $this->assertStringContainsString('page=2', $line);
    }

    public function test_authorization_headers_are_redacted(): void
    {
        $line = $this->line('sent', ['headers' => 'Authorization: Bearer abc.def.ghi-123']);

        $this->assertStringNotContainsString('abc.def.ghi-123', $line);
    }

    public function test_the_app_key_and_payment_secrets_are_redacted(): void
    {
        config(['services.razorpay.key_secret' => 'razorpay-secret-value-99', 'services.razorpay.webhook_secret' => 'whsec_value_000111']);

        $line = $this->line('dump', ['a' => 'razorpay-secret-value-99', 'b' => 'whsec_value_000111', 'c' => substr(config('app.key'), 7)]);

        $this->assertStringNotContainsString('razorpay-secret-value-99', $line);
        $this->assertStringNotContainsString('whsec_value_000111', $line);
        $this->assertStringNotContainsString(substr(config('app.key'), 7), $line);
    }

    public function test_ordinary_text_and_short_values_are_left_alone(): void
    {
        config(['services.gemini.key' => 'abc']);

        $this->assertStringContainsString('order 1234 shipped', $this->line('order 1234 shipped'));
    }

    public function test_the_real_log_channels_redact(): void
    {
        config(['services.gemini.key' => self::KEY, 'logging.default' => 'single', 'logging.channels.single.path' => storage_path('logs/redact-test.log')]);
        @unlink(storage_path('logs/redact-test.log'));

        \Log::channel('single')->error('failed '.self::KEY);

        $written = (string) file_get_contents(storage_path('logs/redact-test.log'));
        @unlink(storage_path('logs/redact-test.log'));

        $this->assertStringContainsString('failed [redacted]', $written);
        $this->assertStringNotContainsString(self::KEY, $written);
    }

    public function test_sensitive_request_fields_are_never_flashed(): void
    {
        $dontFlash = (new \ReflectionProperty(\Illuminate\Foundation\Exceptions\Handler::class, 'dontFlash'))
            ->getValue(app(\Illuminate\Contracts\Debug\ExceptionHandler::class));

        foreach (['current_password', 'api_key', 'values'] as $field) {
            $this->assertContains($field, $dontFlash);
        }
    }

    // ── bazaarx:set-password ────────────────────────────────────────────

    public function test_an_admin_without_a_password_can_be_given_one(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $admin->forceFill(['password' => null])->save();
        $admin->createToken('old-session');

        $this->artisan('bazaarx:set-password', ['email' => strtoupper($admin->email)])
            ->expectsQuestion('New password (min. 10 characters)', 'a-good-long-password')
            ->expectsQuestion('Repeat the password', 'a-good-long-password')
            ->assertSuccessful();

        $this->assertTrue(Hash::check('a-good-long-password', $admin->fresh()->password));
        $this->assertSame(0, $admin->tokens()->count(), 'older sessions are signed out');
    }

    public function test_it_refuses_non_admins_with_the_same_message_as_unknown_emails(): void
    {
        $customer = User::factory()->create(['role' => User::ROLE_CUSTOMER]);
        $before = $customer->password;

        $this->artisan('bazaarx:set-password', ['email' => $customer->email])->expectsOutputToContain('No admin account with that email.')->assertFailed();
        $this->artisan('bazaarx:set-password', ['email' => 'nobody@nowhere.test'])->expectsOutputToContain('No admin account with that email.')->assertFailed();

        $this->assertSame($before, $customer->fresh()->password);
    }

    public function test_it_rejects_short_or_mismatched_passwords(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $before = $admin->password;

        $this->artisan('bazaarx:set-password', ['email' => $admin->email])
            ->expectsQuestion('New password (min. 10 characters)', 'short')
            ->expectsQuestion('Repeat the password', 'short')
            ->assertFailed();

        $this->artisan('bazaarx:set-password', ['email' => $admin->email])
            ->expectsQuestion('New password (min. 10 characters)', 'a-good-long-password')
            ->expectsQuestion('Repeat the password', 'a-different-password')
            ->assertFailed();

        $this->assertSame($before, $admin->fresh()->password);
    }
}
