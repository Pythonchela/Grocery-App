<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Log;

/**
 * The one way to write to the audit trail.
 *
 *     Audit::record($request->user(), 'payout.paid', $payoutRequest, 'Paid ₹2,500 to Asha Crafts', ['reference' => 'UTR1']);
 *
 * It never throws: a failure to write the trail must not undo (or block) the
 * action it describes, and is reported to the log instead. Keep `meta` to ids,
 * amounts and references; never secrets, full account numbers or passwords.
 */
final class Audit
{
    /**
     * @param  Model|array{0: string, 1: string}|null  $subject  a model, or [type, id]
     * @param  array<string, mixed>  $meta
     */
    public static function record(?User $actor, string $action, Model|array|null $subject, string $summary, array $meta = []): void
    {
        try {
            [$type, $id] = match (true) {
                $subject instanceof Model => [class_basename($subject), (string) $subject->getKey()],
                is_array($subject) => [$subject[0], $subject[1]],
                default => [null, null],
            };

            AuditLog::create([
                'actor_id' => $actor?->id,
                'actor_role' => $actor?->role,
                'action' => $action,
                'subject_type' => $type,
                'subject_id' => $id,
                'summary' => mb_substr($summary, 0, 300),
                'meta' => $meta === [] ? null : $meta,
                'ip' => request()?->ip(),
                'created_at' => now(),
            ]);
        } catch (\Throwable $e) {
            Log::warning('Audit log write failed: '.$e->getMessage(), ['action' => $action]);
        }
    }
}
