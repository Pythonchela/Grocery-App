<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class BundleDeal extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'name',
        'description',
        'primary_product_id',
        'secondary_product_id',
        'bundle_price',
        'is_active',
        'expires_at'
    ];

    protected $casts = [
        'bundle_price' => 'decimal:2',
        'is_active' => 'boolean',
        'expires_at' => 'datetime'
    ];

    /** Active and not yet expired. */
    public function scopeLive($query)
    {
        return $query->where('is_active', true)
            ->where(fn ($q) => $q->whereNull('expires_at')->orWhere('expires_at', '>', now()));
    }

    public function primaryProduct()
    {
        return $this->belongsTo(Product::class, 'primary_product_id');
    }

    public function secondaryProduct()
    {
        return $this->belongsTo(Product::class, 'secondary_product_id');
    }
}
