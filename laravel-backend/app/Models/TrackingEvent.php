<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'order_id', 'carrier', 'tracking_no', 'status', 'description', 'location',
    'lat', 'lng', 'occurred_at', 'source', 'raw', 'fingerprint',
])]
class TrackingEvent extends Model
{
    use HasUuids;

    protected function casts(): array
    {
        return [
            'occurred_at' => 'datetime',
            'raw' => 'array',
            'lat' => 'float',
            'lng' => 'float',
        ];
    }

    public function order()
    {
        return $this->belongsTo(Order::class);
    }
}
