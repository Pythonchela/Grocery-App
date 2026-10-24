'use client';

import React, { useEffect, useState } from 'react';
import { apiFetch } from '../../lib/apiClient';

const fields = [
  ['store_legal_name', 'Legal business name', 'Name shown on order receipts'],
  ['store_address', 'Registered business address', 'Full address shown on order receipts'],
  ['store_gstin', 'GSTIN', 'Leave blank if the business is not GST registered'],
];

export default function BusinessSettingsSection({ token }) {
  const [details, setDetails] = useState({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    apiFetch('/settings').then(r => setDetails(r.data || {})).catch(e => setError(e.message)).finally(() => setLoading(false));
  }, []);

  const save = async (e) => {
    e.preventDefault(); setSaving(true); setError(''); setMessage('');
    try {
      const body = Object.fromEntries(fields.map(([key]) => [key, String(details[key] || '').trim()]));
      body.store_gstin = body.store_gstin.toUpperCase();
      const res = await apiFetch('/admin/settings', { method: 'PUT', token, body });
      setDetails(res.data); setMessage('Business details saved.');
    } catch (e) { setError(e.message); }
    finally { setSaving(false); }
  };

  return <form onSubmit={save} className="space-y-3 border-b border-line pb-6">
    <h3 className="font-black text-ink">Business details</h3>
    <p className="text-xs text-ink-muted">These details appear on order receipts. GST tax invoices also need the correct HSN and tax rate for each product; the receipt does not claim a tax breakdown until those are configured.</p>
    {loading ? <p className="text-xs text-ink-muted">Loading…</p> : fields.map(([key, label, hint]) => <label key={key} className="block text-xs font-bold text-ink">
      {label}<span className="block font-normal text-ink-muted">{hint}</span>
      <input className="mt-1 w-full rounded-control border border-line bg-surface px-3 py-2 text-sm" value={details[key] || ''}
        onChange={e => setDetails(v => ({ ...v, [key]: e.target.value }))} />
    </label>)}
    {error && <p role="alert" className="text-xs text-danger">{error}</p>}
    {message && <p role="status" className="text-xs text-success">{message}</p>}
    <button type="submit" disabled={loading || saving} className="btn-primary px-4 py-2 text-xs disabled:opacity-50">{saving ? 'Saving…' : 'Save business details'}</button>
  </form>;
}
