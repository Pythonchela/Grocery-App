<?php

namespace Tests\Feature;

use App\Mail\NotificationMail;
use App\Models\AppNotification;
use App\Models\User;
use App\Services\NotificationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

/**
 * Customer notifications now leave the building: email and (optionally) SMS follow
 * the in-app notification, after the response, and can never break what caused them.
 */
class NotificationDeliveryTest extends TestCase
{
    use RefreshDatabase;

    private function service(): NotificationService
    {
        return app(NotificationService::class);
    }

    private function user(array $attrs = []): User
    {
        return User::factory()->create(array_merge(['email' => 'priya@shop-customer.in', 'phone' => '9876543210'], $attrs));
    }

    private function notify(User $user, string $title = 'Order BX-1 confirmed', ?string $body = 'Thanks!'): void
    {
        $this->service()->send($user, 'ORDER_UPDATE', $title, $body);

        // Deferred work runs after the response; outside a request, run it now.
        app(\Illuminate\Support\Defer\DeferredCallbackCollection::class)->invoke();
    }

    // ── Email ───────────────────────────────────────────────────────────

    public function test_a_notification_is_emailed_as_well_as_stored(): void
    {
        Mail::fake();
        $user = $this->user();

        $this->notify($user);

        $this->assertSame(1, AppNotification::where('user_id', $user->id)->count());
        Mail::assertSent(NotificationMail::class, fn (NotificationMail $m) => $m->hasTo('priya@shop-customer.in')
            && $m->headline === 'Order BX-1 confirmed'
            && $m->body === 'Thanks!');
    }

    public function test_the_email_renders_in_html_and_plain_text(): void
    {
        $mail = new NotificationMail('Order BX-1 shipped', 'It is on its way.');

        $mail->assertSeeInHtml('Order BX-1 shipped');
        $mail->assertSeeInHtml('It is on its way.');
        $mail->assertSeeInText('Order BX-1 shipped');
        $mail->assertSeeInText('It is on its way.');
    }

    public function test_user_supplied_text_is_escaped_in_the_email(): void
    {
        $html = (new NotificationMail('Return RMA-1: <script>alert(1)</script>', '<img src=x onerror=alert(1)>'))->render();

        $this->assertStringNotContainsString('<script>', $html);
        $this->assertStringNotContainsString('<img src=x', $html);
    }

    public function test_accounts_with_a_placeholder_email_are_never_mailed(): void
    {
        Mail::fake();

        foreach (['9876543210@example.com', 'a@example.org', 'b@something.test', 'c@localhost', 'd@x.invalid'] as $address) {
            $this->notify($this->user(['email' => $address, 'phone' => null]));
        }

        Mail::assertNothingSent();
    }

    public function test_someone_who_turned_the_type_off_gets_nothing(): void
    {
        Mail::fake();
        $user = $this->user();
        $user->forceFill(['notification_preferences' => ['ORDER_UPDATE' => false]])->save();

        $this->notify($user);

        Mail::assertNothingSent();
        $this->assertSame(0, AppNotification::count());
    }

    public function test_a_broken_mail_server_never_breaks_the_caller(): void
    {
        Mail::shouldReceive('to')->andThrow(new \RuntimeException('smtp down'));
        $user = $this->user();

        $this->notify($user); // must not throw

        $this->assertSame(1, AppNotification::where('user_id', $user->id)->count(), 'the in-app notification is still there');
    }

    public function test_the_failure_is_logged_without_the_address(): void
    {
        Mail::shouldReceive('to')->andThrow(new \RuntimeException('550 rejected priya@shop-customer.in'));
        \Illuminate\Support\Facades\Log::spy();

        $this->notify($this->user());

        \Illuminate\Support\Facades\Log::shouldHaveReceived('warning')->withArgs(
            fn ($message, $context = []) => str_contains($message, 'email not sent') && ! str_contains(json_encode($context), 'priya@shop-customer.in')
        );
    }

