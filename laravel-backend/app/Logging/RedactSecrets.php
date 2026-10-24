<?php

namespace App\Logging;

use Illuminate\Log\Logger;
use Monolog\Handler\FormattableHandlerInterface;

/**
 * Keeps credentials out of the log files.
 *
 * A credential can reach a log without anyone meaning it to: an HTTP client
 * exception quotes the request URL, a provider echoes a request back in an error,
 * a developer logs a whole payload. Redacting at the formatter is the one place
 * that catches all of those, because it works on the finished line — message,
 * context and exception trace alike.
 *
 * Attached to the log channels in config/logging.php with `tap`.
 */
class RedactSecrets
{
    public function __invoke(Logger $logger): void
    {
        foreach ($logger->getHandlers() as $handler) {
            if ($handler instanceof FormattableHandlerInterface) {
                $handler->setFormatter(new RedactingFormatter($handler->getFormatter()));
            }
        }
    }
}
