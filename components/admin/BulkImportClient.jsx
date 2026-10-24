'use client';

import React, { useState } from 'react';
import {
  UploadCloud, AlertTriangle, CheckCircle2, Trash2, PackagePlus,
} from 'lucide-react';
import { useAdminAuth } from './AdminAuthContext';
import { apiFetch } from '../../lib/apiClient';

const PLACEHOLDER = `Paste product data in any shape — CSV, a pasted spreadsheet, JSON, a markdown table, or plain sentences. For example:

Title, Price, MRP, Category
Silk Anarkali Set, 3499, 6999, Ethnic & Festive
Leather Sneakers, 2499, 4999, Footwear & Sneakers

...or just prose:
Handwoven Cotton Kurta — ₹1,299 (MRP ₹2,199), Ethnic & Festive, sizes S/M/L`;

/**
 * Bulk product import: paste anything, review what the parser made of it,
 * fix what it got wrong, then commit.
 *
 * Preview writes nothing — every row is editable before commit, and the
 * parser's own confidence score and issue list are shown per field so a
 * low-confidence guess is something the admin catches here rather than a
 * silently wrong price live on the storefront.
 */
export default function BulkImportClient({ token: tokenOverride, basePath = '/admin/products/import' }) {
  const { token: adminToken } = useAdminAuth();
  const token = tokenOverride || adminToken;

  const [raw, setRaw] = useState('');
  const [previewing, setPreviewing] = useState(false);
  const [committing, setCommitting] = useState(false);
  const [preview, setPreview] = useState(null); // { format, driver, categories, rows }
  const [rows, setRows] = useState([]);
  const [status, setStatus] = useState('DRAFT');
  const [error, setError] = useState('');
  const [result, setResult] = useState(null);

  const runPreview = async () => {
    if (!raw.trim()) return;
    setPreviewing(true); setError(''); setResult(null);
    try {
      const res = await apiFetch(`${basePath}/preview`, {
        method: 'POST', token, body: { raw },
      });
      setPreview(res.data);
      setRows(res.data.rows.map(r => ({ ...r, include: r.importable })));
    } catch (err) {
      setError(err.message);
    } finally { setPreviewing(false); }
  };

  const updateRow = (index, patch) => {
    setRows(prev => prev.map(r => (r.index === index ? { ...r, ...patch } : r)));
  };

  const removeRow = (index) => {
    setRows(prev => prev.filter(r => r.index !== index));
  };

  const includedRows = rows.filter(r => r.include);
  // A row can be ticked "include" without actually being commit-ready — the
  // backend requires title/price/mrp/category on every row it receives, so
  // this mirrors that before the request ever goes out.
  const readyRows = includedRows.filter(r => r.title && r.price != null && r.mrp != null && r.category_id);
  const blockedCount = includedRows.length - readyRows.length;

  const commit = async () => {
    if (readyRows.length === 0) return;
    setCommitting(true); setError('');
    try {
      const res = await apiFetch(`${basePath}/commit`, {
        method: 'POST', token,
        body: {
          status,
          rows: readyRows.map(r => ({
            title: r.title,
            description: r.description || null,
            brand: r.brand || null,
            price: r.price,
            mrp: r.mrp,
            category_id: r.category_id,
            images: r.images || [],
            tags: r.tags || [],
            variants: r.variants || [],
          })),
        },
      });
      setResult(res.data);
      setPreview(null);
      setRows([]);
      setRaw('');
    } catch (err) {
      setError(err.message);
    } finally { setCommitting(false); }
  };

  const reset = () => {
    setPreview(null); setRows([]); setResult(null); setError(''); setRaw('');
  };

  return (
    <div className="space-y-5">
      <header>
        <h2 className="text-lg font-black text-ink flex items-center gap-2">
          <UploadCloud className="w-5 h-5 text-accent" /> Bulk import
        </h2>
        <p className="text-xs text-ink-muted font-medium mt-0.5">
          Paste a spreadsheet, CSV, JSON, or plain descriptions. Nothing is created until you review and commit.
        </p>
      </header>

      {result && (
        <div className="p-4 border border-success/30 bg-success/5 rounded-card flex items-start gap-3">
          <CheckCircle2 className="w-5 h-5 text-success shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm font-black text-ink">
              {result.created} product{result.created === 1 ? '' : 's'} imported as {result.status}.
            </p>
            <p className="text-xs text-ink-subtle font-medium mt-1">
              {result.products?.map(p => p.title).slice(0, 5).join(' · ')}
              {result.products?.length > 5 ? ` +${result.products.length - 5} more` : ''}
            </p>
          </div>
          <button onClick={reset} className="text-[11px] font-bold text-accent hover:underline shrink-0">
            Import more
          </button>
        </div>
      )}

      {error && (
        <p className="text-xs font-bold text-danger flex items-center gap-1">
          <AlertTriangle className="w-3.5 h-3.5" /> {error}
        </p>
      )}

      {!preview && !result && (
        <div className="space-y-3">
          <textarea
            value={raw}
            onChange={e => setRaw(e.target.value)}
            placeholder={PLACEHOLDER}
            rows={12}
            className="w-full bg-surface border border-line rounded-card px-4 py-3 text-xs font-mono text-ink focus:outline-none focus:border-accent resize-y"
          />
          <button
            onClick={runPreview}
            disabled={previewing || !raw.trim()}
            className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50"
          >
            {previewing ? 'Parsing…' : 'Preview'}
          </button>
        </div>
      )}

      {preview && (
        <div className="space-y-4">
          <div className="flex items-center justify-between gap-3 text-xs font-bold text-ink-muted">
            <span>
              Detected as <span className="text-ink">{preview.format}</span> via the{' '}
              <span className="text-ink">{preview.driver}</span> parser · {preview.total} row(s),{' '}
              {preview.importable} look ready
            </span>
            <button onClick={reset} className="text-danger hover:underline">Start over</button>
          </div>

          <div className="space-y-3">
            {rows.map(row => (
              <ImportRow
                key={row.index}
                row={row}
                categories={preview.categories}
                onChange={patch => updateRow(row.index, patch)}
                onRemove={() => removeRow(row.index)}
              />
            ))}
            {rows.length === 0 && (
              <p className="text-xs text-ink-subtle font-medium py-6 text-center">
                No rows left — start over to paste something else.
              </p>
            )}
          </div>

          {rows.length > 0 && (
            <div className="sticky bottom-0 bg-surface border border-line rounded-card p-4 flex items-center justify-between gap-3 shadow-card">
              <div className="text-xs font-bold text-ink-muted">
                <span className="text-ink">{readyRows.length}</span> of {includedRows.length} selected row(s) ready to import
                {blockedCount > 0 && (
                  <span className="text-warning"> · {blockedCount} missing a required field</span>
                )}
              </div>
              <div className="flex items-center gap-3">
                <select
                  value={status}
                  onChange={e => setStatus(e.target.value)}
                  className="bg-surface border border-line rounded-control px-3 py-2 text-xs font-bold text-ink focus:outline-none focus:border-accent"
                >
                  <option value="DRAFT">Import as Draft</option>
                  <option value="ACTIVE">Import as Active</option>
                </select>
                <button
                  onClick={commit}
                  disabled={committing || readyRows.length === 0}
                  className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50 flex items-center gap-1.5"
                >
                  <PackagePlus className="w-4 h-4" />
                  {committing ? 'Importing…' : `Import ${readyRows.length}`}
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** One editable draft row, with confidence-tinted fields and flagged issues. */
function ImportRow({ row, categories, onChange, onRemove }) {
  const conf = row.confidence || {};
  const tone = (field) => {
    const c = conf[field];
    if (c == null) return '';
    if (c >= 0.8) return 'border-success/40';
    if (c >= 0.5) return 'border-warning/40';
    return 'border-danger/40';
  };

  return (
    <div className={`p-4 border rounded-card bg-surface space-y-3 ${row.include ? 'border-line' : 'border-line opacity-50'}`}>
      <div className="flex items-start gap-3">
        <input
          type="checkbox"
          checked={row.include}
          onChange={e => onChange({ include: e.target.checked })}
          className="mt-1 w-4 h-4 accent-primary cursor-pointer shrink-0"
        />

        <div className="flex-1 grid grid-cols-2 gap-2.5">
          <label className="col-span-2 block">
            <span className="block text-[9px] font-bold text-ink-subtle uppercase mb-0.5">Title</span>
            <input
              value={row.title || ''}
              onChange={e => onChange({ title: e.target.value })}
              className={`w-full bg-surface-muted border rounded-control px-2.5 py-1.5 text-xs font-bold text-ink focus:outline-none focus:border-accent ${tone('title')}`}
            />
          </label>

          <label className="block">
            <span className="block text-[9px] font-bold text-ink-subtle uppercase mb-0.5">Price (₹)</span>
            <input
              type="number" step="0.01"
              value={row.price ?? ''}
              onChange={e => onChange({ price: e.target.value === '' ? null : Number(e.target.value) })}
              className={`w-full bg-surface-muted border rounded-control px-2.5 py-1.5 text-xs font-bold text-ink focus:outline-none focus:border-accent ${tone('price')}`}
            />
          </label>

          <label className="block">
            <span className="block text-[9px] font-bold text-ink-subtle uppercase mb-0.5">MRP (₹)</span>
            <input
              type="number" step="0.01"
              value={row.mrp ?? ''}
              onChange={e => onChange({ mrp: e.target.value === '' ? null : Number(e.target.value) })}
              className={`w-full bg-surface-muted border rounded-control px-2.5 py-1.5 text-xs font-bold text-ink focus:outline-none focus:border-accent ${tone('mrp')}`}
            />
          </label>

          <label className="col-span-2 block">
            <span className="block text-[9px] font-bold text-ink-subtle uppercase mb-0.5">
              Category{row.category_hint && !row.category_id ? ` (detected "${row.category_hint}")` : ''}
            </span>
            <select
              value={row.category_id || ''}
              onChange={e => onChange({ category_id: e.target.value || null })}
              className={`w-full bg-surface-muted border rounded-control px-2.5 py-1.5 text-xs font-bold text-ink focus:outline-none focus:border-accent ${tone('category')}`}
            >
              <option value="">— choose a category —</option>
              {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </label>

          {row.brand && (
            <label className="block">
              <span className="block text-[9px] font-bold text-ink-subtle uppercase mb-0.5">Brand</span>
              <input
                value={row.brand || ''}
                onChange={e => onChange({ brand: e.target.value })}
                className="w-full bg-surface-muted border border-line rounded-control px-2.5 py-1.5 text-xs font-bold text-ink focus:outline-none focus:border-accent"
              />
            </label>
          )}

          {row.variants?.length > 0 && (
            <div className="col-span-2 text-[10px] text-ink-subtle font-semibold">
              {row.variants.length} variant{row.variants.length === 1 ? '' : 's'}:{' '}
              {row.variants.slice(0, 4).map(v => [v.color, v.size].filter(Boolean).join('/')).join(', ')}
              {row.variants.length > 4 ? ` +${row.variants.length - 4} more` : ''}
            </div>
          )}
        </div>

        <button onClick={onRemove} className="text-ink-subtle hover:text-danger shrink-0" aria-label="Remove row">
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      </div>

      {row.issues?.length > 0 && (
        <div className="pl-7 space-y-1">
          {row.issues.map((issue, i) => (
            <p key={i} className="text-[10px] text-warning font-semibold flex items-start gap-1">
              <AlertTriangle className="w-3 h-3 shrink-0 mt-0.5" /> {issue}
            </p>
          ))}
        </div>
      )}
    </div>
  );
}
