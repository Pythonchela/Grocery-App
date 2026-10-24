<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\OrderItem;
use App\Services\SellerOrderDesk;
use Illuminate\Http\Request;

/**
 * The operations board: every order that is still moving, with the clocks that
 * matter — which shop has not answered, which parcel is late to pack, which
 * order has passed the delivery time promised to the customer.
 */
class AdminLiveOrderController extends Controller
{
    private const OPEN = ['CONFIRMED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY'];

    public function index()
    {
        $orders = Order::whereIn('status', self::OPEN)
            ->with([
                'user:id,name,phone',
                'items:id,order_id,product_id,seller_id,quantity,fulfilment_status,seller_response,accept_by,ready_by,rejection_reason',
                'items.product:id,title',
                'items.seller:id,display_name,is_house',
            ])
            ->orderBy('created_at')
            ->limit(200)
            ->get();

        $now = now();
        $rows = $orders->map(fn (Order $o) => $this->row($o, $now))->values();

        return response()->json([
            'status' => 'success',
            'server_time' => $now->toIso8601String(),
            'counts' => [
                'awaiting_seller' => $rows->where('stage', 'awaiting_seller')->count(),
                'to_pack' => $rows->where('stage', 'to_pack')->count(),
                'in_transit' => $rows->where('stage', 'in_transit')->count(),
                'late_to_pack' => $rows->where('late_to_pack', true)->count(),
                'overdue' => $rows->where('overdue', true)->count(),
            ],
            'data' => $rows,
        ]);
    }

    /** Turn a shop's line down on its behalf (the shop is unreachable, say). */
    public function rejectItem(Request $request, string $id, SellerOrderDesk $desk)
    {
        $item = OrderItem::find($id);

        if (! $item) {
            return response()->json(['status' => 'error', 'message' => 'Order item not found'], 404);
        }

        $validated = $request->validate([
            'reason' => 'required|in:'.implode(',', SellerOrderDesk::REASONS),
            'note' => 'nullable|string|max:300',
        ]);

        $desk->decline($item, $validated['reason'], $validated['note'] ?? null, 'ADMIN');
        \App\Services\Audit::record($request->user(), 'order.line_declined', $item, 'Declined an order line on a shop\'s behalf', ['order_id' => $item->order_id, 'reason' => $validated['reason']]);

        return response()->json(['status' => 'success', 'data' => $item->fresh()]);
    }

    private function row(Order $order, $now): array
    {
        $live = $order->items->where('seller_response', '!=', 'REJECTED');

        $waiting = $live->where('seller_response', 'PENDING');
        $late = $live->filter(fn ($i) => $i->seller_response === 'ACCEPTED'
            && $i->fulfilment_status === 'PENDING'
            && $i->ready_by && $i->ready_by->lt($now));

        $stage = match (true) {
            in_array($order->status, ['SHIPPED', 'OUT_FOR_DELIVERY'], true) => 'in_transit',
            $waiting->isNotEmpty() => 'awaiting_seller',
            default => 'to_pack',
        };

        return [
            'id' => $order->id,
            'order_number' => $order->order_number,
            'status' => $order->status,
            'stage' => $stage,
            'payment_method' => $order->payment_method,
            'payment_status' => $order->payment_status,
            'total_amount' => (float) $order->total_amount,
            'created_at' => $order->created_at?->toIso8601String(),
            'promised_by' => $order->promised_by?->toIso8601String(),
            'accept_by' => $waiting->min('accept_by')?->toIso8601String(),
            'late_to_pack' => $late->isNotEmpty(),
            'overdue' => $order->promised_by !== null && $order->promised_by->lt($now),
            'customer' => ['name' => $order->user?->name, 'phone' => $order->user?->phone],
            'city' => $order->shipping_address['city'] ?? null,
            'items' => $order->items->map(fn ($i) => [
                'id' => $i->id,
                'title' => $i->product?->title,
                'quantity' => $i->quantity,
                'shop' => $i->seller?->display_name,
                'seller_response' => $i->seller_response,
                'fulfilment_status' => $i->fulfilment_status,
                'accept_by' => $i->accept_by?->toIso8601String(),
                'ready_by' => $i->ready_by?->toIso8601String(),
                'rejection_reason' => $i->rejection_reason,
            ])->values(),
        ];
    }
}
