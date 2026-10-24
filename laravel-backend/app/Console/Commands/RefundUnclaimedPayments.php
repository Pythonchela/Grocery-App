<?php

namespace App\Console\Commands;

use App\Services\Payments\PaymentService;
use Illuminate\Console\Command;

/**
 * Give back money that was captured but never became an order.
 *
 * Happens when a customer pays and the app dies, or the connection drops,
 * before the checkout call that places the order. The gateway's webhook tells
 * us the money arrived; if the customer's own call still hasn't claimed it
 * after a grace period, it goes back to them instead of sitting here.
 */
class RefundUnclaimedPayments extends Command
{
    protected $signature = 'payments:refund-unclaimed {--minutes= : Grace period before refunding (default from config)}';

    protected $description = 'Refund payments that were captured but never turned into an order';

    public function handle(PaymentService $payments): int
    {
        $minutes = (int) ($this->option('minutes') ?: config('payments.unclaimed_refund_after_minutes'));

        $count = $payments->refundUnclaimed($minutes);

        $this->info("Refunded {$count} unclaimed payment(s) older than {$minutes} minutes.");

        return self::SUCCESS;
    }
}
