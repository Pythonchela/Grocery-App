'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { apiFetch, formatINR, formatDate } from '../../lib/apiClient';
import { PackagePlus, Plus, Pencil, Trash2, RefreshCw, X, Save } from 'lucide-react';

const EMPTY = {
  name: '', description: '', primary_product_id: '', secondary_product_id: '',
  bundle_price: '', expires_at: '', is_active: true,
};

/**
 * "Buy these two together" deals.
 *
 * The saving is taken off at checkout by the API, from live prices, so what is
 * previewed here is exactly what a shopper will be charged: whole pairs only,
 * and never more off than the two products' own prices.
 */
export default function BundlesSection({ token }) {
  const [bundles, setBundles] = useState([]);
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [toast, setToast] = useState('');

  const load = async () => {
    try {
      const [b, p] = await Promise.all([
        apiFetch('/admin/bundles', { token }),
        apiFetch('/products?per_page=100', { token }),
      ]);
      setBundles(b.data || []);
      setProducts(p.data || []);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const showToast = (m) => { setToast(m); setTimeout(() => setToast(''), 3000); };
  const setField = (k, v) => setForm(f => ({ ...f, [k]: v }));

  const priceOf = (id) => Number(products.find(p => p.id === id)?.price || 0);

  const preview = useMemo(() => {
    const parts = priceOf(form.primary_product_id) + priceOf(form.secondary_product_id);
    const price = parseFloat(form.bundle_price);
    if (!parts || !Number.isFinite(price)) return null;
    return { parts, saving: Math.max(0, Math.round((parts - price) * 100) / 100) };
  }, [form.primary_product_id, form.secondary_product_id, form.bundle_price, products]);

  const openNew = () => { setForm(EMPTY); setEditing('new'); setError(''); };
  const openEdit = (b) => {
    setForm({
      name: b.name, description: b.description || '',
      primary_product_id: b.primary_product_id, secondary_product_id: b.secondary_product_id,
      bundle_price: String(b.bundle_price),
      expires_at: b.expires_at ? b.expires_at.slice(0, 10) : '',
      is_active: b.is_active,
    });
    setEditing(b.id);
    setError('');
  };

  const save = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError('');
    const payload = {
      name: form.name,
      description: form.description || null,
      primary_product_id: form.primary_product_id,
      secondary_product_id: form.secondary_product_id,
      bundle_price: parseFloat(form.bundle_price),
      expires_at: form.expires_at || null,
      is_active: form.is_active,
    };
    try {
      if (editing === 'new') await apiFetch('/admin/bundles', { method: 'POST', token, body: payload });
      else await apiFetch(`/admin/bundles/${editing}`, { method: 'PUT', token, body: payload });
      showToast(editing === 'new' ? '✅ Bundle created.' : '✅ Bundle updated.');
      setEditing(null);
      await load();
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  const remove = async (id) => {
    await apiFetch(`/admin/bundles/${id}`, { method: 'DELETE', token });
    showToast('🗑️ Bundle deleted.');
    load();
  };

  return (
    <div className="space-y-5">
      {toast && (
        <div className="fixed bottom-8 left-1/2 -translate-x-1/2 bg-inverse text-ink-inverse px-6 py-3 rounded-pill shadow-panel z-50 font-bold text-sm">
          {toast}
        </div>
      )}

      <div className="flex items-center justify-between">
        <p className="text-ink-subtle text-sm font-bold">{bundles.length} bundle deals</p>
        <div className="flex items-center gap-3">
          <button onClick={load} aria-label="Refresh" className="p-2.5 bg-surface border border-line rounded-card text-ink-muted hover:border-line-strong">
            <RefreshCw className="w-4 h-4" />
          </button>
          <button onClick={openNew} className="flex items-center gap-2 bg-inverse text-ink-inverse px-4 py-2.5 rounded-card text-sm font-bold">
            <Plus className="w-4 h-4" /> Add bundle
          </button>
        </div>
      </div>

      {loading && (
        <div className="flex items-center justify-center gap-2 py-16 text-ink-subtle font-bold">
          <RefreshCw className="w-4 h-4 animate-spin" /> Loading bundles...
        </div>
      )}

      {!loading && bundles.length === 0 && (
        <div className="bg-surface-muted border border-line rounded-panel p-12 text-center">
          <PackagePlus className="w-8 h-8 text-ink-subtle mx-auto mb-3" />
          <h3 className="font-black text-ink">No bundle deals yet</h3>
          <p className="text-ink-subtle text-sm mt-1 font-medium">
            Pair two products at a combined price. Shoppers see it on the product page and in their cart.
          </p>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {bundles.map(b => {
          const parts = Number(b.primary_product?.price || 0) + Number(b.secondary_product?.price || 0);
          return (
            <div key={b.id} className="bg-surface border border-line rounded-card p-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-black text-ink">{b.name}</span>
                    <span className={`text-[10px] font-black px-2 py-0.5 rounded-pill border ${
                      b.is_active ? 'bg-success-soft text-success border-success' : 'bg-surface-sunken text-ink-subtle border-line'
                    }`}>
                      {b.is_active ? 'ACTIVE' : 'INACTIVE'}
                    </span>
                  </div>
                  <p className="text-xs text-ink-subtle font-medium mt-1">
                    {b.primary_product?.title} + {b.secondary_product?.title}
                  </p>
                </div>
                <div className="text-right shrink-0">
                  <p className="font-black text-ink text-lg">{formatINR(b.bundle_price)}</p>
                  {parts > 0 && <p className="text-[11px] text-ink-subtle line-through">{formatINR(parts)}</p>}
                </div>
              </div>
              {b.expires_at && (
                <p className="text-[11px] font-medium text-ink-muted mt-2">Ends {formatDate(b.expires_at)}</p>
              )}
              <div className="flex items-center gap-2 mt-3 pt-3 border-t border-line">
                <button onClick={() => openEdit(b)} className="flex items-center gap-1 text-[11px] font-bold text-accent bg-accent-soft px-2.5 py-1.5 rounded-control">
                  <Pencil className="w-3 h-3" /> Edit
                </button>
                <button onClick={() => remove(b.id)} className="flex items-center gap-1 text-[11px] font-bold text-danger bg-danger-soft px-2.5 py-1.5 rounded-control">
                  <Trash2 className="w-3 h-3" /> Delete
                </button>
              </div>
            </div>
          );
        })}
      </div>

      {editing && (
        <div className="fixed inset-0 z-50 bg-inverse/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-surface rounded-panel w-full max-w-xl max-h-[92vh] flex flex-col overflow-hidden">
            <div className="bg-inverse text-ink-inverse px-6 py-4 flex items-center justify-between">
              <h2 className="font-black flex items-center gap-2">
                <PackagePlus className="w-5 h-5" />
                {editing === 'new' ? 'Create bundle' : 'Edit bundle'}
              </h2>
              <button onClick={() => setEditing(null)} aria-label="Close" className="p-2 rounded-pill">
                <X className="w-5 h-5" />
              </button>
            </div>

            <form onSubmit={save} className="flex-1 overflow-y-auto p-6 space-y-4 text-xs">
              {error && <div className="bg-danger-soft border border-danger text-danger p-3 rounded-card font-bold">⚠️ {error}</div>}

              <Field label="Bundle name" required value={form.name} onChange={v => setField('name', v)} placeholder="e.g. Festive pair" />
              <Field label="Description" value={form.description} onChange={v => setField('description', v)} />

              <ProductSelect label="First product" value={form.primary_product_id} products={products}
                onChange={v => setField('primary_product_id', v)} />
              <ProductSelect label="Second product" value={form.secondary_product_id} products={products}
                onChange={v => setField('secondary_product_id', v)} />

              <div className="grid grid-cols-2 gap-3">
                <Field label="Bundle price (₹)" required type="number" value={form.bundle_price} onChange={v => setField('bundle_price', v)} />
                <Field label="Ends on" type="date" value={form.expires_at} onChange={v => setField('expires_at', v)} />
              </div>

              {preview && (
                <div className={`rounded-card border p-3 font-bold ${
                  preview.saving > 0 ? 'bg-success-soft border-success text-success' : 'bg-warning-soft border-warning text-warning'
                }`}>
                  {preview.saving > 0
                    ? `Together ${formatINR(preview.parts)} → shoppers save ${formatINR(preview.saving)} per pair.`
                    : `${formatINR(preview.parts)} separately - this price is not lower, so no discount would apply.`}
                </div>
              )}

              <label className="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" checked={form.is_active} onChange={e => setField('is_active', e.target.checked)} className="w-4 h-4 accent-primary" />
                <span className="font-bold text-ink">Bundle is active</span>
              </label>

              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setEditing(null)} className="flex-1 bg-surface-sunken text-ink-muted py-3 rounded-card font-bold">
                  Cancel
                </button>
                <button type="submit" disabled={saving}
                  className="flex-1 bg-inverse text-ink-inverse py-3 rounded-card font-bold disabled:opacity-50 flex items-center justify-center gap-2">
                  {saving ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                  {saving ? 'Saving...' : 'Save bundle'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

function ProductSelect({ label, value, products, onChange }) {
  return (
    <div>
      <label className="block font-bold text-ink-muted mb-1.5">{label} <span className="text-danger">*</span></label>
      <select required value={value} onChange={e => onChange(e.target.value)}
        className="w-full bg-surface-muted border border-line rounded-card px-4 py-3 font-semibold focus:outline-none focus:border-line-strong">
        <option value="">Select a product…</option>
        {products.map(p => (
          <option key={p.id} value={p.id}>{p.title} — {formatINR(p.price)}</option>
        ))}
      </select>
    </div>
  );
}

function Field({ label, value, onChange, required, type = 'text', placeholder }) {
  return (
    <div>
      <label className="block font-bold text-ink-muted mb-1.5">
        {label} {required && <span className="text-danger">*</span>}
      </label>
      <input type={type} required={required} value={value} placeholder={placeholder}
        onChange={e => onChange(e.target.value)}
        className="w-full bg-surface-muted border border-line rounded-card px-4 py-3 font-semibold focus:outline-none focus:border-line-strong" />
    </div>
  );
}
