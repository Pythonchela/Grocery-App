<?php

namespace App\Services\Messaging;

/**
 * Picks the SMS driver from config. Built fresh from config each time it is asked,
 * so a change made in the admin panel is used by the next message with nothing to
 * invalidate.
 */
class SmsGatewayManager
{
    public const DRIVERS = ['log', 'msg91', 'twilio'];

    public function gateway(): SmsGateway
    {
        return $this->make((string) config('messaging.sms.driver'), [
            'msg91' => (array) config('messaging.sms.msg91'),
            'twilio' => (array) config('messaging.sms.twilio'),
        ], (string) config('messaging.sms.country_code', '91'));
    }

    /**
     * Build a driver from explicit settings. Used by the connection test, which
     * must try values that have not been saved, without touching the live config.
     *
     * @param  array{msg91?: array, twilio?: array}  $settings
     */
    public function make(string $driver, array $settings, string $countryCode = '91'): SmsGateway
    {
        return match ($driver) {
            'msg91' => new Msg91SmsGateway($settings['msg91'] ?? [], $countryCode),
            'twilio' => new TwilioSmsGateway($settings['twilio'] ?? [], $countryCode),
            default => new LogSmsGateway,
        };
    }

    /**
     * Whether a text sent now would really leave. Anywhere outside development a
     * 'log' driver does not count - callers that promise delivery (the login OTP)
     * must refuse rather than say "sent" into the log.
     */
    public function canDeliver(): bool
    {
        return $this->gateway()->name() !== 'log' || app()->environment(['local', 'testing']);
    }

    public function sendsOrderUpdates(): bool
    {
        return config('messaging.sms.order_updates') === 'on' && $this->gateway()->name() !== 'log';
    }
}
