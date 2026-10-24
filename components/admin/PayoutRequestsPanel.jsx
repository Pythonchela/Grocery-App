'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { apiDownload, apiFetch, formatINR } from '../../lib/apiClient';

const field = 'w-full bg-surface border border-line rounded-control px-3 py-2 text-xs font-semibold text-ink';
const act = 'text-[11px] font-bold hover:underline disabled:opacity-50';

function bankLine(b) {
  return b ? `${b.holder || ''} · ${b.bank || ''} ${b.ifsc || ''} · ••••${b.account_last4}` : 'No bank details on file';
}

/**
 * What sellers have asked of the team: payouts to send, bank-account changes
 * to confirm, and statements to download. Each is a decision a person makes.
 */
export default function PayoutRequestsPanel({ token, sellers = [], onChanged }) {
  const [requests, setRequests] = useState([]);
  const [changes, setChanges] = useState([]);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState('');
  const [reference, setReference] = useState({});
  const [reason, setReason] = useState({});
  const [stmtSeller, setStmtSeller] = useState('');
  const [stmtMonth, setStmtMonth] = useState(new Date().toISOString().slice(0, 7));

  const load = useCallback(async () => {
    try {
      const [r, b] = await Promise.all([
        apiFetch('/admin/payout-requests?status=REQUESTED', { token }),
        apiFetch('/admin/bank-changes', { token }),
      ]);
      setRequests(r.data || []); setChanges(b.data || []);
    } catch (e) { setError(e.message); }
  }, [token]);

  useEffect(() => { load(); }, [load]);

  const run = async (key, fn, done) => {
    setBusy(key); setError(''); setNotice('');
    try { await fn(); setNotice(done); await load(); onChanged?.(); }
    catch (e) { setError(e.message); }
    finally { setBusy(''); }
  };

  return (
    <section className="space-y-4" aria-label="Seller requests">
      {notice && <p role="status" className="text-xs font-bold text-success">{notice}</p>}
      {error && <p role="alert" className="text-xs font-bold text-danger">{error}</p>}

      <div className="space-y-2">
        <h3 className="text-sm font-black text-ink">Payout requests ({requests.length})</h3>
        {requests.length === 0 && <p className="text-xs text-ink-muted">No payouts are waiting.</p>}
        {requests.map((r) => (
          <div key={r.id} className="p-3.5 border border-line rounded-card bg-surface space-y-2">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="text-sm font-black text-ink">{r.seller_name} · {formatINR(r.amount)}</p>
                <p className="text-[11px] text-ink-subtle font-semibold">{bankLine(r.bank)} · payable now {formatINR(r.withdrawable)}</p>
                {r.note && <p className="text-[11px] text-ink-muted">“{r.note}”</p>}
                {r.bank_change_pending && <p className="text-[11px] font-bold text-warning">A bank change is waiting for confirmation: settle that first.</p>}
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <input aria-label={`Bank reference for ${r.seller_name}`} className={`${field} max-w-48`} placeholder="Bank reference (UTR)" value={reference[r.id] || ''} onChange={(e) => setReference((v) => ({ ...v, [r.id]: e.target.value }))} />
              <button className={`${act} text-success`} disabled={busy === r.id || !(reference[r.id] || '').trim()}
                onClick={() => run(r.id, () => apiFetch(`/admin/payout-requests/${r.id}/pay`, { method: 'POST', token, body: { reference: reference[r.id].trim() } }), `Recorded as paid to ${r.seller_name}.`)}>Mark paid</button>
              <input aria-label={`Reason to decline ${r.seller_name}`} className={`${field} max-w-48`} placeholder="Reason to decline" value={reason[r.id] || ''} onChange={(e) => setReason((v) => ({ ...v, [r.id]: e.target.value }))} />
              <button className={`${act} text-danger`} disabled={busy === r.id || !(reason[r.id] || '').trim()}
                onClick={() => run(r.id, () => apiFetch(`/admin/payout-requests/${r.id}/reject`, { method: 'POST', token, body: { reason: reason[r.id].trim() } }), 'Request declined.')}>Decline</button>
            </div>
            <p className="text-[11px] text-ink-muted">Do the bank transfer first, then mark it paid with the bank&apos;s reference.</p>
          </div>
        ))}
      </div>

      <div className="space-y-2">
        <h3 className="text-sm font-black text-ink">Bank account changes ({changes.length})</h3>
        {changes.length === 0 && <p className="text-xs text-ink-muted">No bank changes are waiting.</p>}
        {changes.map((c) => (
          <div key={c.seller_id} className="p-3.5 border border-line rounded-card bg-surface space-y-2">
            <p className="text-sm font-black text-ink">{c.seller_name}</p>
            <p className="text-[11px] text-ink-subtle font-semibold">Now: {bankLine(c.current)}</p>
            <p className="text-[11px] text-ink font-bold">New: {bankLine(c.proposed)}</p>
            <div className="flex flex-wrap items-center gap-2">
              <button className={`${act} text-success`} disabled={busy === c.seller_id}
                onClick={() => run(c.seller_id, () => apiFetch(`/admin/sellers/${c.seller_id}/bank-change/approve`, { method: 'POST', token }), 'Bank details confirmed.')}>Confirm change</button>
              <input aria-label={`Reason not to confirm ${c.seller_name}`} className={`${field} max-w-56`} placeholder="Reason not to confirm" value={reason[c.seller_id] || ''} onChange={(e) => setReason((v) => ({ ...v, [c.seller_id]: e.target.value }))} />
              <button className={`${act} text-danger`} disabled={busy === c.seller_id || !(reason[c.seller_id] || '').trim()}
                onClick={() => run(c.seller_id, () => apiFetch(`/admin/sellers/${c.seller_id}/bank-change/reject`, { method: 'POST', token, body: { reason: reason[c.seller_id].trim() } }), 'Change declined.')}>Decline</button>
            </div>
            <p className="text-[11px] text-ink-muted">Check the new account with the seller outside the app before confirming.</p>
          </div>
        ))}
      </div>

      <div className="space-y-2">
        <h3 className="text-sm font-black text-ink">Seller statement</h3>
        <div className="flex flex-wrap gap-2">
          <select aria-label="Seller" className={`${field} max-w-60`} value={stmtSeller} onChange={(e) => setStmtSeller(e.target.value)}>
            <option value="">Choose a seller</option>
            {sellers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
          <input type="month" aria-label="Month" className={`${field} max-w-40`} value={stmtMonth} onChange={(e) => setStmtMonth(e.target.value)} />
          <button className={`${act} text-accent`} disabled={!stmtSeller || !stmtMonth}
            onClick={() => apiDownload(`/admin/sellers/${stmtSeller}/statements/${stmtMonth}/csv`, { token, filename: `statement-${stmtMonth}.csv` }).catch((e) => setError(e.message))}>Download CSV</button>
        </div>
      </div>
    </section>
  );
}
