<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Phone sign-in by one-time code, end to end through a real (faked) SMS provider.
 *
 * Before this the code was written to a log and the endpoint said "sent", so in
 * production nobody could ever sign in by phone and nothing said so.
 */
class OtpLoginTest extends TestCase
{
    use RefreshDatabase;

    private const PHONE = '9876543210';

    protected function setUp(): void
    {
        parent::setUp();

        config([
            'messaging.sms.driver' => 'msg91',
            'messaging.sms.msg91' => ['authkey' => 'msg91-auth-key-0123456789', 'template_otp' => 'tpl_otp_1', 'template_order' => null],
        ]);
    }

    /** The code the provider was asked to deliver — what the customer would read. */
    private function sentCode(): string
    {
        $code = null;

        Http::assertSent(function (Request $r) use (&$code) {
            $code = $r['recipients'][0]['otp'] ?? null;

            return $code !== null;
        });

        return (string) $code;
    }

    private function send(string $phone = self::PHONE)
    {
        return $this->postJson('/api/v1/auth/otp/send', ['phone' => $phone]);
    }

    private function verify(string $otp, string $phone = self::PHONE)
    {
        return $this->postJson('/api/v1/auth/otp/verify', ['phone' => $phone, 'otp' => $otp]);
    }

    public function test_the_code_is_delivered_by_sms_and_signs_the_person_in(): void
    {
        Http::fake(['control.msg91.com/*' => Http::response(['type' => 'success'])]);

        $this->send()->assertOk()->assertJsonPath('status', 'success');

        $code = $this->sentCode();
        $this->assertMatchesRegularExpression('/^[0-9]{6}$/', $code);

        $this->verify($code)->assertOk()->assertJsonStructure(['data' => ['user', 'token']]);

        $this->assertSame(1, User::where('phone', self::PHONE)->count());
    }

    public function test_the_response_no_longer_talks_about_logs_or_mocks(): void
    {
        Http::fake(['*' => Http::response(['type' => 'success'])]);

        $message = (string) $this->send()->json('message');

        $this->assertStringNotContainsStringIgnoringCase('log', $message);
        $this->assertStringNotContainsStringIgnoringCase('mock', $message);
    }

    public function test_the_code_is_not_stored_in_the_clear(): void
    {
        Http::fake(['*' => Http::response(['type' => 'success'])]);

        $this->send()->assertOk();
        $code = $this->sentCode();

        $stored = (string) Cache::get('otp_'.self::PHONE);

        $this->assertNotSame('', $stored);
        $this->assertNotSame($code, $stored);
        $this->assertStringNotContainsString($code, $stored);
        $this->assertMatchesRegularExpression('/^[0-9a-f]{64}$/', $stored);
    }

    public function test_a_wrong_code_is_refused_and_the_right_one_is_single_use(): void
    {
        Http::fake(['*' => Http::response(['type' => 'success'])]);
        $this->send()->assertOk();
        $code = $this->sentCode();
        $wrong = $code === '000000' ? '111111' : '000000';

        $this->verify($wrong)->assertStatus(422)->assertJsonValidationErrors('otp');
        $this->verify($code)->assertOk();
        $this->verify($code)->assertStatus(422);
    }

    public function test_a_code_is_only_good_for_the_number_it_was_sent_to(): void
    {
        Http::fake(['*' => Http::response(['type' => 'success'])]);
        $this->send()->assertOk();

        $this->verify($this->sentCode(), '9123456780')->assertStatus(422);
    }

    public function test_when_the_provider_fails_the_person_is_told_and_no_code_is_left_behind(): void
    {
        Http::fake(['*' => Http::response(['type' => 'error'], 500)]);

        $this->send()->assertStatus(503)->assertJsonPath('status', 'error');

        $this->assertNull(Cache::get('otp_'.self::PHONE), 'a code nobody received must not stay guessable');
    }

    public function test_a_provider_failure_does_not_leak_provider_detail(): void
    {
        Http::fake(['*' => Http::response(['type' => 'error', 'message' => 'authkey msg91-auth-key-0123456789 rejected'], 401)]);

        $body = $this->send()->assertStatus(503)->getContent();

        $this->assertStringNotContainsString('msg91-auth-key', $body);
        $this->assertStringNotContainsString('authkey', $body);
    }

    public function test_with_no_sms_provider_in_production_it_says_so_instead_of_pretending(): void
    {
        config(['messaging.sms.driver' => 'log']);
        $this->app['env'] = 'production';
        Http::fake();

        $response = $this->send()->assertStatus(503);

        $this->assertStringNotContainsStringIgnoringCase('sent', (string) $response->json('message'));
        $this->assertNull(Cache::get('otp_'.self::PHONE));
        Http::assertNothingSent();
    }

    public function test_in_development_the_log_driver_still_works_for_signing_in(): void
    {
        config(['messaging.sms.driver' => 'log']);

        $this->send()->assertOk();

        $this->assertNotNull(Cache::get('otp_'.self::PHONE));
    }

    public function test_a_new_phone_gets_an_account_whose_placeholder_email_is_never_mailed(): void
    {
        Http::fake(['*' => Http::response(['type' => 'success'])]);
        $this->send()->assertOk();
        $this->verify($this->sentCode())->assertOk();

        $user = User::where('phone', self::PHONE)->firstOrFail();

        $this->assertSame('ACTIVE', $user->status);
        $this->assertTrue(\App\Services\NotificationService::isPlaceholderAddress($user->email));
    }

    public function test_a_blocked_account_cannot_sign_in_with_a_valid_code(): void
    {
        Http::fake(['*' => Http::response(['type' => 'success'])]);
        User::factory()->create(['phone' => self::PHONE, 'status' => 'BLOCKED']);

        $this->send()->assertOk();

        $this->verify($this->sentCode())->assertStatus(422);
    }

    public function test_the_number_must_be_ten_digits(): void
    {
        Http::fake();

        foreach (['12345', '98765432101', 'abcdefghij', '+919876543210', ''] as $bad) {
            $this->send($bad)->assertStatus(422);
        }

        Http::assertNothingSent();
    }
}
