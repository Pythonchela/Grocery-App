<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * A request for help from a shopper or a seller, handled by staff.
 *
 * OPEN: waiting for the team. IN_PROGRESS: someone is on it. WAITING_ON_REQUESTER:
 * the team asked a question. RESOLVED: the team says it is done (the requester
 * may reopen by replying, and it closes by itself after a few days). CLOSED: over.
 */
#[Fillable([
    'number', 'user_id', 'seller_id', 'order_id', 'category', 'subject', 'status', 'priority',
    'assigned_to', 'last_message_at', 'first_response_at', 'sla_due_at', 'resolved_at', 'rating', 'rating_note',
])]
class SupportTicket extends Model
{
    use HasUuids;

    public const CATEGORIES = [
        'ORDER_ISSUE', 'DELIVERY', 'PAYMENT', 'REFUND', 'PRODUCT', 'ACCOUNT', 'PAYOUT', 'SHOP_SETUP', 'OTHER',
    ];

    public const STATUSES = ['OPEN', 'IN_PROGRESS', 'WAITING_ON_REQUESTER', 'RESOLVED', 'CLOSED'];

    public const PRIORITIES = ['LOW', 'NORMAL', 'HIGH', 'URGENT'];

    protected function casts(): array
    {
        return [
            'last_message_at' => 'datetime',
            'first_response_at' => 'datetime',
            'sla_due_at' => 'datetime',
            'resolved_at' => 'datetime',
            'rating' => 'integer',
        ];
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function seller()
    {
        return $this->belongsTo(Seller::class);
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function assignee()
    {
        return $this->belongsTo(User::class, 'assigned_to');
    }

    public function messages()
    {
        return $this->hasMany(SupportMessage::class, 'ticket_id')->orderBy('created_at');
    }

    /** Still needs the team: neither resolved nor closed. */
    public function isActive(): bool
    {
        return ! in_array($this->status, ['RESOLVED', 'CLOSED'], true);
    }

    /** The team has not answered in time. */
    public function isOverdue(): bool
    {
        return $this->first_response_at === null
            && $this->isActive()
            && $this->sla_due_at !== null
            && $this->sla_due_at->isPast();
    }
}
