<?php

namespace App\Services;

use App\Models\Order;
use App\Models\SupportMessage;
use App\Models\SupportTicket;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Tickets and what happens on them.
 *
 * The person who raised a ticket sees their own messages and the team's replies;
 * staff also see internal notes. A team reply moves a ticket to "waiting on you";
 * the requester's reply puts it back in the team's queue, even after it was
 * resolved. Every first reply is timed against the priority's target.
 */
class SupportService
{
    public function __construct(private readonly NotificationService $notifications) {}

    /** Higher priority for the categories where money or a livelihood waits. */
    public static function defaultPriority(string $category): string
    {
        return in_array($category, ['PAYMENT', 'REFUND', 'PAYOUT'], true) ? 'HIGH' : 'NORMAL';
    }

    public function slaDue(string $priority, ?\DateTimeInterface $from = null): \Illuminate\Support\Carbon
    {
        $hours = (int) config("support.first_response_hours.{$priority}", 24);

        return \Illuminate\Support\Carbon::instance($from ?? now())->addHours($hours);
    }

    /**
     * Open a ticket. An order may be named only if it is the requester's own
     * (a shopper's order, or one with a line from their shop).
     */
    public function open(User $user, string $category, string $subject, string $body, ?string $orderId = null): SupportTicket
    {
        $seller = $user->isSeller() ? $user->seller : null;

        if ($orderId && ! $this->mayDiscuss($user, $orderId)) {
            throw ValidationException::withMessages(['order_id' => ['That order is not yours.']]);
        }

        return DB::transaction(function () use ($user, $seller, $category, $subject, $body, $orderId) {
            $priority = self::defaultPriority($category);

            $ticket = SupportTicket::create([
                'number' => $this->nextNumber(),
                'user_id' => $user->id,
                'seller_id' => $seller?->id,
                'order_id' => $orderId,
                'category' => $category,
                'subject' => trim($subject),
                'status' => 'OPEN',
                'priority' => $priority,
                'last_message_at' => now(),
                'sla_due_at' => $this->slaDue($priority),
            ]);

            SupportMessage::create(['ticket_id' => $ticket->id, 'user_id' => $user->id, 'author' => 'REQUESTER', 'body' => trim($body)]);

            return $ticket;
        });
    }

    /** A message on a ticket. Staff may mark it internal; nobody else can. */
    public function reply(SupportTicket $ticket, User $author, string $body, bool $internal = false): SupportMessage
    {
        $staff = $author->isAdmin();

        if ($internal && ! $staff) {
            $internal = false;
        }

        if (! $staff && $ticket->status === 'CLOSED') {
            throw ValidationException::withMessages(['body' => ['This ticket is closed. Open a new one if you still need help.']]);
        }

        return DB::transaction(function () use ($ticket, $author, $body, $internal, $staff) {
            $message = SupportMessage::create([
                'ticket_id' => $ticket->id,
                'user_id' => $author->id,
                'author' => $staff ? 'STAFF' : 'REQUESTER',
                'body' => trim($body),
                'is_internal' => $internal,
            ]);

            $updates = ['last_message_at' => now()];

            if ($staff && ! $internal) {
                $updates['first_response_at'] = $ticket->first_response_at ?? now();
                $updates['status'] = 'WAITING_ON_REQUESTER';
                $updates['assigned_to'] = $ticket->assigned_to ?? $author->id;
            } elseif (! $staff) {
                // The requester wrote back: it is the team's turn, even if it had been resolved.
                $updates['status'] = 'OPEN';
                $updates['resolved_at'] = null;
            }

            $ticket->forceFill($updates)->save();

            if ($staff && ! $internal) {
                $this->notifications->send(
                    $ticket->user, 'SUPPORT', "Reply on {$ticket->number}", Str::limit(trim($body), 140),
                    ['support_ticket' => $ticket->id],
                );
            }

            return $message;
        });
    }

    /** Staff change status, priority or assignee. Returns what changed, for the audit trail. */
    public function update(SupportTicket $ticket, array $changes): array
    {
        $changed = [];

        foreach (['status', 'priority', 'assigned_to'] as $field) {
            if (array_key_exists($field, $changes) && $changes[$field] !== $ticket->{$field}) {
                $changed[$field] = [$ticket->{$field}, $changes[$field]];
                $ticket->{$field} = $changes[$field];
            }
        }

        if (isset($changed['status'])) {
            $ticket->resolved_at = in_array($ticket->status, ['RESOLVED', 'CLOSED'], true) ? ($ticket->resolved_at ?? now()) : null;
        }

        if (isset($changed['priority']) && $ticket->first_response_at === null) {
            // The clock restarts from when it was raised, at the new priority's target.
            $ticket->sla_due_at = $this->slaDue($ticket->priority, $ticket->created_at);
        }

        $ticket->save();

        if (isset($changed['status']) && $ticket->status === 'RESOLVED') {
            $this->notifications->send($ticket->user, 'SUPPORT', "{$ticket->number} was marked resolved", 'Reply if it is not sorted and we will pick it up again.', ['support_ticket' => $ticket->id]);
        }

        return $changed;
    }

    /** The requester says it is sorted. */
    public function closeByRequester(SupportTicket $ticket): SupportTicket
    {
        $ticket->forceFill(['status' => 'CLOSED', 'resolved_at' => $ticket->resolved_at ?? now()])->save();

        return $ticket;
    }

    public function rate(SupportTicket $ticket, int $rating, ?string $note): SupportTicket
    {
        if (! in_array($ticket->status, ['RESOLVED', 'CLOSED'], true)) {
            throw ValidationException::withMessages(['rating' => ['You can rate a ticket once it is resolved.']]);
        }

        $ticket->forceFill(['rating' => $rating, 'rating_note' => $note ? mb_substr($note, 0, 300) : null])->save();

        return $ticket;
    }

    /** Close resolved tickets nobody replied to for a few days. Returns how many. */
    public function closeStaleResolved(): int
    {
        return SupportTicket::where('status', 'RESOLVED')
            ->where('resolved_at', '<=', now()->subDays((int) config('support.auto_close_days', 7)))
            ->update(['status' => 'CLOSED']);
    }

    private function mayDiscuss(User $user, string $orderId): bool
    {
        $order = Order::find($orderId);

        if (! $order) {
            return false;
        }

        if ($order->user_id === $user->id) {
            return true;
        }

        $seller = $user->isSeller() ? $user->seller : null;

        return $seller !== null && $order->items()->where('seller_id', $seller->id)->exists();
    }

    private function nextNumber(): string
    {
        do {
            $number = 'TKT-'.strtoupper(Str::random(6));
        } while (SupportTicket::where('number', $number)->exists());

        return $number;
    }
}
