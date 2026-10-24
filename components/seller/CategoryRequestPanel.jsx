'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '../../lib/apiClient';

export default function CategoryRequestPanel({ token }) {
  const [open, setOpen] = useState(false);
  const [rows, setRows] = useState([]);
  const [name, setName] = useState('');
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const load = useCallback(() => apiFetch('/seller/category-requests', { token }).then(r => setRows(r.data || [])).catch(e => setError(e.message)), [token]);
  useEffect(() => { if (open) load(); }, [open, load]);

  const submit = async (e) => {
    e.preventDefault(); setSaving(true); setError('');
    try {
      await apiFetch('/seller/category-requests', { method: 'POST', token, body: { name: name.trim(), reason: reason.trim() || null } });
      setName(''); setReason(''); await load();
    } catch (e) { setError(e.message); }
    finally { setSaving(false); }
  };

  return <section className="rounded-card border border-line bg-surface p-3 text-sm text-ink">
    <button type="button" className="font-bold text-accent" onClick={() => setOpen(v => !v)} aria-expanded={open}>Need a new category? {open ? 'Hide requests' : 'Request one'}</button>
    {open && <div className="mt-3 space-y-3">
      <p className="text-xs text-ink-muted">Choose an existing category whenever possible. New categories appear after admin approval.</p>
      <form onSubmit={submit} className="flex flex-wrap gap-2">
        <input aria-label="New category name" required minLength={2} maxLength={120} className="min-w-48 flex-1 rounded-control border border-line p-2" placeholder="Category name" value={name} onChange={e => setName(e.target.value)} />
        <input aria-label="Why this category is needed" maxLength={1000} className="min-w-48 flex-1 rounded-control border border-line p-2" placeholder="What will you sell?" value={reason} onChange={e => setReason(e.target.value)} />
        <button disabled={saving} className="rounded-control bg-accent px-3 py-2 font-bold text-on-accent disabled:opacity-50">Send request</button>
      </form>
      {error && <p role="alert" className="text-danger">{error}</p>}
      {rows.map(row => <p key={row.id} className="border-t border-line pt-2"><strong>{row.name}</strong> · {row.status.toLowerCase()}{row.category ? ` · now in ${row.category.name}` : ''}{row.admin_note ? ` · ${row.admin_note}` : ''}</p>)}
    </div>}
  </section>;
}
