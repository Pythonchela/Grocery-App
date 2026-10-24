<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SupportTicket;
use App\Services\SupportService;
use Illuminate\Http\Request;

/**
 * Help for shoppers and sellers: raise a ticket, follow it, reply, say it is
 * sorted, rate how it went. Everything is scoped to the caller's own tickets,
 * and staff-only internal notes are never returned.
 */
class SupportController extends Controller
{
    public function __construct(private readonly SupportService $support) {}

    public function index(Request $request)
    {
        $query = SupportTicket::where('user_id', $request->user()->id)
            ->with('order:id,order_number')
            ->orderByDesc('last_message_at');

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        return response()->json(['status' => 'success', 'data' => $query->limit(100)->get()->map(fn ($t) => $this->summary($t))->values()]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'category' => 'required|in:'.implode(',', SupportTicket::CATEGORIES),
            'subject' => 'required|string|min:3|max:160',
            'message' => 'required|string|min:3|max:4000',
            'order_id' => 'nullable|uuid',
        ]);

        $ticket = $this->support->open($request->user(), $validated['category'], $validated['subject'], $validated['message'], $validated['order_id'] ?? null);

        return response()->json(['status' => 'success', 'data' => $this->detail($ticket->fresh())], 201);
    }

    public function show(Request $request, string $id)
    {
        $ticket = $this->own($request, $id);

        return $ticket
            ? response()->json(['status' => 'success', 'data' => $this->detail($ticket)])
            : response()->json(['status' => 'error', 'message' => 'Ticket not found'], 404);
    }

    public function reply(Request $request, string $id)
    {
        $ticket = $this->own($request, $id);

        if (! $ticket) {
            return response()->json(['status' => 'error', 'message' => 'Ticket not found'], 404);
        }

        $validated = $request->validate(['body' => 'required|string|min:1|max:4000']);
        $this->support->reply($ticket, $request->user(), $validated['body']);

        return response()->json(['status' => 'success', 'data' => $this->detail($ticket->fresh())], 201);
    }

    public function close(Request $request, string $id)
    {
        $ticket = $this->own($request, $id);

        if (! $ticket) {
            return response()->json(['status' => 'error', 'message' => 'Ticket not found'], 404);
        }

        return response()->json(['status' => 'success', 'data' => $this->detail($this->support->closeByRequester($ticket))]);
    }

    public function rate(Request $request, string $id)
    {
        $ticket = $this->own($request, $id);

        if (! $ticket) {
            return response()->json(['status' => 'error', 'message' => 'Ticket not found'], 404);
        }

        $validated = $request->validate(['rating' => 'required|integer|between:1,5', 'note' => 'nullable|string|max:300']);

        return response()->json(['status' => 'success', 'data' => $this->detail($this->support->rate($ticket, (int) $validated['rating'], $validated['note'] ?? null))]);
    }

    private function own(Request $request, string $id): ?SupportTicket
    {
        return SupportTicket::where('user_id', $request->user()->id)->find($id);
    }

    private function summary(SupportTicket $t): array
    {
        return [
            'id' => $t->id,
            'number' => $t->number,
            'subject' => $t->subject,
            'category' => $t->category,
            'status' => $t->status,
            'order_number' => $t->order?->order_number,
            'last_message_at' => $t->last_message_at?->toIso8601String(),
            'created_at' => $t->created_at?->toIso8601String(),
        ];
    }

    private function detail(SupportTicket $t): array
    {
        $t->loadMissing('order:id,order_number');

        return $this->summary($t) + [
            'rating' => $t->rating,
            'messages' => $t->messages()->where('is_internal', false)->get()->map(fn ($m) => [
                'id' => $m->id,
                'author' => $m->author,
                'body' => $m->body,
                'created_at' => $m->created_at?->toIso8601String(),
            ])->values(),
        ];
    }
}
