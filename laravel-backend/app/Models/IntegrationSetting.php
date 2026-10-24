<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * One admin-managed setting, stored encrypted.
 *
 * Deliberately dumb: it does not encrypt or decrypt anything itself, and there is
 * no accessor that hands the value back. Sealing and opening live in
 * App\Integrations\IntegrationSettings, so the plaintext has exactly one place to
 * come from and nothing serialises a model into a response or a log by accident.
 */
class IntegrationSetting extends Model
{
    protected $primaryKey = 'key';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = ['key', 'value', 'updated_by'];

    // Whatever else happens to this model — toArray, toJson, a dump in a log —
    // the stored payload does not come along.
    protected $hidden = ['value'];
}
