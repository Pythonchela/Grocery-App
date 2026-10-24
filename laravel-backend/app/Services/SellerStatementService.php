<?php

namespace App\Services;

use App\Models\Seller;
use App\Models\SellerLedgerEntry;
use Carbon\CarbonImmutable;
use Illuminate\Validation\ValidationException;

/**
 * A seller's month in money: what they sold, what was taken off, what was paid.
 *
 * Read entirely from the ledger, which is append-only, so a statement for a past
 * month never changes after the fact. Tax lines are what the ledger recorded at
 * the time, from the rates the marketplace had set then.
 */
class SellerStatementService
{
    public function period(string $month): array
    {
        if (! preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $month)) {
            throw ValidationException::withMessages(['month' => ['Use a month like 2026-10.']]);
        }

        $tz = config('marketplace.timezone', 'Asia/Kolkata');
        $start = CarbonImmutable::createFromFormat('!Y-m', $month, $tz)->startOfMonth();

        return [$start, $start->endOfMonth()];
    }

    /** Months (newest first) in which the seller has any ledger activity, plus the current one. */
    public function months(Seller $seller): array
    {
        $tz = config('marketplace.timezone', 'Asia/Kolkata');

        $months = SellerLedgerEntry::where('seller_id', $seller->id)->pluck('created_at')
            ->map(fn ($d) => CarbonImmutable::instance($d)->setTimezone($tz)->format('Y-m'))
            ->push(CarbonImmutable::now($tz)->format('Y-m'))
            ->unique()->sortDesc()->values()->all();

        return $months;
    }

    /** @return array<string, mixed> */
    public function forMonth(Seller $seller, string $month): array
    {
        [$start, $end] = $this->period($month);

        $entries = SellerLedgerEntry::where('seller_id', $seller->id)
            ->whereBetween('created_at', [$start->utc(), $end->utc()])
            ->with('order:id,order_number')
            ->orderBy('created_at')->orderBy('id')
            ->get();

        $before = SellerLedgerEntry::where('seller_id', $seller->id)
            ->where('created_at', '<', $start->utc())
            ->orderByDesc('created_at')->orderByDesc('id')
            ->first();

        $opening = (float) ($before?->balance_after ?? 0);
        $closing = (float) ($entries->last()?->balance_after ?? $opening);

        $sales = $entries->where('type', 'SALE');
        $refunds = $entries->where('type', 'REFUND');
        $sumOf = fn ($rows, string $col) => round((float) $rows->sum($col), 2);

        return [
            'month' => $month,
            'from' => $start->toDateString(),
            'to' => $end->toDateString(),
            'seller' => ['id' => $seller->id, 'name' => $seller->display_name],
            'opening_balance' => round($opening, 2),
            'closing_balance' => round($closing, 2),
            'orders' => $sales->pluck('order_id')->unique()->count(),
            'gross_sales' => $sumOf($sales, 'gross'),
            'refunds' => abs($sumOf($refunds, 'gross')),
            // Net of reversals: what the platform kept after refunds took part of it back.
            'commission' => round($sumOf($sales, 'commission') + $sumOf($refunds, 'commission'), 2),
            'gst_on_commission' => round($sumOf($sales, 'gst') + $sumOf($refunds, 'gst'), 2),
            'tcs' => round($sumOf($sales, 'tcs') + $sumOf($refunds, 'tcs'), 2),
            'tds' => round($sumOf($sales, 'tds') + $sumOf($refunds, 'tds'), 2),
            'earnings' => round($sumOf($sales, 'net') + $sumOf($refunds, 'net'), 2),
            'adjustments' => $sumOf($entries->where('type', 'ADJUSTMENT'), 'net'),
            'payouts' => abs($sumOf($entries->where('type', 'PAYOUT'), 'net')),
            'rows' => $entries->map(fn (SellerLedgerEntry $e) => [
                'date' => $e->created_at->setTimezone(config('marketplace.timezone', 'Asia/Kolkata'))->format('Y-m-d H:i'),
                'type' => $e->type,
                'order' => $e->order?->order_number,
                'note' => $e->note,
                'gross' => (float) $e->gross,
                'commission' => (float) $e->commission,
                'gst' => (float) $e->gst,
                'tcs' => (float) $e->tcs,
                'tds' => (float) $e->tds,
                'net' => (float) $e->net,
                'balance' => (float) $e->balance_after,
            ])->values()->all(),
        ];
    }

    /** The statement as CSV, opening in a spreadsheet. */
    public function csv(array $statement): string
    {
        $out = fopen('php://temp', 'r+');
        fwrite($out, "\xEF\xBB\xBF");

        $line = fn (array $row) => fputcsv($out, array_map(fn ($v) => self::safe($v), $row));

        $line(['Statement', $statement['seller']['name'], $statement['from'].' to '.$statement['to']]);
        foreach ([
            'Opening balance' => 'opening_balance', 'Orders' => 'orders', 'Gross sales' => 'gross_sales', 'Refunds' => 'refunds',
            'Commission' => 'commission', 'GST on commission' => 'gst_on_commission', 'TCS' => 'tcs', 'TDS' => 'tds',
            'Earnings' => 'earnings', 'Adjustments' => 'adjustments', 'Payouts' => 'payouts', 'Closing balance' => 'closing_balance',
        ] as $label => $key) {
            $line([$label, $statement[$key]]);
        }
        $line([]);
        $line(['Date', 'Type', 'Order', 'Note', 'Gross', 'Commission', 'GST', 'TCS', 'TDS', 'Net', 'Balance']);
        foreach ($statement['rows'] as $r) {
            $line([$r['date'], $r['type'], $r['order'], $r['note'], $r['gross'], $r['commission'], $r['gst'], $r['tcs'], $r['tds'], $r['net'], $r['balance']]);
        }

        rewind($out);

        return stream_get_contents($out);
    }

    /** A cell that starts with = + - @ would run as a formula in a spreadsheet. */
    private static function safe(mixed $value): mixed
    {
        return is_string($value) && preg_match('/^[=+\-@\t\r]/', $value) ? "'".$value : $value;
    }
}
