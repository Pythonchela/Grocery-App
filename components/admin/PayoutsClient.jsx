'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { Landmark, RefreshCw, AlertCircle, CheckCircle2, X } from 'lucide-react';
import { useAdminAuth } from './AdminAuthContext';
import { apiFetch, formatINR } from '../../lib/apiClient';
import PayoutRequestsPanel from './PayoutRequestsPanel';

/**
 * Who is owed what, and how much of it can be paid today.
 *
 * Sellers are paid by bank transfer outside the app. A vendor's balance is
 * split into what is still pending (the order is not delivered, or is inside the
 * return window) and what is payable now. Recording a transfer takes it off the
 * balance, against the bank's reference, and cannot exceed what is payable.
 */
export default function PayoutsClient() {
  const { token } = useAdminAuth();

  const [rows, setRows] = useState([]);
  const [totals, setTotals] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [paying, setPaying] = useState(null); // the row a transfer is being recorded for

  const load = useCallback(async () => {
    setLoading(true); setError('');
    try {
      const res = await apiFetch('/admin/payouts', { token });
      setRows(res.data || []);
      setTotals(res.totals || null);
    } catch (err) {
      setError(err.message);
    } finally { setLoading(false); }
  }, [token]);

  useEffect(() => { load(); }, [load]);

  return (
    <div className="space-y-4">
      <header className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-black text-ink flex items-center gap-2">
            <Landmark className="w-5 h-5 text-accent" /> Vendor payouts
          </h2>
          <p className="text-xs text-ink-muted font-medium mt-0.5">
            Earnings become payable once the order is delivered and the 7-day return window has passed.
          </p>
        </div>
        <button onClick={load} className="text-ink-subtle hover:text-ink" aria-label="Refresh">
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </header>

      {totals && (
        <div className="grid grid-cols-3 gap-3">
          {[
            ['Owed in all', totals.owed, 'text-ink'],
            ['Pending', totals.pending, 'text-warning'],
            ['Payable now', totals.withdrawable, 'text-success'],
          ].map(([label, value, tone]) => (
            <div key={label} className="bg-surface border border-line rounded-card p-3">
              <p className="text-[10px] font-bold uppercase tracking-wide text-ink-subtle">{label}</p>
              <p className={`text-lg font-black ${tone}`}>{formatINR(value)}</p>
            </div>
          ))}
        </div>
      )}

      <PayoutRequestsPanel token={token} sellers={rows} onChanged={load} />

      {notice && <p className="text-xs font-bold text-success flex items-center gap-1"><CheckCircle2 className="w-3.5 h-3.5" /> {notice}</p>}
      {error && <p className="text-xs font-bold text-danger flex items-center gap-1"><AlertCircle className="w-3.5 h-3.5" /> {error}</p>}

      {loading && rows.length === 0 ? (
        <div className="py-12 flex justify-center"><RefreshCw className="w-5 h-5 animate-spin text-accent" /></div>
      ) : rows.length === 0 ? (
        <div className="py-12 text-center text-ink-subtle">
          <Landmark className="w-8 h-8 mx-auto mb-2" />
          <p className="text-sm font-bold">No vendors yet</p>
        </div>
      ) : (
        <div className="space-y-2">
          {rows.map((r) => (
            <div key={r.id} className="p-3.5 border border-line rounded-card bg-surface space-y-2">
              <div className="flex items-start gap-3">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-black text-ink truncate">{r.name}</p>
                  <p className="text-[11px] text-ink-subtle font-semibold truncate">
                    {r.bank
                      ? `${r.bank.holder || ''} · ${r.bank.bank || ''} ${r.bank.ifsc || ''} · ••••${r.bank.account_last4}`
                      : <span className="text-warning">No bank details on file</span>}
                  </p>
                </div>
                <div className="grid grid-cols-3 gap-4 text-right shrink-0">
                  <div><p className="text-[10px] text-ink-subtle font-bold">Owed</p><p className="text-xs font-black text-ink">{formatINR(r.balance)}</p></div>
                  <div><p className="text-[10px] text-ink-subtle font-bold">Pending</p><p className="text-xs font-black text-warning">{formatINR(r.pending)}</p></div>
                  <div><p className="text-[10px] text-ink-subtle font-bold">Payable</p><p className="text-xs font-black text-success">{formatINR(r.withdrawable)}</p></div>
                </div>
                <button
                  onClick={() => { setPaying(r); setNotice(''); }}
                  disabled={r.withdrawable <= 0}
                  className="text-[11px] font-bold text-accent hover:underline disabled:text-ink-subtle disabled:no-underline shrink-0"
                >
                  Record payout
                </button>
              </div>
              {r.last_payout && (
                <p className="text-[11px] text-ink-subtle font-medium">
                  Last payout {formatINR(r.last_payout.amount)} · {new Date(r.last_payout.at).toLocaleDateString('en-IN')} · {r.last_payout.note}
                </p>
              )}
            </div>
          ))}
        </div>
      )}

      {paying && (
        <RecordPayout
          row={paying}
          token={token}
          onClose={() => setPaying(null)}
          onDone={(msg) => { setPaying(null); setNotice(msg); load(); }}
        />
      )}
    </div>
  );
}

/** The transfer made: how much, and the bank's reference for it. */
function RecordPayout({ row, token, onClose, onDone }) {
  const [amount, setAmount] = useState(String(row.withdrawable));
  const [reference, setReference] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async () => {
    setBusy(true); setError('');
    try {
      await apiFetch(`/admin/sellers/${row.id}/payouts`, {
        method: 'POST', token, body: { amount: Number(amount), reference: reference.trim() },
      });
      onDone(`Recorded ${formatINR(Number(amount))} paid to ${row.name}.`);
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-inverse/60 backdrop-blur-sm flex items-center justify-center p-4">
      <div role="dialog" aria-label={`Record a payout to ${row.name}`} className="w-full max-w-sm bg-surface border border-line rounded-panel p-5 space-y-3">
        <header className="flex items-start justify-between gap-3">
          <div>
            <h3 className="text-base font-black text-ink">Record a payout</h3>
            <p className="text-[11px] text-ink-subtle font-semibold">{row.name} · payable now {formatINR(row.withdrawable)}</p>
          </div>
          <button onClick={onClose} aria-label="Close" className="text-ink-subtle hover:text-ink"><X className="w-4 h-4" /></button>
        </header>

        <p className="text-[11px] text-ink-muted font-medium">
          Do the bank transfer first, then record it here. This takes the amount off what the vendor is owed.
        </p>

        {error && <p className="text-xs font-bold text-danger">{error}</p>}

        <label className="block">
          <span className="block text-[10px] font-bold text-ink-subtle uppercase mb-1">Amount (₹)</span>
          <input type="number" min="0" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)}
            className="w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-bold text-ink focus:outline-none focus:border-accent" />
        </label>
        <label className="block">
          <span className="block text-[10px] font-bold text-ink-subtle uppercase mb-1">Bank reference (UTR)</span>
          <input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="e.g. UTR 4382910234"
            className="w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-semibold text-ink focus:outline-none focus:border-accent" />
        </label>

        <button onClick={submit} disabled={busy || !Number(amount) || !reference.trim()} className="btn-primary text-sm py-2.5 px-5 w-full disabled:opacity-50">
          {busy ? 'Recording…' : 'Record payout'}
        </button>
      </div>
    </div>
  );
}
