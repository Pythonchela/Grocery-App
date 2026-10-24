<?php

namespace App\Integrations\Testers;

use App\Services\Messaging\SmsDeliveryException;
use App\Services\Messaging\SmsGatewayManager;
use App\Services\Messaging\SmsMessage;
use App\Services\NotificationService;

/**
 * Sends one real text to a number the admin types. It costs a few paise, so it is
 * rate limited like every test, and it only ever goes to the provider selected in
 * the form (a fixed host per driver) - never to an address taken from input.
 */
class SmsTester implements Tester
{
    public function test(array $values, ?string $target = null): TestResult
    {
        $driver = (string) ($values['driver'] ?? 'log');

        if ($driver === 'log') {
            return TestResult::unavailable('No SMS provider is selected, so nothing is sent.');
        }

        $phone = NotificationService::nationalNumber($target);

        if ($phone === null || strlen(preg_replace('/\D+/', '', (string) $target) ?? '') !== 10) {
            return TestResult::incomplete('Enter the 10-digit mobile number to send the test to.');
        }

        $gateway = app(SmsGatewayManager::class)->make($driver, [
            'msg91' => [
                'authkey' => $values['msg91_authkey'] ?? null,
                'template_otp' => $values['msg91_template_otp'] ?? null,
                'template_order' => $values['msg91_template_order'] ?? null,
            ],
            'twilio' => [
                'sid' => $values['twilio_sid'] ?? null,
                'token' => $values['twilio_token'] ?? null,
                'from' => $values['twilio_from'] ?? null,
            ],
        ], (string) config('messaging.sms.country_code', '91'));

        $app = (string) config('app.name');

        try {
            // On a template provider this uses the OTP template with a dummy code.
            $gateway->send(new SmsMessage($phone, "Test message from {$app}: your SMS settings work.", SmsMessage::OTP, ['otp' => '000000']));
        } catch (SmsDeliveryException $e) {
            return TestResult::failed($e->getMessage());
        }

        return TestResult::ok('The provider accepted the message. It should reach the phone within a minute.');
    }
}
