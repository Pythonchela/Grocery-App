<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Storage;

/**
 * A KYC document a seller uploaded.
 *
 * `disk` and `path` are hidden from serialization on purpose. A response that
 * carries the storage path invites someone to try fetching it directly, and the
 * only supported way to read one of these is the authenticated download route
 * that checks who is asking.
 */
#[Fillable(['seller_id', 'kind', 'disk', 'path', 'original_name', 'mime', 'size_bytes', 'uploaded_by'])]
#[Hidden(['disk', 'path'])]
class SellerDocument extends Model
{
    use HasFactory, HasUuids;

    /** What a reviewer expects to see, by business type. */
    public const KINDS = [
        'PAN_CARD', 'GST_CERTIFICATE', 'CANCELLED_CHEQUE', 'ADDRESS_PROOF', 'INCORPORATION_CERT',
    ];

    /** Always required, whatever the business type. */
    public const REQUIRED_KINDS = ['PAN_CARD', 'CANCELLED_CHEQUE'];

    protected function casts(): array
    {
        return ['size_bytes' => 'integer'];
    }

    public function seller()
    {
        return $this->belongsTo(Seller::class);
    }

    public function exists(): bool
    {
        return Storage::disk($this->disk)->exists($this->path);
    }

    /** Removes the stored file alongside the row, so deletes don't leak files. */
    public function deleteWithFile(): void
    {
        Storage::disk($this->disk)->delete($this->path);
        $this->delete();
    }
}
