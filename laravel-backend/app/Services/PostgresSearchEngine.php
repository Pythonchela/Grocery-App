<?php

namespace App\Services;

use App\Models\Product;
use App\Services\Contracts\SearchEngine;

class PostgresSearchEngine implements SearchEngine
{
    public function search(string $query, array $filters = [], string $sortBy = 'relevance'): array
    {
        $products = Product::query()
            ->where('status', 'ACTIVE');

        // Delegated to the model scopes the catalog endpoint uses, so the two
        // search paths can't drift apart on dialect handling or on which
        // products are considered matchable.
        if (! empty($query)) {
            $products->matchingSearch($query)->orderByRelevance($query);
        }

        // Apply filters
        if (!empty($filters['category_id'])) {
            $products->where('category_id', $filters['category_id']);
        }
        
        if (!empty($filters['min_price'])) {
            $products->where('price', '>=', $filters['min_price']);
        }

        if (!empty($filters['max_price'])) {
            $products->where('price', '<=', $filters['max_price']);
        }

        if (!empty($filters['brand'])) {
            $products->where('brand', $filters['brand']);
        }

        // Additional sorts (override relevance if specified)
        if ($sortBy === 'price_asc') {
            $products->reorder('price', 'asc');
        } elseif ($sortBy === 'price_desc') {
            $products->reorder('price', 'desc');
        } elseif ($sortBy === 'newest') {
            $products->reorder('created_at', 'desc');
        }

        // Return a paginated collection
        return $products->paginate(24)->toArray();
    }
}
