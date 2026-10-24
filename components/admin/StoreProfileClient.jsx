'use client';

import React, { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { AlertCircle, ArrowLeft, RefreshCw, Store } from 'lucide-react';
import { apiFetch } from '../../lib/apiClient';
import { useAdminAuth } from './AdminAuthContext';
import ShopProfileSection from './ShopProfileSection';

const PICKUP_FIELDS = [
  ['pickup_line1', 'Street address'],
  ['pickup_city', 'City'],
  ['pickup_state', 'State'],
  ['pickup_pincode', 'PIN code'],
  ['pickup_phone', 'Phone at pickup'],
  ['pickup_code', 'Courier pickup name (Shiprocket / Delhivery)'],
];

const inputCls = 'w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-semibold text-ink focus:outline-none focus:border-accent';

/**
 * The store's own page: how it presents itself to shoppers (logo, hours, minimum
 * order, delivery area) and where couriers collect parcels from.
 *
 * There is one shop in this installation, so there is no list to choose from.
 */
export default function StoreProfileClient() {
  const { token } = useAdminAuth();
  const [store, setStore] = useState(null);
  const [pickup, setPickup] = useState({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const adopt = useCallback((data) => {
    setStore(data);
    setPickup(Object.fromEntries(PICKUP_FIELDS.map(([key]) => [key, data[key] || ''])));
  }, []);

  const load = useCallback(async () => {
    setError('');
    try {
      const body = await apiFetch('/admin/store', { token });
      adopt(body.data);
    } catch (err) {
      setError(err.message);
    }
  }, [token, adopt]);

  useEffect(() => { if (token) load(); }, [token, load]);

  const savePickup = async () => {
    setBusy(true); setError(''); setNotice('');
    try {
      // Empty means "not set": the API treats these as nullable.
      const body = Object.fromEntries(Object.entries(pickup).map(([k, v]) => [k, String(v).trim() === '' ? null : String(v).trim()]));
      const res = await apiFetch('/admin/store', { method: 'PUT', token, body });
      adopt(res.data);
      setNotice('Pickup address saved.');
    } catch (err) {
      setError(err.message);
    } finally { setBusy(false); }
  };

  return (
    <div className="min-h-screen bg-surface-sunken">
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-5">
        <div className="flex items-center gap-3">
          <Link href="/admin" className="text-ink-muted hover:text-ink" aria-label="Back to admin"><ArrowLeft className="w-5 h-5" /></Link>
          <div>
            <h1 className="text-lg font-black text-ink flex items-center gap-2"><Store className="w-5 h-5 text-accent" /> My shop</h1>
            <p className="text-xs text-ink-muted">How the store presents itself, when it takes orders, and where parcels are collected.</p>
          </div>
        </div>

        {error && (
          <p role="alert" className="text-xs font-bold text-danger flex items-center gap-1"><AlertCircle className="w-3.5 h-3.5" /> {error}</p>
        )}
        {notice && <p role="status" className="text-xs font-bold text-success">{notice}</p>}

        {!store && !error && <p className="text-sm text-ink-muted flex items-center gap-2"><RefreshCw className="w-4 h-4 animate-spin" /> Loading…</p>}

        {store && (
          <div className="space-y-6 rounded-card border border-line bg-surface p-5">
            <ShopProfileSection seller={store} token={token} endpoint="/admin/store" onSaved={adopt} />

            <section className="space-y-3 border-t border-line pt-5">
              <h2 className="text-xs font-black text-ink uppercase tracking-wide">Pickup address</h2>
              <p className="text-[11px] text-ink-subtle font-medium">
                Where couriers collect orders. Delivery times and fees are worked out from here. Left empty, the address in Integrations is used.
              </p>
              {PICKUP_FIELDS.map(([key, label]) => (
                <label key={key} className="block">
                  <span className="block text-[10px] font-bold text-ink-subtle uppercase mb-1">{label}</span>
                  <input
                    value={pickup[key] ?? ''}
                    onChange={(e) => setPickup((p) => ({ ...p, [key]: e.target.value }))}
                    inputMode={key === 'pickup_pincode' ? 'numeric' : undefined}
                    maxLength={key === 'pickup_pincode' ? 6 : undefined}
                    className={inputCls}
                  />
                </label>
              ))}
              <button onClick={savePickup} disabled={busy} className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50">
                {busy ? 'Saving…' : 'Save pickup address'}
              </button>
            </section>
          </div>
        )}
      </div>
    </div>
  );
}
