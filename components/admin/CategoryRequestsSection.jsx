'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '../../lib/apiClient';

export default function CategoryRequestsSection({ token, onApproved }) {
  const [rows, setRows] = useState([]);
  const [filter, setFilter] = useState('PENDING');
  const [page, setPage] = useState(1);
  const [lastPage, setLastPage] = useState(1);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [note, setNote] = useState({});
  const load = useCallback(async () => {
    try {
      const res = await apiFetch(`/admin/category-requests?status=${filter}&page=${page}`, { token });
      setRows(res.data || []); setLastPage(res.meta?.last_page || 1); setError('');
    } catch (e) { setError(e.message); }
  }, [filter, page, token]);
  useEffect(() => { load(); }, [load]);

  const decide = async (row, decision) => {
    setBusy(row.id); setError('');
    try {
      await apiFetch(`/admin/category-requests/${row.id}`, { method: 'PUT', token,
        body: { decision, admin_note: note[row.id] || null } });
      await load();
      if (decision === 'APPROVED') onApproved?.();
    } catch (e) { setError(e.message); }
    finally { setBusy(''); }
  };

  return <section className="rounded-panel border border-line bg-surface p-4 space-y-3">
    <div className="flex flex-wrap items-center justify-between gap-2"><div><h2 className="font-black text-ink">Seller category requests</h2><p className="text-xs text-ink-muted">Approve to add the category, or reject with a reason the seller can read.</p></div>
      <select aria-label="Request status" className="rounded-control border border-line p-2 text-sm" value={filter} onChange={e => { setFilter(e.target.value); setPage(1); }}>
        {['PENDING', 'APPROVED', 'REJECTED'].map(v => <option key={v}>{v}</option>)}
      </select></div>
    {error && <p role="alert" className="text-sm text-danger">{error}</p>}
    {rows.length === 0 && <p className="text-sm text-ink-muted">No {filter.toLowerCase()} requests.</p>}
    {rows.map(row => <article key={row.id} className="rounded-card border border-line p-3 text-sm space-y-2">
      <div className="flex flex-wrap justify-between gap-2"><strong>{row.name}</strong><span className="text-ink-muted">{row.seller?.display_name} · {row.status}</span></div>
      {row.reason && <p>{row.reason}</p>}
      {row.category && <p className="text-xs text-ink-muted">Category: {row.category.name}</p>}
      {row.admin_note && <p className="text-xs text-ink-muted">Review note: {row.admin_note}</p>}
      {row.status === 'PENDING' && <div className="space-y-2">
        <input aria-label={`Review note for ${row.name}`} className="w-full rounded-control border border-line p-2" placeholder="Note to seller (optional)" value={note[row.id] || ''} onChange={e => setNote(v => ({ ...v, [row.id]: e.target.value }))} />
        <div className="flex gap-2"><button disabled={!!busy} className="rounded-control bg-accent px-3 py-2 font-bold text-on-accent disabled:opacity-50" onClick={() => decide(row, 'APPROVED')}>Approve</button>
          <button disabled={!!busy} className="rounded-control border border-line px-3 py-2 font-bold disabled:opacity-50" onClick={() => decide(row, 'REJECTED')}>Reject</button></div>
      </div>}
    </article>)}
    {lastPage > 1 && <div className="flex justify-center gap-3 text-sm"><button disabled={page <= 1} onClick={() => setPage(p => p - 1)}>Previous</button><span>{page} of {lastPage}</span><button disabled={page >= lastPage} onClick={() => setPage(p => p + 1)}>Next</button></div>}
  </section>;
}
