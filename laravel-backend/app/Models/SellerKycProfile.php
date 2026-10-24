<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * A merchant's identity and settlement details.
 *
 * PAN, GSTIN and the bank account number are encrypted at rest and hidden from
 * serialization. Nothing gets one of these onto the wire by accident: reading
 * them is an explicit call to `revealFor()`, which is only ever made by the
 * staff review endpoint. Everywhere else — including the seller's own dashboard
 * — sees `maskedAttributes()`.
 *
 * A seller re-reading their own PAN in full is not a feature; confirming the
 * last four digits is.
 */
#[Fillable([
    'business_type', 'legal_name', 'pan', 'gstin',
    'registered_line1', 'registered_line2', 'registered_city',
    'registered_state', 'registered_pincode',
    'bank_account_holder', 'bank_account_number', 'bank_ifsc', 'bank_name',
])]
// `pan_hash` is hidden alongside the values themselves. It isn't reversible,
// but it is a stable identifier derived from a government ID — two records
// carrying the same one are provably the same person, which is exactly the
// correlation this table exists to keep private.
#[Hidden(['pan', 'gstin', 'bank_account_number', 'pan_hash', 'pending_bank'])]
class SellerKycProfile extends Model
{
    use HasFactory, HasUuids;

    public const BUSINESS_TYPES = [
        'INDIVIDUAL', 'PROPRIETORSHIP', 'PARTNERSHIP', 'LLP', 'PRIVATE_LIMITED',
    ];

    /** Everything that must be present before this can be submitted. */
    public const REQUIRED_FIELDS = [
        'business_type', 'legal_name', 'pan',
        'registered_line1', 'registered_city', 'registered_state', 'registered_pincode',
        'bank_account_holder', 'bank_account_number', 'bank_ifsc',
    ];

    protected function casts(): array
    {
        return [
            // Laravel encrypts on write and decrypts on read. Losing APP_KEY
            // makes these unrecoverable, which is the intended property.
            'pan' => 'encrypted',
            'gstin' => 'encrypted',
            'bank_account_number' => 'encrypted',
            'pending_bank' => 'encrypted:array',
            'pending_bank_at' => 'datetime',
            'submitted_at' => 'datetime',
            'reviewed_at' => 'datetime',
        ];
    }

    public function seller()
    {
        return $this->belongsTo(Seller::class);
    }

    /**
     * Keyed hash used as a blind index on the PAN.
     *
     * HMAC rather than a bare sha256: a PAN has a narrow, well-known format, so
     * an unkeyed digest of one is brute-forceable in seconds. The key means an
     * attacker holding the table still can't confirm whether a given PAN is in
     * it.
     */
    public static function hashPan(string $pan): string
    {
        return hash_hmac('sha256', strtoupper(trim($pan)), config('app.key'));
    }

    /** Keeps the blind index in step with the encrypted value. */
    protected static function booted(): void
    {
        static::saving(function (self $profile) {
            if ($profile->isDirty('pan')) {
                $profile->pan_hash = filled($profile->pan) ? self::hashPan($profile->pan) : null;
            }
        });
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function isEditable(): bool
    {
        // Locked while staff are looking at it; reopened by a rejection.
        return in_array($this->status, ['DRAFT', 'REJECTED'], true);
    }

    public function isApproved(): bool
    {
        return $this->status === 'APPROVED';
    }

    /** Required fields still empty. Drives the onboarding checklist. */
    public function missingFields(): array
    {
        return array_values(array_filter(
            self::REQUIRED_FIELDS,
            fn ($field) => blank($this->{$field}),
        ));
    }

    /**
     * Safe for the seller's own dashboard: enough to recognise what was
     * entered, not enough to reconstruct it.
     */
    public function maskedAttributes(): array
    {
        return [
            'business_type' => $this->business_type,
            'legal_name' => $this->legal_name,
            'pan' => self::mask($this->pan, 4),
            'gstin' => self::mask($this->gstin, 4),
            'registered_line1' => $this->registered_line1,
            'registered_line2' => $this->registered_line2,
            'registered_city' => $this->registered_city,
            'registered_state' => $this->registered_state,
            'registered_pincode' => $this->registered_pincode,
            'bank_account_holder' => $this->bank_account_holder,
            'bank_account_number' => self::mask($this->bank_account_number, 4),
            'bank_ifsc' => $this->bank_ifsc,
            'bank_name' => $this->bank_name,
            'status' => $this->status,
            'submitted_at' => $this->submitted_at,
            'reviewed_at' => $this->reviewed_at,
            'rejection_reason' => $this->rejection_reason,
        ];
    }

    /**
     * The unmasked values, for a reviewer who has to check them against the
     * uploaded documents. Deliberately a named method rather than a property:
     * anything that reveals an identity number should be visible as a decision
     * at the call site.
     */
    public function revealFor(User $reviewer): array
    {
        return array_merge($this->maskedAttributes(), [
            'pan' => $this->pan,
            'gstin' => $this->gstin,
            'bank_account_number' => $this->bank_account_number,
            'revealed_to' => $reviewer->email,
        ]);
    }

    private static function mask(?string $value, int $keep): ?string
    {
        if (blank($value)) {
            return null;
        }

        if (strlen($value) <= $keep) {
            return str_repeat('•', strlen($value));
        }

        return str_repeat('•', strlen($value) - $keep).substr($value, -$keep);
    }
}
