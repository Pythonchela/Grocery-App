<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\Request;

/** Read-only view of the audit trail, for full admins. */
class AuditLogController extends Controller
{
    public function index(Request $request)
    {
        $query = AuditLog::with('actor:id,name,email')->orderByDesc('created_at')->orderByDesc('id');

        if ($request->filled('action')) {
            // "payout" matches payout.paid, payout.declined, ...
            $query->where('action', 'like', str_replace(['%', '_'], ['\%', '\_'], $request->action).'%');
        }

        if ($request->filled('actor')) {
            $query->where('actor_id', $request->actor);
        }

        if ($request->filled('from')) {
            $query->where('created_at', '>=', $request->date('from')->startOfDay());
        }

        if ($request->filled('to')) {
            $query->where('created_at', '<=', $request->date('to')->endOfDay());
        }

        if ($request->filled('q')) {
            $term = '%'.str_replace(['%', '_'], ['\%', '\_'], trim($request->q)).'%';
            $query->where(fn ($q) => $q->where('summary', 'like', $term)->orWhere('subject_id', 'like', $term));
        }

        $perPage = min((int) $request->get('per_page', 50), 200);
        $page = $query->paginate($perPage)->withQueryString();

        return response()->json([
            'status' => 'success',
            'data' => collect($page->items())->map(fn (AuditLog $l) => [
                'id' => $l->id,
                'at' => $l->created_at?->toIso8601String(),
                'actor' => $l->actor?->name ?? ($l->actor_id ? 'Unknown user' : 'System'),
                'actor_email' => $l->actor?->email,
                'actor_role' => $l->actor_role,
                'action' => $l->action,
                'subject_type' => $l->subject_type,
                'subject_id' => $l->subject_id,
                'summary' => $l->summary,
                'meta' => $l->meta,
                'ip' => $l->ip,
            ])->values(),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
        ]);
    }
}
