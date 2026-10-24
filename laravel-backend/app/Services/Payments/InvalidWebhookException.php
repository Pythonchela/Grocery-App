<?php

namespace App\Services\Payments;

use RuntimeException;

/** A webhook whose signature failed, or that this gateway is not set up to receive. */
class InvalidWebhookException extends RuntimeException
{
}
