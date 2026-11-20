<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable(['name', 'slug', 'parent_id', 'icon_url', 'image_url', 'banner_url', 'filter_config', 'option_groups', 'variant_setup', 'spec_template', 'delivery_profile', 'prep_minutes', 'sort_order', 'is_featured'])]
class Category extends Model
{
    use HasFactory, HasUuids;

    protected function casts(): array
    {
        return [
            'filter_config' => 'array',
            'option_groups' => 'array',
            'variant_setup' => 'array',
            'spec_template' => 'array',
            'is_featured' => 'boolean',
        ];
    }

    public function parent()
    {
        return $this->belongsTo(Category::class, 'parent_id');
    }

    public function children()
    {
        return $this->hasMany(Category::class, 'parent_id');
    }

    public function products()
    {
        return $this->hasMany(Product::class);
    }
}
