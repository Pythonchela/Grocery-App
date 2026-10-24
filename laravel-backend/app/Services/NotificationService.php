<?php

namespace App\Services;

use App\Mail\NotificationMail;
use App\Models\AppNotification;
use App\Models\User;
use App\Services\Messaging\SmsDeliveryException;
use App\Services\Messaging\SmsGatewayManager;
use App\Services\Messaging\SmsMessage;
use App\Services\Push\PushService;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

use function Illuminate\Support\defer;

/**
 * Single entry point for customer notifications.
 *
 * The in-app notification is persisted and drives the bell. Email and SMS follow it,
 * and are sent after the HTTP response has gone out (defer), so a slow or broken
 * provider can never hold up, or fail, the order or return that caused the message.
 * Failures are reported and swallowed here for the same reason.
 *
 * Deferring, rather than queueing, is deliberate: nothing in the deployment runs a
 * queue worker, and a queued email with no worker is an email that never arrives.
 */
class NotificationService
{
    public function __construct(private readonly SmsGatewayManager $sms) {}

    public function send(User $user, string $type, string $title, ?string $body = null, array $data = []): ?AppNotification
    {
        if (! $user->wantsNotification($type)) {
            return null;
        }

        $notification = AppNotification::create([
            'user_id' => $user->id,
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'data' => $data,
        ]);

        $this->dispatchEmail($user, $title, $body);
        $this->dispatchSms($user, $body ? "{$title}. {$body}" : $title);
        $this->dispatchPush($user, $notification, $title, $body, $data);

        return $notification;
    }

    public function orderPlaced($order): void
    {
        $this->send(
            $order->user,
            'ORDER_UPDATE',
            "Order {$order->order_number} confirmed",
            'Thanks for your order! We will notify you when it ships.',
            ['order_id' => $order->id, 'order_number' => $order->order_number],
        );
    }

    /**
     * Tell each seller their share of a new order, so they can start packing
     * without having to open the app to find out. A seller with no login (the
     * owner's own shop) has nobody to tell.
     */
    public function newSellerOrder($order): void
    {
        $order->loadMissing('items');

        foreach ($order->items->groupBy('seller_id') as $sellerId => $lines) {
            $seller = \App\Models\Seller::with('user')->find($sellerId);

            if (! $seller?->user) {
                continue;
            }

            $count = (int) $lines->sum('quantity');
            $earning = number_format((float) $lines->sum('seller_earning'), 2);

            $manual = $lines->contains(fn ($l) => $l->seller_response === 'PENDING');
            $minutes = \App\Services\SellerOrderDesk::acceptWindowMinutes();

            $this->send(
                $seller->user,
                'SELLER_ORDER',
                $manual
                    ? "New order {$order->order_number}: accept within {$minutes} min"
                    : "New order {$order->order_number}: {$count} ".($count === 1 ? 'item' : 'items').' to pack',
                $manual
                    ? "{$count} ".($count === 1 ? 'item' : 'items')." worth ₹{$earning} to you. Accept or decline it, or it is cancelled automatically."
                    : "You earn ₹{$earning}. Pack it, then tap Book courier.",
                // No order_id: that would send a tap to the shopper's order page.
                ['seller_order' => true, 'order_number' => $order->order_number],
            );
        }
    }

    public function orderStatusChanged($order, string $status): void
    {
        $labels = [
            'PACKED' => 'has been packed',
            'SHIPPED' => 'has shipped',
            'OUT_FOR_DELIVERY' => 'is out for delivery',
            'DELIVERED' => 'has been delivered',
            'CANCELLED' => 'was cancelled',
        ];

        if (! isset($labels[$status])) {
            return;
        }

        $this->send(
            $order->user,
            'ORDER_UPDATE',
            "Order {$order->order_number} {$labels[$status]}",
            $status === 'DELIVERED' ? 'Enjoy! You can now leave a verified review.' : null,
            ['order_id' => $order->id, 'order_number' => $order->order_number, 'status' => $status],
        );
    }

    public function refundUpdate($return, string $message): void
    {
        $this->send(
            $return->user,
            'REFUND',
            "Return {$return->rma_number}: {$message}",
            null,
            ['return_id' => $return->id, 'rma_number' => $return->rma_number, 'status' => $return->status],
        );
    }

    /**
     * Send the login OTP. Unlike everything else here this is synchronous and it
     * throws: the person is waiting for the code, so "we could not send it" has to
     * reach them instead of disappearing into a log.
     *
     * @throws SmsDeliveryException
     */
    public function sendOtp(string $phone, string $otp): void
    {
        $this->sms->gateway()->send(SmsMessage::otp($phone, $otp, (string) config('app.name')));
    }

    /**
     * Push to the user's phones. The notification row above is the source of
     * truth; this is only a nudge, so it is skipped when push is not configured
     * and never allowed to fail the caller.
     */
    private function dispatchPush(User $user, AppNotification $notification, string $title, ?string $body, array $data): void
    {
        $push = app(PushService::class);

        if (! $push->enabled()) {
            return;
        }

        $payload = $data + ['type' => $notification->type, 'notification_id' => $notification->id];

        $this->afterResponse(fn () => $push->notify($user, $title, $body, $payload), 'push');
    }

    private function dispatchEmail(User $user, string $subject, ?string $body): void
    {
        $to = $user->email;

        if (! $to || self::isPlaceholderAddress($to)) {
            return;
        }

        $this->afterResponse(fn () => Mail::to($to)->send(new NotificationMail($subject, $body)), 'email');
    }

    private function dispatchSms(User $user, string $message): void
    {
        $phone = self::nationalNumber($user->phone);

        if ($phone === null || ! $this->sms->sendsOrderUpdates()) {
            return;
        }

        $this->afterResponse(fn () => $this->sms->gateway()->send(SmsMessage::order($phone, $message)), 'sms');
    }

    /** Run after the response is sent; report, never throw. */
    private function afterResponse(callable $send, string $channel): void
    {
        defer(function () use ($send, $channel) {
            try {
                $send();
            } catch (Throwable $e) {
                // The class and channel only. A provider's message can carry an
                // address or a number.
                Log::warning("[NotificationService] {$channel} not sent", ['reason' => $e::class]);
                report($e);
            }
        });
    }

    /**
     * Accounts created by phone OTP are given `<phone>@example.com` because the
     * column is required. That address belongs to nobody (example.com is reserved),
     * and mailing it would only bounce. Reserved and test domains are skipped.
     */
    public static function isPlaceholderAddress(string $email): bool
    {
        $domain = strtolower(substr(strrchr($email, '@') ?: '', 1));

        return $domain === ''
            || in_array($domain, ['example.com', 'example.org', 'example.net', 'localhost'], true)
            || preg_match('/\.(test|invalid|example|localhost)$/', $domain) === 1;
    }

    /** The 10-digit national number, or null if this is not one. */
    public static function nationalNumber(?string $phone): ?string
    {
        $digits = preg_replace('/\D+/', '', (string) $phone) ?? '';

        if (strlen($digits) > 10) {
            $digits = substr($digits, -10);
        }

        return strlen($digits) === 10 ? $digits : null;
    }
}
