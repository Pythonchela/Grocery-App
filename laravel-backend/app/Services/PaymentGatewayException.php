<?php

namespace App\Services;

use RuntimeException;

/**
 * The payment provider could not be reached, or refused a request we made.
 *
 * The message is written for the customer and never carries provider internals;
 * what the provider actually said is logged by the gateway and kept on
 * `$detail` for whoever reads the log.
 *
 * Distinct from "payment not verified": an unverified payment is a normal
 * outcome (bad signature, abandoned checkout), whereas this means we do not
 * know what happened at the provider — so the caller must abort rather than
 * assume either answer.
 */
class PaymentGatewayException extends RuntimeException
{
    public function __construct(string $message, public readonly ?string $detail = null)
    {
        parent::__construct($message);
    }
}
