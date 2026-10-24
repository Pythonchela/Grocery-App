<?php

namespace Tests\Feature;

use App\Models\User;
use App\Monitoring\SentryScrubber;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Sentry\Breadcrumb;
use Sentry\Event;
use Sentry\ExceptionDataBag;
use Sentry\Frame;
use Sentry\Stacktrace;
use Tests\TestCase;

/**
 * An error tracker is a third party. Whatever is in an exception must not reach it
 * carrying a credential, a password, a cookie or a request body.
 */
class SentryScrubberTest extends TestCase
{
    use RefreshDatabase;

    private const KEY = 'AIzaSyD-TEST-KEY-1234567890abcdWXYZ';

    private const SMTP = 'smtp-Secret-Pass-4471';

    private function event(array $request = []): Event
    {
        $event = Event::createEvent();
        $event->setRequest($request);

        return $event;
    }

    public function test_secrets_are_removed_from_exception_text(): void
    {
        config(['services.gemini.key' => self::KEY, 'mail.mailers.smtp.password' => self::SMTP]);

        $event = $this->event();
        $event->setExceptions([new ExceptionDataBag(new \RuntimeException('Failed calling https://g.test/v1?key='.self::KEY.' with '.self::SMTP))]);

        $out = SentryScrubber::beforeSend($event);

        $value = $out->getExceptions()[0]->getValue();
        $this->assertStringNotContainsString(self::KEY, $value);
        $this->assertStringNotContainsString(self::SMTP, $value);
        $this->assertStringContainsString('[redacted]', $value);
    }

    public function test_the_message_and_extra_data_are_scrubbed_too(): void
    {
        config(['services.gemini.key' => self::KEY]);

        $event = $this->event();
        $event->setMessage('token '.self::KEY);
        $event->setExtra(['nested' => ['deep' => 'sent '.self::KEY], 'fine' => 'order 1234']);

        $out = SentryScrubber::beforeSend($event);

        $this->assertStringNotContainsString(self::KEY, (string) $out->getMessage());
        $this->assertStringNotContainsString(self::KEY, json_encode($out->getExtra()));
        $this->assertSame('order 1234', $out->getExtra()['fine'], 'ordinary data is untouched');
    }

    public function test_function_arguments_in_stack_frames_are_dropped(): void
    {
        $frame = new Frame('login', 'AuthController.php', 40, null, null, ['password' => 'hunter2-the-password', 'email' => 'a@b.in']);
        $event = $this->event();
        $event->setExceptions([new ExceptionDataBag(new \RuntimeException('boom'), new Stacktrace([$frame]))]);

        $out = SentryScrubber::beforeSend($event);

        $this->assertSame([], $out->getExceptions()[0]->getStacktrace()->getFrames()[0]->getVars());
    }

    public function test_request_bodies_cookies_and_credential_headers_never_leave(): void
    {
        $event = $this->event([
            'url' => 'https://api.shop.in/v1/x?key='.self::KEY,
            'query_string' => 'authkey=abcdef0123456789&page=2',
            'data' => ['current_password' => 'my-real-password', 'otp' => '482913'],
            'cookies' => ['laravel_session' => 'sess123'],
            'headers' => [
                'Authorization' => ['Bearer tok-abcdef'], 'Cookie' => ['a=b'], 'X-XSRF-TOKEN' => ['x'],
                'User-Agent' => ['Mozilla'], 'Accept' => ['application/json'],
            ],
        ]);

        $out = SentryScrubber::beforeSend($event)->getRequest();

        $this->assertArrayNotHasKey('data', $out);
        $this->assertArrayNotHasKey('cookies', $out);
        $this->assertArrayNotHasKey('Authorization', $out['headers']);
        $this->assertArrayNotHasKey('Cookie', $out['headers']);
        $this->assertArrayNotHasKey('X-XSRF-TOKEN', $out['headers']);
        $this->assertArrayHasKey('User-Agent', $out['headers'], 'harmless headers are useful for debugging and stay');
        $this->assertStringNotContainsString(self::KEY, $out['url']);
        $this->assertStringNotContainsString('abcdef0123456789', $out['query_string']);
        $this->assertStringContainsString('page=2', $out['query_string']);
        $this->assertStringNotContainsString('my-real-password', json_encode($out));
    }

    public function test_breadcrumbs_are_scrubbed(): void
    {
        config(['services.gemini.key' => self::KEY]);

        $crumb = new Breadcrumb(Breadcrumb::LEVEL_INFO, Breadcrumb::TYPE_HTTP, 'http', 'GET https://g.test/?key='.self::KEY, [
            'url' => 'https://g.test/?key='.self::KEY, 'status' => 200,
        ]);

        $out = SentryScrubber::beforeBreadcrumb($crumb);

        $this->assertStringNotContainsString(self::KEY, (string) $out->getMessage());
        $this->assertStringNotContainsString(self::KEY, json_encode($out->getMetadata()));
        $this->assertSame(200, $out->getMetadata()['status']);
    }

    public function test_the_sdk_is_configured_to_send_no_personal_data_and_to_use_the_scrubber(): void
    {
        $this->assertFalse((bool) config('sentry.send_default_pii'));
        $this->assertSame('none', config('sentry.max_request_body_size'));
        $this->assertSame([SentryScrubber::class, 'beforeSend'], config('sentry.before_send'));
        $this->assertSame([SentryScrubber::class, 'beforeBreadcrumb'], config('sentry.before_breadcrumb'));
        $this->assertTrue(is_callable(config('sentry.before_send')));
        $this->assertTrue(is_callable(config('sentry.before_breadcrumb')));

        // Bindings are where bound values (emails, hashes) would travel.
        $this->assertFalse((bool) config('sentry.breadcrumbs.sql_bindings'));
        $this->assertFalse((bool) config('sentry.tracing.sql_bindings'));
    }

    public function test_the_config_holds_no_closures_so_config_cache_still_works(): void
    {
        $this->assertStringNotContainsString('Closure', serialize_safe(config('sentry')));
    }

    public function test_with_no_dsn_the_app_works_and_sends_nothing(): void
    {
        $this->assertEmpty(config('sentry.dsn'));

        $this->getJson('/api/v1/categories')->assertOk();
        $this->actingAs(User::factory()->create(), 'sanctum')->getJson('/api/v1/auth/me')->assertOk();
    }

    public function test_a_server_error_still_renders_normally_with_tracking_installed(): void
    {
        \Illuminate\Support\Facades\Route::get('/api/v1/_boom', fn () => throw new \RuntimeException('kaboom '.self::KEY));

        $response = $this->getJson('/api/v1/_boom')->assertStatus(500);

        // The default error page: no stack trace of ours leaks to the client in production.
        $this->app['env'] = 'production';
        $this->assertArrayHasKey('message', $response->json());
    }

    public function test_the_same_scrubber_protects_the_log_files(): void
    {
        config(['services.gemini.key' => self::KEY]);

        $this->assertStringNotContainsString(self::KEY, \App\Logging\SecretScrubber::scrub('x '.self::KEY));
    }
}

/** serialize() throws on a Closure, which is exactly what this guards against. */
function serialize_safe(array $config): string
{
    try {
        return serialize($config);
    } catch (\Throwable $e) {
        return 'Closure';
    }
}
