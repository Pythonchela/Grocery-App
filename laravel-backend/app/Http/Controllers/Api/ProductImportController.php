<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Services\Contracts\ProductParser;
use App\Services\Import\AiProductExtractor;
use App\Services\Import\ProductImporter;
use App\Support\ProductDetails;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ProductImportController extends Controller
{
    public function __construct(private ProductParser $parser) {}

    /**
     * Read uploaded files and pasted text into draft rows. Writes no products — the
     * owner reviews and edits every row before anything is created. Photos that
     * show a product are saved here, so the review can show them.
     *
     * The screen sends one file (or one group of photos) per request, which keeps
     * each call inside the server's time limit and lets it show progress.
     */
    public function parse(Request $request, ProductImporter $importer, AiProductExtractor $ai)
    {
        $validated = $request->validate([
            'files' => 'nullable|array|max:12',
            'files.*' => 'file|max:20480',
            'text' => 'nullable|string|max:500000',
            'hint' => 'nullable|string|max:500',
            'default_stock' => 'nullable|integer|min:0|max:100000',
            'category_id' => 'nullable|uuid|exists:categories,id',
        ]);

        if (empty($validated['files']) && trim((string) ($validated['text'] ?? '')) === '') {
            return response()->json(['status' => 'error', 'message' => 'Add a file, a photo or some text to read.'], 422);
        }

        // A long document read by AI can take a minute or two.
        @set_time_limit(240);

        $result = $importer->run($validated['files'] ?? [], $validated['text'] ?? null, [
            'hint' => $validated['hint'] ?? '',
            'default_stock' => $validated['default_stock'] ?? 10,
            'category_id' => $validated['category_id'] ?? null,
        ]);

        return response()->json(['status' => 'success', 'data' => $this->present($result) + [
            'ai_available' => $ai->available(),
        ]]);
    }

    /**
     * Dry run for pasted text: parse the blob and hand back draft rows with
     * per-field confidence and issues. Kept for clients that only have a string.
     */
    public function preview(Request $request, ProductImporter $importer, AiProductExtractor $ai)
    {
        $validated = $request->validate([
            'raw' => 'required|string|max:500000',
        ]);

        $result = $importer->run([], $validated['raw']);

        return response()->json(['status' => 'success', 'data' => $this->present($result) + [
            'ai_available' => $ai->available(),
        ]]);
    }

    /** The shape the review screen reads. */
    private function present(array $result): array
    {
        $rows = $result['rows'];
        $categories = Category::select('id', 'name', 'slug')->orderBy('name')->get()->map->only(['id', 'name', 'slug'])->all();

        // A title that collides with the catalogue or with another row gets a suffix on
        // commit; say so now.
        $slugs = array_filter(array_column($rows, 'slug'));
        $existing = $slugs ? Product::whereIn('slug', $slugs)->pluck('slug')->all() : [];
        $seen = [];

        foreach ($rows as &$row) {
            if (($row['slug'] ?? '') === '') {
                continue;
            }
            if (in_array($row['slug'], $existing, true)) {
                $row['issues'][] = 'A product with this URL slug already exists — it will be given a unique suffix.';
            }
            if (isset($seen[$row['slug']])) {
                $row['issues'][] = 'Duplicate of another row in this import.';
            }
            $seen[$row['slug']] = true;
        }
        unset($row);

        return [
            'format' => $result['format'],
            'driver' => $result['driver'],
            'total' => count($rows),
            'importable' => count(array_filter($rows, fn ($r) => $r['importable'])),
            'categories' => $categories,
            'rows' => $rows,
            'problems' => $result['problems'],
            'notes' => $result['notes'],
        ];
    }

    /**
     * Create the reviewed rows. All-or-nothing per request so a mid-list
     * failure can't leave a half-imported catalogue.
     */
    public function commit(Request $request)
    {
        $rules = [
            'rows' => 'required|array|min:1|max:500',
            'rows.*.title' => 'required|string|max:255',
            'rows.*.description' => 'nullable|string|max:20000',
            'rows.*.brand' => 'nullable|string|max:255',
            'rows.*.price' => 'required|numeric|min:0',
            'rows.*.mrp' => 'required|numeric|min:0',
            'rows.*.category_id' => 'required|uuid|exists:categories,id',
            'rows.*.images' => 'nullable|array|max:20',
            'rows.*.images.*' => 'string|max:1000',
            'rows.*.tags' => 'nullable|array|max:30',
            'rows.*.tags.*' => 'string|max:60',
            'rows.*.features' => 'nullable|array|max:30',
            'rows.*.features.*' => 'string|max:500',
            'rows.*.weight_grams' => 'nullable|integer|min:1|max:200000',
            'rows.*.length_cm' => 'nullable|integer|min:1|max:500',
            'rows.*.width_cm' => 'nullable|integer|min:1|max:500',
            'rows.*.height_cm' => 'nullable|integer|min:1|max:500',
            'rows.*.variants' => 'nullable|array|max:60',
            'rows.*.variants.*.color' => 'nullable|string|max:60',
            'rows.*.variants.*.size' => 'nullable|string|max:60',
            'rows.*.variants.*.sku' => 'nullable|string|max:80',
            'rows.*.variants.*.stock' => 'nullable|integer|min:0',
            'rows.*.variants.*.price' => 'nullable|numeric|min:0',
            'rows.*.variants.*.mrp' => 'nullable|numeric|min:0',
            'status' => 'nullable|in:DRAFT,ACTIVE',
            'seller_id' => 'nullable|uuid|exists:sellers,id',
        ];

        // The specification table and manufacturer panel follow the same limits as the product form.
        foreach (ProductDetails::rules() as $key => $rule) {
            if ($key !== 'description_html') {
                $rules['rows.*.'.$key] = $rule;
            }
        }

        $validated = $request->validate($rules);

        $status = $validated['status'] ?? 'DRAFT';

        // A live product needs a real price, exactly as when it is added by hand.
        if ($status === 'ACTIVE') {
            foreach ($validated['rows'] as $i => $row) {
                if ((float) $row['price'] <= 0 || (float) $row['mrp'] <= 0) {
                    return response()->json([
                        'status' => 'error',
                        'message' => '“'.$row['title'].'” has no price. Give it a price, or import as Draft.',
                    ], 422);
                }
            }
        }

        // The same importer serves staff and sellers. A seller can never choose
        // the destination shop, even by including seller_id in a crafted body.
        if (! $request->user()->isAdmin()) {
            $validated['seller_id'] = $request->user()->seller->id;
        }

        // A SKU that is already taken, or repeated in this batch, would fail the whole
        // import on the database's unique rule. Leave it blank instead.
        $asked = [];
        foreach ($validated['rows'] as $row) {
            foreach ($row['variants'] ?? [] as $v) {
                if (! empty($v['sku'])) {
                    $asked[] = $v['sku'];
                }
            }
        }
        $taken = $asked ? ProductVariant::whereIn('sku', $asked)->pluck('sku')->all() : [];
        $used = [];

        $created = [];

        try {
            DB::transaction(function () use ($validated, $status, &$created, $taken, &$used) {
                foreach ($validated['rows'] as $row) {
                    $product = Product::create([
                        'title' => $row['title'],
                        'slug' => $this->uniqueSlug($row['title']),
                        'description' => $row['description'] ?? null,
                        'brand' => $row['brand'] ?? null,
                        'category_id' => $row['category_id'],
                        // Staff may choose a shop; seller imports are forced to
                        // the signed-in seller's shop above.
                        'seller_id' => $validated['seller_id'] ?? \App\Models\Seller::house()->id,
                        'price' => $row['price'],
                        'mrp' => max($row['mrp'], $row['price']),
                        'images' => $row['images'] ?? [],
                        'tags' => $row['tags'] ?? [],
                        'features' => $row['features'] ?? [],
                        'specifications' => ProductDetails::specifications($row['specifications'] ?? null),
                        'manufacturer' => ProductDetails::manufacturer($row['manufacturer'] ?? null),
                        'weight_grams' => $row['weight_grams'] ?? null,
                        'length_cm' => $row['length_cm'] ?? null,
                        'width_cm' => $row['width_cm'] ?? null,
                        'height_cm' => $row['height_cm'] ?? null,
                        'status' => $status,
                        'is_new' => true,
                    ]);

                    $variants = $row['variants'] ?? [];
                    if (! $variants) {
                        $variants = [['color' => null, 'size' => 'Standard', 'stock' => 0, 'sku' => null]];
                    }

                    foreach ($variants as $v) {
                        $sku = ($v['sku'] ?? null) ?: null;
                        if ($sku !== null && (in_array($sku, $taken, true) || isset($used[$sku]))) {
                            $sku = null;
                        }
                        if ($sku !== null) {
                            $used[$sku] = true;
                        }

                        $product->variants()->create([
                            'color' => $v['color'] ?? null,
                            'size' => $v['size'] ?? null,
                            'sku' => $sku,
                            'stock' => $v['stock'] ?? 0,
                            'price' => $v['price'] ?? null,
                            'mrp' => $v['mrp'] ?? null,
                        ]);
                    }

                    $created[] = $product->id;
                }
            });
        } catch (\Throwable $e) {
            report($e);

            return response()->json([
                'status' => 'error',
                'message' => 'Import failed and was rolled back: '.$e->getMessage(),
            ], 422);
        }

        return response()->json([
            'status' => 'success',
            'message' => count($created).' product(s) imported as '.$status.'.',
            'data' => [
                'created' => count($created),
                'status' => $status,
                'products' => Product::with(['category', 'variants'])->whereIn('id', $created)->get(),
            ],
        ], 201);
    }

    /** Appends -2, -3… when the base slug is taken. */
    private function uniqueSlug(string $title): string
    {
        $base = Str::slug($title) ?: 'product';
        $slug = $base;
        $n = 2;

        while (Product::where('slug', $slug)->exists()) {
            $slug = $base.'-'.$n++;
        }

        return $slug;
    }
}
