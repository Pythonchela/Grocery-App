<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Payment gateways
    |--------------------------------------------------------------------------
    |
    | A gateway only takes money and gives it back; everything else (orders,
    | refunds, wallet, coupons, returns) belongs to the platform. To add one:
    |
    |   1. write a class implementing App\Services\Contracts\PaymentGateway
    |      with a static `fromConfig(): ?static` that returns null while its
    |      credentials are missing,
    |   2. add the class here.
    |
    | A gateway with no credentials simply isn't offered. With none configured
    | the sandbox gateway (moves no money) is used.
    |
    */
    'gateways' => [
        \App\Services\RazorpayGateway::class,
    ],

    /*
    | Which enabled gateway new payments use when the client doesn't choose one.
    | Leave unset to use the first configured gateway. Old payments are always
    | refunded through the gateway that took them, whatever this says.
    */
    'default' => env('PAYMENT_GATEWAY'),

    /*
    | The sandbox gateway approves every payment and moves no money. It is on by
    | default for local and testing, and OFF in production, where a server that
    | is missing its gateway keys would otherwise accept orders nobody paid for
    | (prepaid checkout then answers "not available" and COD keeps working).
    | Set to true only for a demo deployment that is deliberately fake.
    */
    // Blank or unset means "use the default for this environment" (allowed
    // locally, refused in production) — not "false". Laravel's env() already
    // turns the words true/false/null into real values, so those arrive typed.
    'allow_sandbox' => (function () {
        $raw = env('PAYMENTS_ALLOW_SANDBOX');

        if ($raw === null || (is_string($raw) && trim($raw) === '')) {
            return null;
        }

        return filter_var($raw, FILTER_VALIDATE_BOOLEAN);
    })(),

    /*
    | A payment the gateway captured but no order ever claimed (the app died
    | between paying and placing the order) is refunded automatically after this
    | many minutes. Long enough for a slow checkout call to finish first.
    */
    'unclaimed_refund_after_minutes' => (int) env('PAYMENT_UNCLAIMED_REFUND_MINUTES', 30),

];
