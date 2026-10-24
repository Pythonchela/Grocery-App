<?php

namespace Tests\Feature;

use App\Services\Messaging\LogSmsGateway;
use App\Services\Messaging\Msg91SmsGateway;
use App\Services\Messaging\SmsDeliveryException;
use App\Services\Messaging\SmsGatewayManager;
use App\Services\Messaging\SmsMessage;
use App\Services\Messaging\TwilioSmsGateway;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

/** The SMS drivers: what they send, and that a failure never leaks a credential. */
class SmsGatewayTest extends TestCase
{
    private const AUTHKEY = 'msg91-auth-key-0123456789';

    private const TWILIO_SID = 'AC_fake_test_sid_not_a_real_one';

    private const TWILIO_TOKEN = 'twilio-token-0123456789abcdef';

    private function msg91(array $over = []): Msg91SmsGateway
    {
        return new Msg91SmsGateway(array_merge([
            'authkey' => self::AUTHKEY, 'template_otp' => 'tpl_otp_1', 'template_order' => 'tpl_order_1',
        ], $over));
    }

    private function twilio(array $over = []): TwilioSmsGateway
    {
        return new TwilioSmsGateway(array_merge([
            'sid' => self::TWILIO_SID, 'token' => self::TWILIO_TOKEN, 'from' => '+14155550123',
        ], $over));
    }

    // ── MSG91 ───────────────────────────────────────────────────────────

    public function test_msg91_sends_the_approved_template_with_its_variable(): void
    {
        Http::fake(['control.msg91.com/*' => Http::response(['type' => 'success', 'message' => 'abc'])]);

        $this->msg91()->send(SmsMessage::otp('9876543210', '482913', 'BazaarX'));

        Http::assertSent(function (Request $r) {
            return $r->url() === 'https://control.msg91.com/api/v5/flow'
                && $r->hasHeader('authkey', self::AUTHKEY)
                && $r['template_id'] === 'tpl_otp_1'
                && $r['recipients'][0]['mobiles'] === '919876543210'
                && $r['recipients'][0]['otp'] === '482913';
        });
    }

    public function test_msg91_uses_the_order_template_for_order_messages(): void
    {
        Http::fake(['*' => Http::response(['type' => 'success'])]);

        $this->msg91()->send(SmsMessage::order('9876543210', 'Order 1 shipped'));

        Http::assertSent(fn (Request $r) => $r['template_id'] === 'tpl_order_1' && $r['recipients'][0]['message'] === 'Order 1 shipped');
    }

    public function test_msg91_refuses_a_message_kind_with_no_template_rather_than_sending_something_else(): void
    {
        Http::fake();

        $this->expectException(SmsDeliveryException::class);

        try {
            $this->msg91(['template_order' => null])->send(SmsMessage::order('9876543210', 'x'));
        } finally {
            Http::assertNothingSent();
        }
    }

    public function test_msg91_without_a_key_does_not_call_out(): void
    {
        Http::fake();

        try {
            $this->msg91(['authkey' => ''])->send(SmsMessage::otp('9876543210', '111111', 'X'));
            $this->fail('expected an exception');
        } catch (SmsDeliveryException $e) {
            $this->assertStringContainsString('auth key', $e->getMessage());
        }

        Http::assertNothingSent();
    }

    public function test_msg91_reports_a_rejected_key_without_echoing_anything(): void
    {
        Http::fake(['*' => Http::response(['type' => 'error', 'message' => 'bad key '.self::AUTHKEY.' for 919876543210'], 401)]);

        try {
            $this->msg91()->send(SmsMessage::otp('9876543210', '111111', 'X'));
            $this->fail('expected an exception');
        } catch (SmsDeliveryException $e) {
            $this->assertStringContainsString('rejected', $e->getMessage());
            $this->assertStringNotContainsString(self::AUTHKEY, $e->getMessage());
            $this->assertStringNotContainsString('9876543210', $e->getMessage());
        }
    }

    public function test_msg91_treats_a_200_with_an_error_type_as_a_failure(): void
    {
        Http::fake(['*' => Http::response(['type' => 'error', 'message' => 'template mismatch'], 200)]);

        $this->expectException(SmsDeliveryException::class);

        $this->msg91()->send(SmsMessage::otp('9876543210', '111111', 'X'));
    }

    public function test_a_network_failure_is_a_delivery_exception(): void
    {
        Http::fake(fn () => throw new \Illuminate\Http\Client\ConnectionException('timeout'));

        $this->expectException(SmsDeliveryException::class);

        $this->msg91()->send(SmsMessage::otp('9876543210', '111111', 'X'));
    }

    public function test_provider_failures_are_not_logged_with_the_number_or_the_body(): void
    {
        Http::fake(['*' => Http::response(['type' => 'error', 'message' => 'number 919876543210 bad'], 400)]);
        Log::spy();

        try {
            $this->msg91()->send(SmsMessage::otp('9876543210', '111111', 'X'));
        } catch (SmsDeliveryException) {
        }

        Log::shouldHaveReceived('warning')->withArgs(function ($message, $context = []) {
            return ! str_contains(json_encode($context), '9876543210');
        });
    }

