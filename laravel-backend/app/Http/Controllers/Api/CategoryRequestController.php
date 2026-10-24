<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\CategoryRequest;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class CategoryRequestController extends Controller
{
    public function sellerIndex(Request $request)
    {
        return response()->json(['status' => 'success', 'data' => CategoryRequest::with('category:id,name')
            ->where('seller_id', $request->user()->seller->id)->latest()->get()]);
    }

    public function sellerStore(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|min:2|max:120',
            'reason' => 'nullable|string|max:1000',
        ]);
        $data['name'] = trim($data['name']);
        $data['seller_id'] = $request->user()->seller->id;
        $duplicate = CategoryRequest::where('seller_id', $data['seller_id'])
            ->where('status', 'PENDING')->whereRaw('LOWER(name) = ?', [Str::lower($data['name'])])->exists();
        if ($duplicate) {
            throw ValidationException::withMessages(['name' => ['You already have a pending request for this category.']]);
        }

        $created = CategoryRequest::create($data);

        return response()->json(['status' => 'success', 'data' => $created], 201);
    }

    public function adminIndex(Request $request)
    {
        $status = $request->query('status');
        $rows = CategoryRequest::with(['seller:id,display_name', 'category:id,name'])
            ->when(in_array($status, ['PENDING', 'APPROVED', 'REJECTED'], true), fn ($q) => $q->where('status', $status))
            ->latest()->paginate(min(max((int) $request->query('per_page', 25), 1), 100));

        return response()->json(['status' => 'success', 'data' => $rows->items(), 'meta' => [
            'current_page' => $rows->currentPage(), 'last_page' => $rows->lastPage(), 'total' => $rows->total(),
        ]]);
    }

    public function decide(Request $request, string $id)
    {
        $data = $request->validate([
            'decision' => 'required|in:APPROVED,REJECTED',
            'admin_note' => 'nullable|string|max:1000',
            'category_id' => 'nullable|uuid|exists:categories,id',
        ]);

        return DB::transaction(function () use ($data, $id) {
            $row = CategoryRequest::lockForUpdate()->findOrFail($id);
            if ($row->status !== 'PENDING') {
                throw ValidationException::withMessages(['decision' => ['This request has already been reviewed.']]);
            }

            if ($data['decision'] === 'APPROVED') {
                $category = isset($data['category_id'])
                    ? Category::findOrFail($data['category_id'])
                    : Category::firstOrCreate(['slug' => Str::slug($row->name)], ['name' => $row->name]);
                $row->category_id = $category->id;
            }
            $row->status = $data['decision'];
            $row->admin_note = $data['admin_note'] ?? null;
            $row->save();

            return response()->json(['status' => 'success', 'data' => $row->load('category:id,name')]);
        });
    }
}
