<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** One row of the audit trail. Append-only: nothing edits or deletes these. */
class AuditLog extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = ['actor_id', 'actor_role', 'action', 'subject_type', 'subject_id', 'summary', 'meta', 'ip', 'created_at'];

    protected function casts(): array
    {
        return ['meta' => 'array', 'created_at' => 'datetime'];
    }

    public function actor()
    {
        return $this->belongsTo(User::class, 'actor_id');
    }
}
