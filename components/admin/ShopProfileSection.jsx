'use client';

import React, { useState } from 'react';
import { Upload, X } from 'lucide-react';
import { apiFetch } from '../../lib/apiClient';
import { uploadFile } from '../../lib/uploads';
import OpeningHoursEditor from './OpeningHoursEditor';

const field = 'w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-semibold text-ink focus:outline-none focus:border-accent';
const labelCls = 'block text-[10px] font-bold text-ink-subtle uppercase mb-1';

/** PIN codes typed one per line, or separated by commas or spaces. */
export function parsePincodes(text) {
  return [...new Set(String(text || '').split(/[\s,;]+/).map((p) => p.trim()).filter(Boolean))];
}

/**
 * How a shop presents itself to shoppers and what it asks of an order: logo and
 * banner, a tagline and a few lines about the shop, when it is open, the
 * smallest basket it will deliver, and the PIN codes it covers.
 *
 * The store's own profile. Saves through PUT /admin/store.
 */
export default function ShopProfileSection({ seller, token, onSaved, endpoint = '/admin/store' }) {
  const [form, setForm] = useState({
    logo_url: seller.logo_url || '',
    banner_url: seller.banner_url || '',
    tagline: seller.tagline || '',
    about: seller.about || '',
    min_order_amount: String(Number(seller.min_order_amount) || 0),
    prep_minutes: seller.prep_minutes ?? '',
    accepting_orders: seller.accepting_orders !== false,
    pincodes: (seller.service_pincodes || []).join('\n'),
    opening_hours: seller.opening_hours || null,
  });
  const [busy, setBusy] = useState(false);
  const [uploading, setUploading] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const set = (key, value) => setForm((f) => ({ ...f, [key]: value }));

  const upload = async (key, file) => {
    if (!file) return;
    setUploading(key); setError('');
    try {
      set(key, await uploadFile(file, token));
    } catch (err) {
      setError(err.message);
    } finally { setUploading(''); }
  };

  const save = async () => {
    setBusy(true); setError(''); setNotice('');
    try {
      const res = await apiFetch(endpoint, {
        method: 'PUT', token,
        body: {
          logo_url: form.logo_url || null,
          banner_url: form.banner_url || null,
          tagline: form.tagline.trim() || null,
          about: form.about.trim() || null,
          min_order_amount: Number(form.min_order_amount) || 0,
          prep_minutes: form.prep_minutes === '' ? null : Number(form.prep_minutes),
          accepting_orders: form.accepting_orders,
          service_pincodes: parsePincodes(form.pincodes),
          // null means "always open".
          opening_hours: form.opening_hours || [],
        },
      });
      onSaved(res.data);
      setNotice('Shop details saved.');
    } catch (err) {
      setError(err.message);
    } finally { setBusy(false); }
  };

  const picture = (key, label, shape) => (
    <div>
      <span className={labelCls}>{label}</span>
      <div className="flex items-center gap-3">
        {form[key] ? (
          <div className="relative">
            <img src={form[key]} alt={label} className={`${shape} object-cover border border-line bg-surface-muted`} />
            <button type="button" onClick={() => set(key, '')} aria-label={`Remove ${label.toLowerCase()}`}
              className="absolute -top-1.5 -right-1.5 h-5 w-5 rounded-pill bg-danger text-on-primary inline-flex items-center justify-center">
              <X className="h-3 w-3" />
            </button>
          </div>
        ) : (
          <div className={`${shape} border border-dashed border-line bg-surface-muted`} />
        )}
        <label className="inline-flex items-center gap-1.5 text-xs font-bold text-accent cursor-pointer">
          <Upload className="w-3.5 h-3.5" />
          {uploading === key ? 'Uploading…' : form[key] ? 'Replace' : 'Upload'}
          <input type="file" accept="image/*" className="hidden" onChange={(e) => { upload(key, e.target.files?.[0]); e.target.value = ''; }} />
        </label>
      </div>
    </div>
  );

  return (
    <section className="space-y-3">
      <h4 className="text-xs font-black text-ink uppercase tracking-wide">Store details</h4>
      <p className="text-[11px] text-ink-subtle font-medium">
        How the store presents itself, and what it asks of an order.
      </p>

      {notice && <p className="text-xs font-bold text-success">{notice}</p>}
      {error && <p className="text-xs font-bold text-danger">{error}</p>}

      <div className="grid grid-cols-[auto_1fr] gap-4 items-start">
        {picture('logo_url', 'Logo', 'w-16 h-16 rounded-pill')}
        {picture('banner_url', 'Banner', 'w-full max-w-[200px] h-16 rounded-control')}
      </div>

      <label className="block">
        <span className={labelCls}>Tagline</span>
        <input value={form.tagline} onChange={(e) => set('tagline', e.target.value)} maxLength={120} placeholder="Fresh groceries since 1990" className={field} />
      </label>

      <label className="block">
        <span className={labelCls}>About the shop</span>
        <textarea value={form.about} onChange={(e) => set('about', e.target.value)} rows={3} maxLength={2000} className={field} />
      </label>

      <div className="grid grid-cols-2 gap-2">
        <label className="block">
          <span className={labelCls}>Minimum order (₹)</span>
          <input type="number" min="0" value={form.min_order_amount} onChange={(e) => set('min_order_amount', e.target.value)} className={field} />
        </label>
        <label className="block">
          <span className={labelCls}>Usually ready in (mins)</span>
          <input type="number" min="0" max="1440" value={form.prep_minutes} onChange={(e) => set('prep_minutes', e.target.value)} className={field} />
        </label>
      </div>

      <label className="flex items-center gap-2 text-xs font-bold text-ink cursor-pointer">
        <input type="checkbox" checked={form.accepting_orders} onChange={(e) => set('accepting_orders', e.target.checked)} />
        Taking orders (untick to pause the shop)
      </label>

      <label className="block">
        <span className={labelCls}>Delivers to these PIN codes</span>
        <textarea value={form.pincodes} onChange={(e) => set('pincodes', e.target.value)} rows={3} placeholder="One per line, or separated by commas. Leave empty to deliver anywhere a courier can go." className={`${field} font-mono`} />
        <span className="block text-[10px] text-ink-subtle font-medium mt-1">{parsePincodes(form.pincodes).length || 'No'} PIN codes listed</span>
      </label>

      <div>
        <span className={labelCls}>Opening hours</span>
        <OpeningHoursEditor value={form.opening_hours} onChange={(hours) => set('opening_hours', hours)} />
      </div>

      <button onClick={save} disabled={busy || !!uploading} className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50">
        {busy ? 'Saving…' : 'Save shop page'}
      </button>
    </section>
  );
}
