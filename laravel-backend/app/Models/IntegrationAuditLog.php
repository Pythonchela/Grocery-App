<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * An append-only record of a change (or attempted change) to integration
 * settings. Holds fingerprints, never values.
 */
class IntegrationAuditLog extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $fillable = [
        'user_id', 'action', 'group', 'field', 'outcome',
        'fingerprint_old', 'fingerprint_new', 'ip',
    ];

    protected function casts(): array
    {
        return ['created_at' => 'datetime'];
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
