'use client';

import React, { useState } from 'react';
import {
  UploadCloud, AlertTriangle, CheckCircle2, Trash2, PackagePlus, FileText, Image as ImageIcon,
  FileSpreadsheet, Sparkles, X, ChevronDown, ChevronUp, Plus, Loader2,
} from 'lucide-react';
import { useAdminAuth } from './AdminAuthContext';
import { apiFetch } from '../../lib/apiClient';
import { parseImport } from '../../lib/importApi';
import {
  ACCEPT, attention, commitBody, isPicture, isReady, isTable, mergeResults, planBatches, sortedForReview,
} from '../../lib/importRows';

const PLACEHOLDER = `Or paste product details in any shape: a spreadsheet, CSV, JSON, or plain sentences.

Handwoven Cotton Kurta — ₹1,299 (MRP ₹2,199), Ethnic & Festive, sizes S/M/L, colours red and blue`;

const size = (bytes) => (bytes > 1048576 ? `${(bytes / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`);

function FileIcon({ file }) {
  if (isPicture(file)) return <ImageIcon className="w-4 h-4 text-accent" />;
  if (isTable(file)) return <FileSpreadsheet className="w-4 h-4 text-success" />;
  return <FileText className="w-4 h-4 text-ink-muted" />;
}

/**
 * Product import: drop photos, PDFs, Word and Excel files, or paste text. They are read
 * into draft products with their photos, details, colours and sizes; the owner checks
 * what came out, fixes what is wrong, and only then are products created.
 *
 * Nothing is created until "Import". Every price is checked against the source and
 * anything doubtful is put first and marked, so a misread number is caught here
 * rather than live on the storefront.
 */
