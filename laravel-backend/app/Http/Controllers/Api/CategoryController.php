<?php

namespace App\Http\Controllers\Api;

use App\Support\ProductDetails;
use App\Services\Options\ProductOptions;
use App\Services\Options\VariantSetup;
use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Product;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class CategoryController extends Controller
{
    public function index(Request $request)
    {
        $query = Category::withCount('products')->orderBy('sort_order');

        if ($request->boolean('tree')) {
            $categories = $query->whereNull('parent_id')->with('children')->get();
        } else {
            $categories = $query->get();
        }

        $this->withCoverImages($categories);

        return response()->json(['status' => 'success', 'count' => $categories->count(), 'data' => $categories]);
    }

    /**
     * Every category gets a picture to show in lists: the one the admin uploaded
     * (`image_url`), or - until they do - a photo of something in it.
     * `cover_image_url` is that answer, so apps never show a bare icon for a
     * category that has products.
     *
     * @param  \Illuminate\Support\Collection<int, Category>  $categories
     */
    private function withCoverImages($categories): void
    {
        $flat = $categories->flatMap(fn (Category $c) => collect([$c])->merge($c->relationLoaded('children') ? $c->children : []));
        $missing = $flat->filter(fn (Category $c) => blank($c->image_url))->pluck('id')->all();

        $fallback = [];
        if ($missing !== []) {
            Product::whereIn('category_id', $missing)
                ->where('status', 'ACTIVE')
                ->orderBy('created_at')
                ->get(['id', 'category_id', 'images'])
                ->each(function (Product $p) use (&$fallback) {
                    $image = collect($p->images ?? [])->first(fn ($i) => filled($i));
                    if ($image && ! isset($fallback[$p->category_id])) {
                        $fallback[$p->category_id] = $image;
                    }
                });
        }

        foreach ($flat as $category) {
            $category->setAttribute('cover_image_url', filled($category->image_url) ? $category->image_url : ($fallback[$category->id] ?? null));
        }
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'slug' => 'nullable|string|unique:categories,slug',
            'parent_id' => 'nullable|uuid|exists:categories,id',
            'icon_url' => 'nullable|string',
            'image_url' => 'nullable|string|max:2048',
            'banner_url' => 'nullable|string',
            'filter_config' => 'nullable|array',
            'option_groups' => 'nullable|array',
            ...VariantSetup::RULES,
            ...ProductDetails::templateRules(),
            'delivery_profile' => 'nullable|in:instant,parcel,heavy',
            'prep_minutes' => 'nullable|integer|min:0|max:1440',
            'sort_order' => 'nullable|integer',
            'is_featured' => 'nullable|boolean',
        ]);

        $validated['slug'] = $validated['slug'] ?? Str::slug($validated['name']);
        $validated = $this->withCleanOptions($validated);

        $category = Category::create($validated);

        return response()->json(['status' => 'success', 'data' => $category], 201);
    }

    /** The option template, in canonical form. No stock: a template is shared by many products. */
    private function withCleanOptions(array $validated): array
    {
        if (isset($validated['option_groups'])) {
            $validated['option_groups'] = ProductOptions::normalize($validated['option_groups']);
        }

        if (array_key_exists('variant_setup', $validated)) {
            $validated['variant_setup'] = VariantSetup::normalize($validated['variant_setup']);
        }

        if (array_key_exists('spec_template', $validated)) {
            $validated['spec_template'] = ProductDetails::template($validated['spec_template']);
        }

        return $validated;
    }

    public function show($id)
    {
        $category = Category::with('children')->find($id);

        if (! $category) {
            return response()->json(['status' => 'error', 'message' => 'Category not found'], 404);
        }

        return response()->json(['status' => 'success', 'data' => $category]);
    }

    public function update(Request $request, $id)
    {
        $category = Category::find($id);

        if (! $category) {
            return response()->json(['status' => 'error', 'message' => 'Category not found'], 404);
        }

        $validated = $request->validate([
            'name' => 'sometimes|string|max:255',
            'slug' => ['sometimes', 'string', Rule::unique('categories', 'slug')->ignore($category->id)],
            'parent_id' => 'nullable|uuid|exists:categories,id|not_in:'.$category->id,
            'icon_url' => 'nullable|string',
            'image_url' => 'nullable|string|max:2048',
            'banner_url' => 'nullable|string',
            'filter_config' => 'nullable|array',
            'option_groups' => 'nullable|array',
            ...VariantSetup::RULES,
            ...ProductDetails::templateRules(),
            'delivery_profile' => 'nullable|in:instant,parcel,heavy',
            'prep_minutes' => 'nullable|integer|min:0|max:1440',
            'sort_order' => 'nullable|integer',
            'is_featured' => 'nullable|boolean',
        ]);

        $category->update($this->withCleanOptions($validated));

        return response()->json(['status' => 'success', 'data' => $category]);
    }

    public function destroy($id)
    {
        $category = Category::withCount(['products', 'children'])->find($id);

        if (! $category) {
            return response()->json(['status' => 'error', 'message' => 'Category not found'], 404);
        }

        if ($category->products_count > 0) {
            return response()->json([
                'status' => 'error',
                'message' => "Cannot delete category '{$category->name}' because it contains {$category->products_count} active product(s). Please delete or reassign those products first."
            ], 422);
        }

        if ($category->children_count > 0) {
            return response()->json([
                'status' => 'error',
                'message' => "Cannot delete category '{$category->name}' because it contains sub-categories. Please reassign or delete the sub-categories first."
            ], 422);
        }

        try {
            $category->delete();
            return response()->json(['status' => 'success', 'message' => 'Category deleted successfully']);
        } catch (\Exception $e) {
            return response()->json([
                'status' => 'error',
                'message' => 'Failed to delete category due to associated database items: '.$e->getMessage()
            ], 422);
        }
    }
}
