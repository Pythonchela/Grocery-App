'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '../../lib/apiClient';
import { useAdminAuth } from './AdminAuthContext';

const GROUPS = [
  ['', 'Everything'], ['payout', 'Payouts'], ['bank', 'Bank accounts'], ['seller', 'Sellers'], ['order', 'Orders'],
  ['return', 'Returns'], ['wallet', 'Wallets'], ['user', 'People & access'], ['staff', 'Staff'], ['settings', 'Settings'], ['support', 'Support'],
];
const field = 'bg-surface border border-line rounded-control px-3 py-2 text-xs font-semibold text-ink';

/** Who did what to money, access and orders. Read-only, newest first. */
export default function AuditLogClient() {
  const { token } = useAdminAuth();
  const [group, setGroup] = useState('');
  const [q, setQ] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState([]);
  const [meta, setMeta] = useState({ last_page: 1, total: 0 });
  const [error, setError] = useState('');
  const [open, setOpen] = useState(null);

  const load = useCallback(async () => {
    const params = new URLSearchParams({ page: String(page), per_page: '50' });
    if (group) params.set('action', group);
    if (q.trim()) params.set('q', q.trim());
    if (from) params.set('from', from);
    if (to) params.set('to', to);
    try { const res = await apiFetch(`/admin/audit-logs?${params}`, { token }); setRows(res.data || []); setMeta(res.meta || {}); setError(''); }
    catch (e) { setError(e.message); }
  }, [token, group, q, from, to, page]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => { setPage(1); }, [group, q, from, to]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <select aria-label="Kind of action" className={field} value={group} onChange={(e) => setGroup(e.target.value)}>{GROUPS.map(([v, l]) => <option key={l} value={v}>{l}</option>)}</select>
        <input aria-label="Search the log" className={`${field} min-w-48 flex-1`} placeholder="Search what happened" value={q} onChange={(e) => setQ(e.target.value)} />
        <input type="date" aria-label="From" className={field} value={from} onChange={(e) => setFrom(e.target.value)} />
        <input type="date" aria-label="To" className={field} value={to} onChange={(e) => setTo(e.target.value)} />
      </div>
      {error && <p role="alert" className="text-xs font-bold text-danger">{error}</p>}
      <p className="text-xs text-ink-muted">{meta.total ?? 0} entries. Nothing here can be edited or deleted.</p>

      <div className="bg-surface border border-line rounded-card overflow-x-auto">
        <table className="w-full text-xs">
          <thead><tr className="bg-surface-muted text-left text-ink-muted"><th className="px-3 py-2">When</th><th className="px-3 py-2">Who</th><th className="px-3 py-2">What</th><th className="px-3 py-2">Action</th></tr></thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan={4} className="px-3 py-8 text-center text-ink-muted">Nothing recorded for this view.</td></tr>}
            {rows.map((r) => (
              <React.Fragment key={r.id}>
                <tr className="border-t border-line align-top cursor-pointer hover:bg-surface-muted" onClick={() => setOpen(open === r.id ? null : r.id)}>
                  <td className="px-3 py-2 whitespace-nowrap text-ink-muted">{new Date(r.at).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })}</td>
                  <td className="px-3 py-2 text-ink font-semibold">{r.actor}<span className="block text-[10px] text-ink-muted">{r.actor_role}</span></td>
                  <td className="px-3 py-2 text-ink">{r.summary}</td>
                  <td className="px-3 py-2 font-mono text-[11px] text-ink-muted">{r.action}</td>
                </tr>
                {open === r.id && (
                  <tr className="bg-surface-muted"><td colSpan={4} className="px-3 py-2 text-[11px] text-ink-muted">
                    <div>{r.subject_type ? `${r.subject_type} ${r.subject_id}` : 'No subject'}{r.ip ? ` · from ${r.ip}` : ''}</div>
                    {r.meta && <pre className="mt-1 whitespace-pre-wrap font-mono">{JSON.stringify(r.meta, null, 2)}</pre>}
                  </td></tr>
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>
      </div>

      {meta.last_page > 1 && (
        <div className="flex justify-center gap-3 text-xs font-bold">
          <button type="button" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</button>
          <span>{page} of {meta.last_page}</span>
          <button type="button" disabled={page >= meta.last_page} onClick={() => setPage(page + 1)}>Next</button>
        </div>
      )}
    </div>
  );
}