export default function BulkImportClient({ token: tokenOverride, basePath = '/admin/products/import' }) {
  const { token: adminToken } = useAdminAuth();
  const token = tokenOverride || adminToken;

  const [files, setFiles] = useState([]);
  const [raw, setRaw] = useState('');
  const [together, setTogether] = useState(true);
  const [hint, setHint] = useState('');
  const [defaultStock, setDefaultStock] = useState(10);
  const [wholeCategory, setWholeCategory] = useState('');
  const [categories, setCategories] = useState(null);
  const [dragging, setDragging] = useState(false);

  const [progress, setProgress] = useState(null); // { done, total, label }
  const [result, setResult] = useState(null);     // merged parse results
  const [rows, setRows] = useState([]);
  const [status, setStatus] = useState('DRAFT');
  const [committing, setCommitting] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState(null);

  const reading = progress !== null;
  const nothing = files.length === 0 && !raw.trim();

  const addFiles = (list) => {
    const incoming = Array.from(list || []);
    setFiles((prev) => {
      const seen = new Set(prev.map((f) => `${f.name}:${f.size}`));
      return [...prev, ...incoming.filter((f) => !seen.has(`${f.name}:${f.size}`))];
    });
  };

  // The category list is needed to pick "put everything in", before any file is read.
  const loadCategories = async () => {
    if (categories) return;
    try {
      const res = await apiFetch('/categories');
      setCategories((res.data || []).map((c) => ({ id: c.id, name: c.name })));
    } catch { setCategories([]); }
  };

  const read = async () => {
    if (nothing || reading) return;
    setError(''); setDone(null);

    const batches = planBatches(files, raw, { together });
    const results = [];
    let failed = 0;

    for (let i = 0; i < batches.length; i += 1) {
      const batch = batches[i];
      const label = batch.files.length === 1 ? batch.files[0].name : batch.files.length ? `${batch.files.length} files` : 'pasted text';
      setProgress({ done: i, total: batches.length, label });

      try {
        results.push(await parseImport({
          files: batch.files, text: batch.text, hint, defaultStock: Number(defaultStock) || 0, categoryId: wholeCategory,
        }, token));
      } catch (err) {
        failed += 1;
        results.push({ rows: [], problems: [`${label}: ${err.message}`] });
      }
    }

    const merged = mergeResults(results);
    setProgress(null);

    if (merged.rows.length === 0) {
      setResult(null);
      setError(merged.problems.length
        ? merged.problems.join(' ')
        : 'No products were found in what you added. Check the files and try again.');
      return;
    }

    setCategories(merged.categories);
    setResult(merged);
    setRows(sortedForReview(merged.rows.map((r) => ({ ...r, include: r.importable && !r.possible_duplicate }))));
    if (failed) setError(`${failed} of ${batches.length} could not be read. The rest is below.`);
  };

  // A row that was missing something and is now complete gets ticked: fixing it means the owner wants it.
  const updateRow = (index, patch) => setRows((prev) => prev.map((r) => {
    if (r.index !== index) return r;
    const next = { ...r, ...patch };
    if (!('include' in patch) && !isReady(r) && isReady(next) && !r.possible_duplicate) next.include = true;
    return next;
  }));
  const removeRow = (index) => setRows((prev) => prev.filter((r) => r.index !== index));

  const included = rows.filter((r) => r.include);
  const ready = included.filter(isReady);
  const toCheck = rows.filter((r) => attention(r) === 'check').length;

  const commit = async () => {
    if (!ready.length) return;
    setCommitting(true); setError('');
    try {
      const res = await apiFetch(`${basePath}/commit`, { method: 'POST', token, body: commitBody(rows, status) });
      setDone(res.data);
      setResult(null); setRows([]); setFiles([]); setRaw('');
    } catch (err) {
      setError(err.message);
    } finally { setCommitting(false); }
  };

  const reset = () => {
    setResult(null); setRows([]); setDone(null); setError(''); setFiles([]); setRaw(''); setProgress(null);
  };

  return (
    <div className="space-y-5">
      <header>
        <h2 className="text-lg font-black text-ink flex items-center gap-2">
          <UploadCloud className="w-5 h-5 text-accent" /> Add products from files
        </h2>
        <p className="text-xs text-ink-muted font-medium mt-0.5">
          Drop product photos, a PDF catalogue, a Word or Excel price list, or paste text. They are read into
          products for you to check. Nothing is created until you import.
        </p>
      </header>

      {done && (
        <div className="p-4 border border-success/30 bg-success/5 rounded-card flex items-start gap-3">
          <CheckCircle2 className="w-5 h-5 text-success shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm font-black text-ink">
              {done.created} product{done.created === 1 ? '' : 's'} added as {done.status === 'ACTIVE' ? 'live' : 'draft'}.
            </p>
            <p className="text-xs text-ink-subtle font-medium mt-1">
              {done.products?.map((p) => p.title).slice(0, 5).join(' · ')}
              {done.products?.length > 5 ? ` +${done.products.length - 5} more` : ''}
            </p>
            {done.status !== 'ACTIVE' && (
              <p className="text-xs text-ink-muted font-medium mt-1">
                Open Products to add any missing photos, then publish them.
              </p>
            )}
          </div>
          <button onClick={reset} className="text-[11px] font-bold text-accent hover:underline shrink-0">Add more</button>
        </div>
      )}

      {error && (
        <p role="alert" className="text-xs font-bold text-danger flex items-start gap-1.5">
          <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" /> <span>{error}</span>
        </p>
      )}

      {!result && !done && (
        <div className="space-y-4">
          <div
            role="presentation"
            onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
            onDragLeave={() => setDragging(false)}
            onDrop={(e) => { e.preventDefault(); setDragging(false); addFiles(e.dataTransfer.files); }}
          >
            <label
              className={`flex flex-col items-center justify-center gap-2 text-center border-2 border-dashed rounded-card px-6 py-10 cursor-pointer transition ${
                dragging ? 'border-accent bg-accent/5' : 'border-line hover:border-line-strong bg-surface'
              }`}
            >
              <input
                type="file"
                multiple
                accept={ACCEPT}
                className="sr-only"
                onChange={(e) => { addFiles(e.target.files); e.target.value = ''; }}
              />
              <UploadCloud className="w-8 h-8 text-accent" />
              <span className="text-sm font-black text-ink">Drop files here, or click to choose</span>
              <span className="text-xs text-ink-muted font-medium">
                Photos (JPG, PNG, WebP) · PDF · Word (.docx) · Excel (.xlsx) · CSV · text. Photos and PDFs are read by AI.
              </span>
            </label>
          </div>

          {files.length > 0 && (
            <ul className="divide-y divide-line border border-line rounded-card bg-surface">
              {files.map((f) => (
                <li key={`${f.name}:${f.size}`} className="flex items-center gap-3 px-3 py-2 text-xs">
                  <FileIcon file={f} />
                  <span className="flex-1 min-w-0 truncate font-semibold text-ink">{f.name}</span>
                  <span className="text-ink-subtle">{size(f.size)}</span>
                  <button
                    type="button"
                    onClick={() => setFiles((prev) => prev.filter((x) => x !== f))}
                    aria-label={`Remove ${f.name}`}
                    className="text-ink-subtle hover:text-danger"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                </li>
              ))}
            </ul>
          )}

          <textarea
            value={raw}
            onChange={(e) => setRaw(e.target.value)}
            placeholder={PLACEHOLDER}
            rows={5}
            aria-label="Paste product details"
            className="w-full bg-surface border border-line rounded-card px-4 py-3 text-xs font-mono text-ink focus:outline-none focus:border-accent resize-y"
          />

          <div className="grid sm:grid-cols-2 gap-3 text-xs">
            <label className="block">
              <span className="block font-bold text-ink-muted mb-1">Put products in this category when it isn&apos;t clear</span>
              <select
                value={wholeCategory}
                onFocus={loadCategories}
                onChange={(e) => setWholeCategory(e.target.value)}
                className="w-full bg-surface border border-line rounded-control px-3 py-2 font-semibold text-ink focus:outline-none focus:border-accent"
              >
                <option value="">Decide from the files</option>
                {(categories || []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="block font-bold text-ink-muted mb-1">Stock when the file doesn&apos;t say</span>
              <input
                type="number" min="0" value={defaultStock}
                onChange={(e) => setDefaultStock(e.target.value)}
                className="w-full bg-surface border border-line rounded-control px-3 py-2 font-semibold text-ink focus:outline-none focus:border-accent"
              />
            </label>
            <label className="block sm:col-span-2">
              <span className="block font-bold text-ink-muted mb-1">A note for the reader <span className="font-normal">(optional)</span></span>
              <input
                value={hint} maxLength={500} onChange={(e) => setHint(e.target.value)}
                placeholder="e.g. All of these are Acme brand. Prices are inclusive of GST."
                className="w-full bg-surface border border-line rounded-control px-3 py-2 font-semibold text-ink focus:outline-none focus:border-accent"
              />
            </label>
            {files.some(isPicture) && files.some((f) => !isPicture(f) && !isTable(f)) && (
              <label className="sm:col-span-2 flex items-start gap-2 text-ink-muted font-semibold">
                <input type="checkbox" checked={together} onChange={(e) => setTogether(e.target.checked)} className="mt-0.5 accent-primary" />
                <span>The photos and the document are about the same products (so prices and details are matched to the photos)</span>
              </label>
            )}
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={read}
              disabled={nothing || reading}
              className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50 inline-flex items-center gap-2"
            >
              {reading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Sparkles className="w-4 h-4" />}
              {reading ? 'Reading…' : 'Read and review'}
            </button>
            {reading && (
              <span role="status" className="text-xs font-semibold text-ink-muted">
                {progress.done + 1} of {progress.total}: {progress.label}
              </span>
            )}
          </div>
        </div>
      )}

      {result && (
        <div className="space-y-4">
          <div className="flex items-start justify-between gap-3 text-xs">
            <div className="space-y-1">
              <p className="font-bold text-ink">
                {rows.length} product{rows.length === 1 ? '' : 's'} found
                <span className="text-ink-muted font-semibold">
                  {' '}· read by {result.drivers.map((d) => ({ table: 'table reader', ai: 'AI', basic: 'basic reader' }[d] || d)).join(' and ')}
                </span>
              </p>
              {toCheck > 0 ? (
                <p className="text-warning font-bold">{toCheck} need{toCheck === 1 ? 's' : ''} a closer look. They are at the top.</p>
              ) : (
                <p className="text-success font-bold">Nothing looks doubtful. Give each a quick read before importing.</p>
              )}
              {result.problems.map((p) => <p key={p} className="text-warning font-semibold">{p}</p>)}
              {result.notes.map((p) => <p key={p} className="text-ink-muted font-medium">{p}</p>)}
            </div>
            <button onClick={reset} className="text-danger font-bold hover:underline shrink-0">Start over</button>
          </div>

          <div className="space-y-3">
            {rows.map((row) => (
              <ImportRow
                key={row.index}
                row={row}
                categories={result.categories}
                token={token}
                onCategoryCreated={(c) => setResult((r) => ({ ...r, categories: [...r.categories, c] }))}
                onChange={(patch) => updateRow(row.index, patch)}
                onRemove={() => removeRow(row.index)}
              />
            ))}
            {rows.length === 0 && (
              <p className="text-xs text-ink-subtle font-medium py-6 text-center">No products left. Start over to add more files.</p>
            )}
          </div>

          {rows.length > 0 && (
            <div className="sticky bottom-0 bg-surface border border-line rounded-card p-4 flex flex-wrap items-center justify-between gap-3 shadow-card">
              <div className="text-xs font-bold text-ink-muted">
                <span className="text-ink">{ready.length}</span> of {included.length} ticked ready to import
                {included.length - ready.length > 0 && (
                  <span className="text-warning"> · {included.length - ready.length} missing a title, price or category</span>
                )}
              </div>
              <div className="flex items-center gap-3">
                <select
                  value={status}
                  aria-label="Import as"
                  onChange={(e) => setStatus(e.target.value)}
                  className="bg-surface border border-line rounded-control px-3 py-2 text-xs font-bold text-ink focus:outline-none focus:border-accent"
                >
                  <option value="DRAFT">Import as draft (not visible to shoppers)</option>
                  <option value="ACTIVE">Import as live</option>
                </select>
                <button
                  onClick={commit}
                  disabled={committing || ready.length === 0}
                  className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50 flex items-center gap-1.5"
                >
                  <PackagePlus className="w-4 h-4" />
                  {committing ? 'Importing…' : `Import ${ready.length}`}
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

const FIELD = 'w-full bg-surface-muted border rounded-control px-2.5 py-1.5 text-xs font-bold text-ink focus:outline-none focus:border-accent';
const LABEL = 'block text-[9px] font-bold text-ink-subtle uppercase mb-0.5';

function toneOf(row, field) {
  const c = row.confidence?.[field];
  if (c == null) return 'border-line';
  if (c >= 0.8) return 'border-success/40';
  if (c >= 0.5) return 'border-warning/40';
  return 'border-danger';
}

/** One product read from the files: editable, with its photos, doubtful fields marked, and the reasons listed. */
function ImportRow({ row, categories, token, onCategoryCreated, onChange, onRemove }) {
  const [open, setOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const level = attention(row);
  const variants = row.variants || [];
  const specCount = (row.specifications || []).reduce((n, g) => n + g.rows.length, 0);

  const createCategory = async () => {
    setCreating(true);
    try {
      const res = await apiFetch('/categories', { method: 'POST', token, body: { name: row.category_hint } });
      onCategoryCreated({ id: res.data.id, name: res.data.name, slug: res.data.slug });
      onChange({ category_id: res.data.id });
    } catch { /* the category list still works */ } finally { setCreating(false); }
  };

  const setVariant = (i, patch) => onChange({ variants: variants.map((v, j) => (j === i ? { ...v, ...patch } : v)) });

  return (
    <div className={`p-4 border rounded-card bg-surface space-y-3 ${row.include ? (level === 'check' ? 'border-warning/60' : 'border-line') : 'border-line opacity-50'}`}>
      <div className="flex items-start gap-3">
        <input
          type="checkbox"
          checked={row.include}
          onChange={(e) => onChange({ include: e.target.checked })}
          aria-label={`Import ${row.title || 'this product'}`}
          className="mt-1 w-4 h-4 accent-primary cursor-pointer shrink-0"
        />

        <div className="shrink-0 w-16">
          {(row.images || []).length > 0 ? (
            <div className="relative">
              <img src={row.images[0]} alt="" className="w-16 h-16 rounded-control object-cover border border-line bg-surface-sunken" />
              {row.images.length > 1 && (
                <span className="absolute -bottom-1 -right-1 bg-inverse text-ink-inverse text-[9px] font-black rounded-pill px-1.5 py-0.5">+{row.images.length - 1}</span>
              )}
            </div>
          ) : (
            <div className="w-16 h-16 rounded-control border border-dashed border-line flex items-center justify-center text-ink-subtle">
              <ImageIcon className="w-5 h-5" />
            </div>
          )}
        </div>

        <div className="flex-1 grid grid-cols-2 gap-2.5 min-w-0">
          <label className="col-span-2 block">
            <span className={LABEL}>Title</span>
            <input value={row.title || ''} onChange={(e) => onChange({ title: e.target.value })} className={`${FIELD} ${toneOf(row, 'title')}`} />
          </label>

          <label className="block">
            <span className={LABEL}>Price (₹)</span>
            <input
              type="number" step="0.01" value={row.price ?? ''}
              onChange={(e) => onChange({ price: e.target.value === '' ? null : Number(e.target.value) })}
              className={`${FIELD} ${toneOf(row, 'price')}`}
            />
          </label>
          <label className="block">
            <span className={LABEL}>MRP (₹)</span>
            <input
              type="number" step="0.01" value={row.mrp ?? ''}
              onChange={(e) => onChange({ mrp: e.target.value === '' ? null : Number(e.target.value) })}
              className={`${FIELD} ${toneOf(row, 'mrp')}`}
            />
          </label>

          <label className="block">
            <span className={LABEL}>Category{row.category_hint && !row.category_id ? ` (found “${row.category_hint}”)` : ''}</span>
            <select
              value={row.category_id || ''}
              onChange={(e) => onChange({ category_id: e.target.value || null })}
              className={`${FIELD} ${toneOf(row, 'category')}`}
            >
              <option value="">Choose a category</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </label>
          <label className="block">
            <span className={LABEL}>Brand</span>
            <input value={row.brand || ''} onChange={(e) => onChange({ brand: e.target.value })} className={`${FIELD} border-line`} />
          </label>

          {row.category_hint && !row.category_id && (
            <button
              type="button" onClick={createCategory} disabled={creating}
              className="col-span-2 justify-self-start inline-flex items-center gap-1 text-[11px] font-bold text-accent hover:underline disabled:opacity-50"
            >
              <Plus className="w-3 h-3" /> Create the category “{row.category_hint}”
            </button>
          )}
        </div>

        <button onClick={onRemove} className="text-ink-subtle hover:text-danger shrink-0" aria-label={`Remove ${row.title || 'row'}`}>
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      </div>

      {row.issues?.length > 0 && (
        <ul className="pl-7 space-y-1">
          {row.issues.map((issue) => (
            <li key={issue} className="text-[11px] text-warning font-semibold flex items-start gap-1">
              <AlertTriangle className="w-3 h-3 shrink-0 mt-0.5" /> {issue}
            </li>
          ))}
        </ul>
      )}

      <div className="pl-7 flex items-center justify-between gap-3 text-[11px] font-semibold text-ink-subtle">
        <span className="truncate">
          {variants.length} variant{variants.length === 1 ? '' : 's'}
          {row.features?.length ? ` · ${row.features.length} highlights` : ''}
          {specCount ? ` · ${specCount} specifications` : ''}
          {row.weight_grams ? ` · ${row.weight_grams} g` : ''}
          {row.source ? ` · from ${row.source}` : ''}
        </span>
        <button type="button" onClick={() => setOpen((v) => !v)} aria-expanded={open} className="inline-flex items-center gap-1 text-accent font-bold shrink-0">
          {open ? 'Hide details' : 'Show details'} {open ? <ChevronUp className="w-3 h-3" /> : <ChevronDown className="w-3 h-3" />}
        </button>
      </div>

      {open && (
        <div className="pl-7 space-y-3 text-xs">
          <label className="block">
            <span className={LABEL}>Description</span>
            <textarea
              rows={4} value={row.description || ''} onChange={(e) => onChange({ description: e.target.value })}
              className={`${FIELD} font-medium resize-y ${toneOf(row, 'description')}`}
            />
          </label>

          <label className="block">
            <span className={LABEL}>Highlights (one per line)</span>
            <textarea
              rows={3} value={(row.features || []).join('\n')}
              onChange={(e) => onChange({ features: e.target.value.split('\n') })}
              className={`${FIELD} font-medium resize-y border-line`}
            />
          </label>

          <div>
            <span className={LABEL}>Colours and sizes</span>
            <div className="overflow-x-auto">
              <table className="w-full text-left">
                <thead>
                  <tr className="text-[9px] uppercase text-ink-subtle">
                    <th className="pr-2 font-bold">Colour</th><th className="pr-2 font-bold">Size</th><th className="pr-2 font-bold">SKU</th>
                    <th className="pr-2 font-bold">Stock</th><th className="pr-2 font-bold">Own price</th><th />
                  </tr>
                </thead>
                <tbody>
                  {variants.map((v, i) => (
                    <tr key={i}>
                      {['color', 'size', 'sku'].map((k) => (
                        <td key={k} className="pr-2 py-0.5">
                          <input aria-label={`${k} ${i + 1}`} value={v[k] || ''} onChange={(e) => setVariant(i, { [k]: e.target.value })} className={`${FIELD} border-line`} />
                        </td>
                      ))}
                      <td className="pr-2 py-0.5 w-20">
                        <input aria-label={`stock ${i + 1}`} type="number" min="0" value={v.stock ?? ''} onChange={(e) => setVariant(i, { stock: e.target.value })} className={`${FIELD} border-line`} />
                      </td>
                      <td className="pr-2 py-0.5 w-24">
                        <input aria-label={`price ${i + 1}`} type="number" step="0.01" value={v.price ?? ''} onChange={(e) => setVariant(i, { price: e.target.value === '' ? null : e.target.value })} className={`${FIELD} border-line`} />
                      </td>
                      <td className="py-0.5">
                        <button
                          type="button" aria-label={`Remove variant ${i + 1}`}
                          onClick={() => onChange({ variants: variants.filter((_, j) => j !== i) })}
                          className="text-ink-subtle hover:text-danger"
                        ><X className="w-3 h-3" /></button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {specCount > 0 && (
            <div>
              <span className={LABEL}>Specifications found</span>
              <dl className="grid sm:grid-cols-2 gap-x-6">
                {row.specifications.flatMap((g) => g.rows.map((r) => (
                  <div key={`${g.title}-${r.label}`} className="py-1 border-b border-line">
                    <dt className="text-[10px] text-ink-subtle">{r.label}</dt>
                    <dd className="font-semibold text-ink">{r.value}</dd>
                  </div>
                )))}
              </dl>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
