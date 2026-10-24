<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SupportTicket;
use App\Models\User;
use App\Services\Audit;
use App\Services\SupportService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** The team's support inbox. Open to every staff role; the server decides, not the menu. */
class AdminSupportController extends Controller
{
    public function __construct(private readonly SupportService $support) {}

    public function index(Request $request)
    {
        $base = SupportTicket::query();

        $counts = [
            'open' => (clone $base)->whereIn('status', ['OPEN', 'IN_PROGRESS'])->count(),
            'waiting' => (clone $base)->where('status', 'WAITING_ON_REQUESTER')->count(),
            'overdue' => (clone $base)->whereNull('first_response_at')->whereNotIn('status', ['RESOLVED', 'CLOSED'])->where('sla_due_at', '<', now())->count(),
            'unassigned' => (clone $base)->whereNull('assigned_to')->whereNotIn('status', ['RESOLVED', 'CLOSED'])->count(),
        ];

        $query = SupportTicket::with(['user:id,name,email,role', 'seller:id,display_name', 'order:id,order_number', 'assignee:id,name'])
            ->orderByRaw("CASE priority WHEN 'URGENT' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END")
            ->orderBy('sla_due_at');

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        } elseif (! $request->boolean('all')) {
            $query->whereNotIn('status', ['RESOLVED', 'CLOSED']);
        }

        foreach (['category', 'priority'] as $field) {
            if ($request->filled($field)) {
                $query->where($field, $request->input($field));
            }
        }

        if ($request->boolean('mine')) {
            $query->where('assigned_to', $request->user()->id);
        }

        if ($request->boolean('unassigned')) {
            $query->whereNull('assigned_to');
        }

        if ($request->boolean('overdue')) {
            $query->whereNull('first_response_at')->where('sla_due_at', '<', now());
        }

        if ($request->filled('kind')) {
            $request->kind === 'seller' ? $query->whereNotNull('seller_id') : $query->whereNull('seller_id');
        }

        if ($request->filled('q')) {
            $term = '%'.str_replace(['%', '_'], ['\%', '\_'], trim($request->q)).'%';
            $query->where(fn ($q) => $q->where('number', 'like', $term)->orWhere('subject', 'like', $term)
                ->orWhereHas('user', fn ($u) => $u->where('email', 'like', $term)->orWhere('name', 'like', $term)));
        }

        return response()->json([
            'status' => 'success',
            'counts' => $counts,
            'data' => $query->limit(200)->get()->map(fn (SupportTicket $t) => $this->row($t))->values(),
        ]);
    }

    public function show(string $id)
    {
        $ticket = SupportTicket::with(['user:id,name,email,phone,role', 'seller:id,display_name', 'order.items.product:id,title', 'order.items.seller:id,display_name', 'assignee:id,name'])->find($id);

        if (! $ticket) {
            return response()->json(['status' => 'error', 'message' => 'Ticket not found'], 404);
        }

        return response()->json(['status' => 'success', 'data' => $this->row($ticket) + [
            'requester' => ['name' => $ticket->user?->name, 'email' => $ticket->user?->email, 'phone' => $ticket->user?->phone],
            'order' => $ticket->order ? [
                'id' => $ticket->order->id,
                'order_number' => $ticket->order->order_number,
                'status' => $ticket->order->status,
                'total_amount' => (float) $ticket->order->total_amount,
                'payment_method' => $ticket->order->payment_method,
                'items' => $ticket->order->items->map(fn ($i) => ['title' => $i->product?->title, 'quantity' => $i->quantity, 'shop' => $i->seller?->display_name])->values(),
            ] : null,
            'rating' => $ticket->rating,
            'rating_note' => $ticket->rating_note,
            'messages' => $ticket->messages()->with('user:id,name')->get()->map(fn ($m) => [
                'id' => $m->id,
                'author' => $m->author,
                'name' => $m->user?->name,
                'body' => $m->body,
                'internal' => $m->is_internal,
                'created_at' => $m->created_at?->toIso8601String(),
            ])->values(),
        ]]);
    }

    public function reply(Request $request, string $id)
    {
        $ticket = SupportTicket::find($id);

        if (! $ticket) {
            return response()->json(['status' => 'error', 'message' => 'Ticket not found'], 404);
        }

        $validated = $request->validate(['body' => 'required|string|min:1|max:4000', 'internal' => 'nullable|boolean']);
        $this->support->reply($ticket, $request->user(), $validated['body'], (bool) ($validated['internal'] ?? false));

        return $this->show($id);
    }

    public function update(Request $request, string $id)
    {
        $ticket = SupportTicket::find($id);

        if (! $ticket) {
            return response()->json(['status' => 'error', 'message' => 'Ticket not found'], 404);
        }

        $validated = $request->validate([
            'status' => ['sometimes', Rule::in(SupportTicket::STATUSES)],
            'priority' => ['sometimes', Rule::in(SupportTicket::PRIORITIES)],
            'assigned_to' => ['sometimes', 'nullable', 'uuid', Rule::exists('users', 'id')->whereIn('role', User::STAFF_ROLES)],
        ]);

        $changed = $this->support->update($ticket, $validated);

        if ($changed !== []) {
            Audit::record($request->user(), 'support.updated', $ticket, "Updated {$ticket->number}: ".implode(', ', array_keys($changed)), $changed);
        }

        return $this->show($id);
    }

    /** Staff who can take a ticket, for the assignee picker. */
    public function agents()
    {
        return response()->json(['status' => 'success', 'data' => User::whereIn('role', User::STAFF_ROLES)->where('status', 'ACTIVE')->orderBy('name')->get(['id', 'name', 'role'])]);
    }

    private function row(SupportTicket $t): array
    {
        return [
            'id' => $t->id,
            'number' => $t->number,
            'subject' => $t->subject,
            'category' => $t->category,
            'status' => $t->status,
            'priority' => $t->priority,
            'kind' => $t->seller_id ? 'SELLER' : 'CUSTOMER',
            'requester_name' => $t->user?->name,
            'requester_email' => $t->user?->email,
            'shop' => $t->seller?->display_name,
            'order_number' => $t->order?->order_number,
            'assigned_to' => $t->assigned_to,
            'assignee_name' => $t->assignee?->name,
            'sla_due_at' => $t->sla_due_at?->toIso8601String(),
            'first_response_at' => $t->first_response_at?->toIso8601String(),
            'overdue' => $t->isOverdue(),
            'last_message_at' => $t->last_message_at?->toIso8601String(),
            'created_at' => $t->created_at?->toIso8601String(),
        ];
    }
}