    // ── Twilio ──────────────────────────────────────────────────────────

    public function test_twilio_posts_free_text_with_basic_auth(): void
    {
        Http::fake(['api.twilio.com/*' => Http::response(['sid' => 'SM1'], 201)]);

        $this->twilio()->send(SmsMessage::otp('9876543210', '482913', 'BazaarX'));

        Http::assertSent(function (Request $r) {
            return $r->url() === 'https://api.twilio.com/2010-04-01/Accounts/'.self::TWILIO_SID.'/Messages.json'
                && $r->hasHeader('Authorization', 'Basic '.base64_encode(self::TWILIO_SID.':'.self::TWILIO_TOKEN))
                && $r['To'] === '+919876543210'
                && $r['From'] === '+14155550123'
                && str_contains($r['Body'], '482913');
        });
    }

    public function test_twilio_uses_a_messaging_service_when_given_one(): void
    {
        Http::fake(['*' => Http::response([], 201)]);

        $this->twilio(['from' => 'MG0123456789abcdef0123456789abcdef'])->send(SmsMessage::order('9876543210', 'hi'));

        Http::assertSent(fn (Request $r) => isset($r['MessagingServiceSid']) && ! isset($r['From']));
    }

    public function test_twilio_holds_the_sid_to_its_real_shape_because_it_goes_in_the_url(): void
    {
        Http::fake();

        try {
            $this->twilio(['sid' => '../../evil'])->send(SmsMessage::order('9876543210', 'hi'));
            $this->fail('expected an exception');
        } catch (SmsDeliveryException) {
        }

        Http::assertNothingSent();
    }

    public function test_twilio_needs_all_three_settings(): void
    {
        Http::fake();

        foreach (['sid', 'token', 'from'] as $missing) {
            try {
                $this->twilio([$missing => ''])->send(SmsMessage::order('9876543210', 'hi'));
                $this->fail("expected an exception without {$missing}");
            } catch (SmsDeliveryException) {
            }
        }

        Http::assertNothingSent();
    }

    public function test_twilio_failure_does_not_echo_the_token(): void
    {
        Http::fake(['*' => Http::response(['code' => 20003, 'message' => 'auth failed '.self::TWILIO_TOKEN], 401)]);

        try {
            $this->twilio()->send(SmsMessage::order('9876543210', 'hi'));
            $this->fail('expected an exception');
        } catch (SmsDeliveryException $e) {
            $this->assertStringNotContainsString(self::TWILIO_TOKEN, $e->getMessage());
        }
    }

    // ── Log driver ──────────────────────────────────────────────────────

    public function test_the_log_driver_shows_the_text_in_testing_so_a_developer_can_sign_in(): void
    {
        Log::spy();

        (new LogSmsGateway)->send(SmsMessage::otp('9876543210', '482913', 'X'));

        Log::shouldHaveReceived('info')->withArgs(fn ($m, $ctx) => str_contains($ctx['message'] ?? '', '482913') && ! str_contains(json_encode($ctx), '9876543210'));
    }

    public function test_the_log_driver_never_writes_the_code_outside_development(): void
    {
        $this->app['env'] = 'production';
        Log::spy();

        (new LogSmsGateway)->send(SmsMessage::otp('9876543210', '482913', 'X'));

        Log::shouldHaveReceived('info')->withArgs(fn ($m, $ctx) => ! str_contains(json_encode($ctx), '482913') && ! str_contains(json_encode($ctx), '9876543210'));
    }

    // ── Manager ─────────────────────────────────────────────────────────

    public function test_the_manager_builds_the_configured_driver(): void
    {
        $manager = new SmsGatewayManager;

        config(['messaging.sms.driver' => 'msg91']);
        $this->assertSame('msg91', $manager->gateway()->name());

        config(['messaging.sms.driver' => 'twilio']);
        $this->assertSame('twilio', $manager->gateway()->name());

        config(['messaging.sms.driver' => 'something-unknown']);
        $this->assertSame('log', $manager->gateway()->name());
    }

    public function test_a_log_driver_cannot_deliver_outside_development(): void
    {
        $manager = new SmsGatewayManager;
        config(['messaging.sms.driver' => 'log']);

        $this->assertTrue($manager->canDeliver(), 'fine in testing');

        $this->app['env'] = 'production';
        $this->assertFalse($manager->canDeliver());

        config(['messaging.sms.driver' => 'msg91']);
        $this->assertTrue($manager->canDeliver());
    }

    public function test_order_texts_need_both_the_switch_and_a_real_provider(): void
    {
        $manager = new SmsGatewayManager;

        config(['messaging.sms.driver' => 'msg91', 'messaging.sms.order_updates' => 'off']);
        $this->assertFalse($manager->sendsOrderUpdates());

        config(['messaging.sms.order_updates' => 'on']);
        $this->assertTrue($manager->sendsOrderUpdates());

        config(['messaging.sms.driver' => 'log']);
        $this->assertFalse($manager->sendsOrderUpdates());
    }
}
