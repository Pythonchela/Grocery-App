'use client';

import React, { useEffect, useState } from 'react';
import { apiFetch } from '../../lib/apiClient';

const inputCls = 'mt-1 w-full rounded-control border border-line bg-surface px-3 py-2 text-sm';

const NUMBER_FIELDS = [
  ['free_shipping_threshold', 'Free delivery above (₹)', 'Orders at or above this total ship free. 0 means delivery is never free.', '0.01'],
  ['loyalty_earn_per_100', 'Loyalty points earned per ₹100', 'Points a customer earns on every ₹100 spent.', '1'],
  ['loyalty_redeem_value', 'Value of one point (₹)', 'What a point is worth when the customer spends it.', '0.01'],
  ['loyalty_max_redeem_percent', 'Most of an order points can pay for (%)', 'Caps how much of a bill can be paid with points.', '1'],
  ['referral_referrer_reward', 'Referral reward for the inviter (₹)', 'Credited when a friend they invited places a first order.', '1'],
  ['referral_referee_reward', 'Referral reward for the new customer (₹)', 'Credited to the invited friend on their first order.', '1'],
];

/** Splits "560001, 560002\n560003" into valid six-digit PIN codes; returns the bad ones too. */
export function parsePins(text) {
  const parts = String(text || '').split(/[\s,;]+/).filter(Boolean);
  const bad = parts.filter((p) => !/^\d{6}$/.test(p));
  return { pins: [...new Set(parts.filter((p) => /^\d{6}$/.test(p)))], bad };
}

/**
 * The store's trading rules: cash on delivery, delivery charge threshold,
 * loyalty points and referral rewards. The server already enforces all of them
 * and the apps already read them; this is the only place to change them.
 */
export default function StoreRulesSection({ token }) {
  const [values, setValues] = useState({});
  const [blocked, setBlocked] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    apiFetch('/settings')
      .then((res) => { setValues(res.data || {}); setBlocked((res.data?.cod_blocked_pincodes || []).join('\n')); })
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  const save = async (e) => {
    e.preventDefault(); setError(''); setMessage('');
    const { pins, bad } = parsePins(blocked);
    if (bad.length) { setError(`These are not 6-digit PIN codes: ${bad.slice(0, 5).join(', ')}`); return; }

    setSaving(true);
    try {
      const body = { cod_enabled: Boolean(values.cod_enabled), cod_blocked_pincodes: pins };
      NUMBER_FIELDS.forEach(([key]) => { if (values[key] !== '' && values[key] != null) body[key] = Number(values[key]); });
      const res = await apiFetch('/admin/settings', { method: 'PUT', token, body });
      setValues(res.data); setBlocked((res.data?.cod_blocked_pincodes || []).join('\n'));
      setMessage('Store rules saved.');
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };

  return (
    <form onSubmit={save} className="space-y-4 border-b border-line pb-6 mb-6">
      <div>
        <h3 className="font-black text-ink">Store rules</h3>
        <p className="text-xs text-ink-muted">Cash on delivery, delivery charges, loyalty points and referral rewards. Changes apply to new orders straight away.</p>
      </div>

      {loading ? <p className="text-xs text-ink-muted">Loading…</p> : (
        <>
          <div className="flex items-start gap-2 text-sm text-ink">
            <input id="cod-enabled" type="checkbox" className="mt-1" checked={Boolean(values.cod_enabled)}
              onChange={(e) => setValues((v) => ({ ...v, cod_enabled: e.target.checked }))} />
            <div>
              <label htmlFor="cod-enabled" className="font-bold">Allow cash on delivery</label>
              <p className="text-xs text-ink-muted">Off: customers must pay online.</p>
            </div>
          </div>

          <div>
            <label htmlFor="cod-blocked" className="block text-xs font-bold text-ink">No cash on delivery in these PIN codes</label>
            <textarea id="cod-blocked" rows={3} className={inputCls} value={blocked} onChange={(e) => setBlocked(e.target.value)} placeholder="One per line, or separated by commas" />
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            {NUMBER_FIELDS.map(([key, label, hint, step]) => (
              <div key={key}>
                <label htmlFor={`rule-${key}`} className="block text-xs font-bold text-ink">{label}</label>
                <input id={`rule-${key}`} type="number" min="0" step={step} className={inputCls} value={values[key] ?? ''}
                  onChange={(e) => setValues((v) => ({ ...v, [key]: e.target.value }))} />
                <p className="text-[11px] text-ink-muted mt-0.5">{hint}</p>
              </div>
            ))}
          </div>
        </>
      )}

      {error && <p role="alert" className="text-xs text-danger">{error}</p>}
      {message && <p role="status" className="text-xs text-success">{message}</p>}
      <button type="submit" disabled={loading || saving} className="btn-primary px-4 py-2 text-xs disabled:opacity-50">{saving ? 'Saving…' : 'Save store rules'}</button>
    </form>
  );
}