    public function test_email_is_deferred_until_after_the_response_not_sent_inline(): void
    {
        Mail::fake();
        $this->service()->send($this->user(), 'ORDER_UPDATE', 'Hello', null);

        // Nothing has been sent yet: it is queued behind the response.
        Mail::assertNothingSent();

        app(\Illuminate\Support\Defer\DeferredCallbackCollection::class)->invoke();
        Mail::assertSent(NotificationMail::class);
    }

    // ── SMS ─────────────────────────────────────────────────────────────

    public function test_order_texts_are_off_by_default_even_with_a_provider(): void
    {
        Http::fake();
        config(['messaging.sms.driver' => 'msg91', 'messaging.sms.msg91' => ['authkey' => 'k-0123456789', 'template_order' => 't1']]);

        $this->notify($this->user());

        Http::assertNothingSent();
    }

    public function test_order_texts_go_out_when_switched_on(): void
    {
        Http::fake(['control.msg91.com/*' => Http::response(['type' => 'success'])]);
        config([
            'messaging.sms.driver' => 'msg91', 'messaging.sms.order_updates' => 'on',
            'messaging.sms.msg91' => ['authkey' => 'k-0123456789', 'template_order' => 't1'],
        ]);

        $this->notify($this->user(), 'Order BX-1 shipped', null);

        Http::assertSent(fn (Request $r) => $r['template_id'] === 't1'
            && $r['recipients'][0]['mobiles'] === '919876543210'
            && str_contains($r['recipients'][0]['message'], 'Order BX-1 shipped'));
    }

    public function test_order_texts_never_go_out_through_the_log_driver(): void
    {
        Http::fake();
        config(['messaging.sms.driver' => 'log', 'messaging.sms.order_updates' => 'on']);

        $this->notify($this->user());

        Http::assertNothingSent();
    }

    public function test_a_failing_sms_provider_never_breaks_the_caller(): void
    {
        Http::fake(['*' => Http::response(['type' => 'error'], 500)]);
        config([
            'messaging.sms.driver' => 'msg91', 'messaging.sms.order_updates' => 'on',
            'messaging.sms.msg91' => ['authkey' => 'k-0123456789', 'template_order' => 't1'],
        ]);
        $user = $this->user();

        $this->notify($user);

        $this->assertSame(1, AppNotification::where('user_id', $user->id)->count());
    }

    public function test_a_user_without_a_valid_number_is_not_texted(): void
    {
        Http::fake();
        config(['messaging.sms.driver' => 'msg91', 'messaging.sms.order_updates' => 'on', 'messaging.sms.msg91' => ['authkey' => 'k-0123456789', 'template_order' => 't1']]);

        $this->notify($this->user(['phone' => null, 'email' => 'a@shop-customer.in']));
        $this->notify($this->user(['phone' => '12345', 'email' => 'b@shop-customer.in']));

        Http::assertNothingSent();
    }

    // ── helpers ─────────────────────────────────────────────────────────

    public function test_placeholder_detection(): void
    {
        foreach (['x@example.com', 'X@EXAMPLE.COM', 'x@example.net', 'x@foo.test', 'x@bar.invalid', 'x@localhost', 'no-at-sign', ''] as $placeholder) {
            $this->assertTrue(NotificationService::isPlaceholderAddress($placeholder), $placeholder);
        }

        foreach (['x@gmail.com', 'x@shop.in', 'x@testing.com', 'x@example.com.au'] as $real) {
            $this->assertFalse(NotificationService::isPlaceholderAddress($real), $real);
        }
    }

    public function test_national_number_normalisation(): void
    {
        $this->assertSame('9876543210', NotificationService::nationalNumber('9876543210'));
        $this->assertSame('9876543210', NotificationService::nationalNumber('+91 98765-43210'));
        $this->assertSame('9876543210', NotificationService::nationalNumber('919876543210'));
        $this->assertNull(NotificationService::nationalNumber('12345'));
        $this->assertNull(NotificationService::nationalNumber(null));
        $this->assertNull(NotificationService::nationalNumber(''));
    }
}
