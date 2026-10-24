<?php

return [

    // Where the "Open the store" button in emails points.
    'store_url' => env('FRONTEND_URL'),

    /*
    | SMS. A provider-neutral layer, like payments: the driver is only the hook that
    | carries a message; what to say and when is decided by the app.
    |
    |   log     - writes to the log, sends nothing (development). In production the
    |             login OTP endpoint refuses rather than pretend it sent something.
    |   msg91   - India, DLT template based (recommended for Indian numbers).
    |   twilio  - free-text messages, international.
    |
    | All of these can be set from the admin panel (Integrations -> SMS); the
    | environment values below are the defaults it falls back to.
    */
    'sms' => [
        'driver' => env('SMS_DRIVER', 'log'),

        // Send order-update texts as well as the login OTP. Off by default: every
        // text costs money, and on DLT providers each needs its own approved template.
        'order_updates' => env('SMS_ORDER_UPDATES', 'off'),

        // Numbers are stored as 10 digits. Prefixed with this when handed to a provider.
        'country_code' => env('SMS_COUNTRY_CODE', '91'),

        'msg91' => [
            'authkey' => env('MSG91_AUTHKEY'),
            // The Flow template ids approved for your DLT entity. The OTP template must
            // have one variable named `otp`; the order template one named `message`.
            'template_otp' => env('MSG91_TEMPLATE_OTP'),
            'template_order' => env('MSG91_TEMPLATE_ORDER'),
        ],

        'twilio' => [
            'sid' => env('TWILIO_SID'),
            'token' => env('TWILIO_TOKEN'),
            // A number in E.164 form, or a Messaging Service SID (starts with MG).
            'from' => env('TWILIO_FROM'),
        ],
    ],

];
