'use client';

import React, { useState } from 'react';
import { apiFetch } from '../../lib/apiClient';
import { Boxes, RefreshCw, Save, X } from 'lucide-react';

/**
 * Quick stock editor: one number per variant, saved together.
 *
 * The full product form can also change stock, but it rewrites the whole
 * variant list; this changes only the counts, which is what receiving a
 * delivery actually is.
 */
export default function InventoryModal({ product, token, onClose, onSaved }) {
  const variants = product.variants || [];
  const [stock, setStock] = useState(() =>
    Object.fromEntries(variants.map(v => [v.id, String(v.stock ?? 0)])));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const changed = variants.filter(v => String(v.stock ?? 0) !== stock[v.id]);

  const fillAll = (value) =>
    setStock(Object.fromEntries(variants.map(v => [v.id, String(value)])));

  const save = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError('');
    try {
      await apiFetch('/inventory', {
        method: 'PUT',
        token,
        body: {
          items: changed.map(v => ({ variant_id: v.id, stock: parseInt(stock[v.id], 10) || 0 })),
        },
      });
      onSaved(product.id, Object.fromEntries(changed.map(v => [v.id, parseInt(stock[v.id], 10) || 0])));
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  const label = (v) => [v.color, v.size].filter(Boolean).join(' / ') || v.sku || 'Default';

  return (
    <div className="fixed inset-0 z-50 bg-inverse/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-surface rounded-panel w-full max-w-md max-h-[90vh] flex flex-col overflow-hidden">
        <div className="bg-inverse text-ink-inverse px-6 py-4 flex items-center justify-between">
          <h2 className="font-black flex items-center gap-2 text-sm">
            <Boxes className="w-5 h-5" /> Update stock
          </h2>
          <button onClick={onClose} aria-label="Close" className="p-2 rounded-pill"><X className="w-5 h-5" /></button>
        </div>

        <form onSubmit={save} className="flex-1 overflow-y-auto p-6 space-y-4 text-xs">
          <p className="font-black text-ink text-sm">{product.title}</p>
          {error && <div className="bg-danger-soft border border-danger text-danger p-3 rounded-card font-bold">⚠️ {error}</div>}

          {variants.length === 0 ? (
            <p className="text-ink-subtle font-bold">This product has no variants to stock.</p>
          ) : (
            <>
              <div className="flex items-center gap-2 text-ink-muted font-bold">
                Set every variant to
                {[10, 50, 100].map(n => (
                  <button key={n} type="button" onClick={() => fillAll(n)}
                    className="px-2.5 py-1 bg-surface-sunken rounded-control hover:bg-line">{n}</button>
                ))}
              </div>

              <div className="space-y-2">
                {variants.map(v => (
                  <label key={v.id} className="flex items-center justify-between gap-3 bg-surface-muted border border-line rounded-card px-4 py-2.5">
                    <span className="font-bold text-ink">{label(v)}</span>
                    <input
                      type="number" min="0" max="1000000" inputMode="numeric"
                      value={stock[v.id]}
                      onChange={e => setStock(s => ({ ...s, [v.id]: e.target.value }))}
                      aria-label={`Stock for ${label(v)}`}
                      className="w-24 text-right bg-surface border border-line rounded-control px-3 py-1.5 font-black focus:outline-none focus:border-line-strong"
                    />
                  </label>
                ))}
              </div>
            </>
          )}

          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="flex-1 bg-surface-sunken text-ink-muted py-3 rounded-card font-bold">
              Cancel
            </button>
            <button type="submit" disabled={saving || changed.length === 0}
              className="flex-1 bg-inverse text-ink-inverse py-3 rounded-card font-bold disabled:opacity-50 flex items-center justify-center gap-2">
              {saving ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              {saving ? 'Saving...' : changed.length ? `Save ${changed.length} change${changed.length > 1 ? 's' : ''}` : 'No changes'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
