'use client';

import React, { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import {
  AlertTriangle, ArrowLeft, ArrowRight, Check, ChevronDown, Plus, RefreshCw, Settings2, Star, Trash2, Upload, X,
} from 'lucide-react';
import { Button } from '@ds/ui';
import { apiFetch, mapCategory, mapProduct } from '../../lib/apiClient';
import { uploadFile } from '../../lib/uploads';
import { formFromImportRow } from '../../lib/importRows';
import { DELIVERY_PROFILES } from '../../lib/productOptions';
import {
  EMPTY_FORM, EMPTY_VARIANT, autoSlug, colourPhotosOf, formFromProduct, hasVariantOptions, payloadFromForm, readiness,
} from '../../lib/productForm';
import AiFillPanel from './AiFillPanel';
import RichTextEditor from './RichTextEditor';
import SpecificationsEditor from './SpecificationsEditor';
import OptionGroupsEditor from './OptionGroupsEditor';
import ProductFormModal from './ProductFormModal';

/**
 * The add / edit product page: six short steps, the same ones the phone seller app uses.
 * Only a name and a category are needed to start, and a draft can be saved at any step.
 * Showcase extras (360° view, hotspots, hover photo, SEO text, badges, store pickup) are not
 * here: they are in the advanced editor, opened from the last step of a saved product, and
 * whatever was set there is carried through untouched when the page saves.
 */

const STEPS = [
  { id: 'basics', label: 'Basics', hint: 'Name, category, description' },
  { id: 'photos', label: 'Photos', hint: 'The first one is the cover' },
  { id: 'price', label: 'Price & stock', hint: 'What it costs, how many you have' },
  { id: 'delivery', label: 'Delivery', hint: 'Weight and size of the parcel' },
  { id: 'details', label: 'Details', hint: 'Optional: what shoppers read' },
  { id: 'review', label: 'Review', hint: 'Check it, then publish' },
];

const SIZE_CHIPS = ['S', 'M', 'L', 'XL', 'XXL'];

const MANUFACTURER_FIELDS = [
  ['generic_name', 'Generic name', 'e.g. Shirt'],
  ['country_of_origin', 'Country of origin', 'e.g. India'],
  ['manufacturer_name', 'Manufacturer name', ''],
  ['manufacturer_address', 'Manufacturer address', ''],
  ['packer_name', 'Packer name', ''],
  ['packer_address', 'Packer address', ''],
];

const inputCls =
  'w-full bg-surface-muted border border-line rounded-card px-4 py-3 text-sm font-semibold text-ink focus:outline-none focus:border-line-strong transition';
const smallInputCls =
  'w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-semibold text-ink focus:outline-none focus:border-line-strong';

function Field({ id, label, hint, required, children }) {
  return (
    <div>
      <label htmlFor={id} className="block text-sm font-bold text-ink mb-1.5">
        {label}
        {required && <span className="text-danger"> *</span>}
        {!required && <span className="text-ink-subtle font-normal"> (optional)</span>}
      </label>
      {children}
      {hint && <p className="text-xs text-ink-subtle font-medium mt-1.5">{hint}</p>}
    </div>
  );
}

function StepTitle({ title, children }) {
  return (
    <div className="mb-5">
      <h2 className="text-lg font-black text-ink">{title}</h2>
      {children && <p className="text-sm text-ink-subtle font-medium mt-0.5">{children}</p>}
    </div>
  );
}

function Disclosure({ title, hint, children, defaultOpen = false }) {
  return (
    <details className="group rounded-card border border-line bg-surface" open={defaultOpen}>
      <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3">
        <span>
          <span className="block text-sm font-black text-ink">{title}</span>
          {hint && <span className="block text-xs font-medium text-ink-subtle mt-0.5">{hint}</span>}
        </span>
        <ChevronDown className="h-4 w-4 shrink-0 text-ink-subtle transition group-open:rotate-180" />
      </summary>
      <div className="border-t border-line px-4 py-4 space-y-4">{children}</div>
    </details>
  );
}

export default function ProductEditor({ productId, token }) {
  const router = useRouter();
  const isEdit = productId !== 'new';

  const [form, setForm] = useState(EMPTY_FORM);
  const [product, setProduct] = useState(null); // the saved product, once loaded
  const [categories, setCategories] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [step, setStep] = useState('basics');
  const [visited, setVisited] = useState(['basics']);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState('');
  const [uploadError, setUploadError] = useState('');
  const [linkInput, setLinkInput] = useState('');
  const [featureInput, setFeatureInput] = useState('');
  const [showAdvanced, setShowAdvanced] = useState(false);
  // Whether this product is sold in sizes or colours. A choice the admin makes, not something to guess
  // from the rows: turning it on must not need a made-up row to stay on.
  const [optionsOn, setOptionsOn] = useState(false);
  const baseline = useRef(JSON.stringify(EMPTY_FORM));
  const topRef = useRef(null);

  const setField = (key, value) => setForm((f) => ({ ...f, [key]: value }));
  const dirty = JSON.stringify(form) !== baseline.current;

  const load = (saved) => {
    const next = formFromProduct(saved);
    baseline.current = JSON.stringify(next);
    setProduct(saved);
    setForm(next);
    setOptionsOn(hasVariantOptions(next.variants));
  };

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const cats = await apiFetch('/categories');
        if (live) setCategories((cats.data || []).map(mapCategory));
        if (isEdit) {
          const res = await apiFetch(`/products/${productId}`, { token });
          if (live) load(mapProduct(res.data));
        }
      } catch (e) {
        if (live) setLoadError(e.message || 'Could not load this product.');
      } finally {
        if (live) setLoading(false);
      }
    })();
    return () => { live = false; };
  }, [productId, token]);

  // Closing the tab with unsaved changes loses a long form: ask first.
  useEffect(() => {
    if (!dirty) return undefined;
    const warn = (e) => { e.preventDefault(); e.returnValue = ''; };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [dirty]);

  const go = (id) => {
    setError('');
    setStep(id);
    setVisited((v) => (v.includes(id) ? v : [...v, id]));
    topRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  const stepIndex = STEPS.findIndex((s) => s.id === step);
  const check = readiness(form);
  const issuesFor = (id) => check.required.filter((r) => r.step === id).length;

  // ── photos: the first is the cover, the rest are the gallery ────────────────────────────
  const photos = [form.image, ...form.gallery].filter(Boolean);
  const setPhotos = (list) => setForm((f) => ({ ...f, image: list[0] || '', gallery: list.slice(1) }));

  const addPhotos = async (fileList) => {
    const files = Array.from(fileList || []);
    if (!files.length) return;
    setUploading('photos');
    setUploadError('');
    const added = [];
    try {
      for (const file of files) added.push(await uploadFile(file, token));
    } catch (e) {
      setUploadError(e.message);
    } finally {
      // Keep the ones that did go up, even if a later one failed.
      if (added.length) setForm((f) => { const all = [f.image, ...f.gallery].filter(Boolean).concat(added); return { ...f, image: all[0], gallery: all.slice(1) }; });
      setUploading('');
    }
  };
  const addLink = () => {
    const url = linkInput.trim();
    if (!url) return;
    setPhotos([...photos, url]);
    setLinkInput('');
  };
  const makeCover = (i) => setPhotos([photos[i], ...photos.filter((_, j) => j !== i)]);

  // ── variants ──────────────────────────────────────────────────────────────────────────
  const hasOptions = optionsOn;
  const totalStock = form.variants.reduce((n, v) => n + (parseInt(v.stock, 10) || 0), 0);
  const updateVariant = (i, key, val) =>
    setForm((f) => ({ ...f, variants: f.variants.map((v, j) => (j === i ? { ...v, [key]: val } : v)) }));
  const addVariant = (extra = {}) =>
    setForm((f) => ({ ...f, variants: [...f.variants, { ...EMPTY_VARIANT, ...extra }] }));
  const removeVariant = (i) => setForm((f) => ({ ...f, variants: f.variants.filter((_, j) => j !== i) }));

  const toggleOptions = (on) => {
    if (on) {
      setOptionsOn(true);
      return;
    }
    if (form.variants.length > 1 && !window.confirm(`This removes ${form.variants.length} size or colour rows and keeps one stock figure. Continue?`)) return;
    setOptionsOn(false);
    setForm((f) => {
      const first = f.variants[0] || EMPTY_VARIANT;
      const sum = f.variants.reduce((n, v) => n + (parseInt(v.stock, 10) || 0), 0);
      return { ...f, variants: [{ ...first, color: '', colorHex: '', size: '', price: '', mrp: '', images: [], stock: String(sum) }] };
    });
  };

  const addSize = (size) => {
    setForm((f) => {
      if (f.variants.some((v) => (v.size || '').toLowerCase() === size.toLowerCase())) return f;
      const blank = (v) => !v.color && !v.size && !v.sku && !v.price && !v.mrp && !v.id;
      const rows = f.variants.length === 1 && blank(f.variants[0]) ? [] : f.variants;
      return { ...f, variants: [...rows, { ...EMPTY_VARIANT, size }] };
    });
  };

  const colourMap = colourPhotosOf(form.variants);
  const setColourPhotos = (key, urls) =>
    setForm((f) => ({
      ...f,
      variants: f.variants.map((v) => ((v.color || '').trim().toLowerCase() === key ? { ...v, images: urls } : v)),
    }));
  const addColourPhotos = async (key, fileList) => {
    const files = Array.from(fileList || []);
    if (!files.length) return;
    setUploading(`color-${key}`);
    setUploadError('');
    try {
      const added = [];
      for (const file of files) added.push(await uploadFile(file, token));
      setColourPhotos(key, [...(colourMap[key]?.photos || []), ...added]);
    } catch (e) {
      setUploadError(e.message);
    } finally {
      setUploading('');
    }
  };

  // ── AI fill ───────────────────────────────────────────────────────────────────────────
  const fillFromRow = (row) => {
    const { form: next, filled } = formFromImportRow(form, row);
    if (!isEdit && !next.slug && next.title) next.slug = autoSlug(next.title);
    setForm(next);
    if (hasVariantOptions(next.variants)) setOptionsOn(true);
    return { filled };
  };

  // ── save ──────────────────────────────────────────────────────────────────────────────
  const save = async (status) => {
    setError('');
    // Rows left empty (no colour, no size) are not real options: do not save them as extra variants.
    const named = form.variants.filter((v) => v.id || (v.color || '').trim() || (v.size || '').trim());
    const candidate = { ...form, status, variants: optionsOn && named.length ? named : form.variants.slice(0, 1) };
    if (status === 'ACTIVE') {
      const missing = readiness(candidate).required;
      if (missing.length) {
        setError(`Not ready to go live yet: ${missing.map((m) => m.text.toLowerCase()).join('; ')}.`);
        go(missing[0].step);
        return;
      }
    } else if (!candidate.title.trim() || !candidate.categoryId) {
      setError('A draft needs at least a name and a category.');
      go('basics');
      return;
    }

    setSaving(true);
    try {
      await apiFetch(isEdit ? `/products/${productId}` : '/products', {
        method: isEdit ? 'PUT' : 'POST',
        token,
        body: payloadFromForm(candidate),
      });
      baseline.current = JSON.stringify(form); // so leaving the page does not warn
      router.push(`/admin?section=products&saved=${isEdit ? 'edit' : 'new'}`);
    } catch (e) {
      setError(e.message || 'Could not save the product.');
      setSaving(false);
    }
  };

  const leave = (e) => {
    if (dirty && !window.confirm('Leave without saving? What you entered on this page will be lost.')) e.preventDefault();
  };

  // ── render helpers ────────────────────────────────────────────────────────────────────
  const category = categories.find((c) => c.id === form.categoryId);
  const filterGroups = (category?.filterConfig || category?.filter_config)?.groups || [];
  const discount = (() => {
    const p = parseFloat(form.price);
    const m = parseFloat(form.mrp);
    return p > 0 && m > p ? Math.round(((m - p) / m) * 100) : 0;
  })();
  const toggleFilter = (group, opt) => {
    const value = opt.value || opt.label;
    setForm((f) => {
      const on = f.lifestyleBadges.includes(value) || f.lifestyleBadges.includes(opt.label);
      const tags = on
        ? f.lifestyleBadges.filter((t) => t !== value && t !== opt.label)
        : Array.from(new Set([...f.lifestyleBadges, value, opt.label]));
      const brandPick = group.id === 'brand' ? { brand: on ? '' : value } : {};
      return { ...f, lifestyleBadges: tags, ...brandPick };
    });
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-surface-muted flex items-center justify-center">
        <RefreshCw className="w-8 h-8 text-ink-subtle animate-spin" />
        <span className="sr-only">Loading</span>
      </div>
    );
  }
  if (loadError) {
    return (
      <div className="min-h-screen bg-surface-muted flex items-center justify-center p-6">
        <div className="max-w-md rounded-panel border border-line bg-surface p-8 text-center">
          <AlertTriangle className="mx-auto h-8 w-8 text-warning" />
          <h1 className="mt-3 text-lg font-black text-ink">This product could not be opened</h1>
          <p className="mt-1 text-sm text-ink-subtle">{loadError}</p>
          <Link href="/admin?section=products" className="mt-5 inline-block rounded-card bg-inverse px-4 py-2.5 text-sm font-bold text-ink-inverse">
            Back to products
          </Link>
        </div>
      </div>
    );
  }

  const liveLabel = isEdit ? 'Save changes' : form.status === 'DRAFT' ? 'Save draft' : 'Publish product';

  return (
    <div className="min-h-screen bg-surface-muted pb-28">
      <header className="sticky top-0 z-30 border-b border-line bg-surface">
        <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3">
          <Link
            href="/admin?section=products"
            onClick={leave}
            className="inline-flex items-center gap-1.5 rounded-control px-2 py-1.5 text-sm font-bold text-ink-muted hover:bg-surface-sunken hover:text-ink"
          >
            <ArrowLeft className="h-4 w-4" /> Products
          </Link>
          <div className="min-w-0 flex-1">
            <h1 className="truncate text-base font-black text-ink">
              {isEdit ? (form.title || 'Edit product') : 'Add product'}
            </h1>
            <p className="text-xs font-medium text-ink-subtle">
              Step {stepIndex + 1} of {STEPS.length} · {STEPS[stepIndex].label}
              {dirty && <span className="text-warning"> · unsaved changes</span>}
            </p>
          </div>
        </div>
        <nav aria-label="Steps" className="mx-auto flex max-w-6xl gap-1 overflow-x-auto px-4 pb-2">
          {STEPS.map((s, i) => {
            const issues = issuesFor(s.id);
            const done = visited.includes(s.id) && s.id !== step && issues === 0;
            return (
              <button
                key={s.id}
                type="button"
                onClick={() => go(s.id)}
                aria-current={s.id === step ? 'step' : undefined}
                className={`flex shrink-0 items-center gap-2 rounded-pill px-3 py-1.5 text-xs font-bold transition ${
                  s.id === step ? 'bg-inverse text-ink-inverse' : 'text-ink-muted hover:bg-surface-sunken'
                }`}
              >
                <span className={`flex h-5 w-5 items-center justify-center rounded-pill text-2xs ${
                  s.id === step ? 'bg-surface text-ink' : done ? 'bg-success text-on-primary' : 'bg-surface-sunken text-ink-muted'
                }`}>
                  {done ? <Check className="h-3 w-3" /> : i + 1}
                </span>
                {s.label}
                {issues > 0 && visited.includes(s.id) && s.id !== step && (
                  <span className="h-1.5 w-1.5 rounded-pill bg-danger" title="Something is missing here" />
                )}
              </button>
            );
          })}
        </nav>
      </header>

      <div ref={topRef} className="mx-auto grid max-w-6xl gap-6 px-4 py-6 lg:grid-cols-[minmax(0,1fr)_280px]">
        <main className="min-w-0 rounded-panel border border-line bg-surface p-5 sm:p-7">
          {error && (
            <div role="alert" className="mb-5 flex gap-2 rounded-card border border-danger bg-danger-soft p-3 text-sm font-bold text-danger">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> {error}
            </div>
          )}

          {/* ── 1. BASICS ───────────────────────────────────────────────── */}
          {step === 'basics' && (
            <div className="space-y-5">
              <StepTitle title="What are you selling?">
                Only the name and category are needed to start. You can save a draft at any step.
              </StepTitle>
              <AiFillPanel token={token} onFill={fillFromRow} />
              <Field id="pe-title" label="Product name" required>
                <input
                  id="pe-title"
                  className={inputCls}
                  value={form.title}
                  maxLength={255}
                  onChange={(e) => setForm((f) => ({ ...f, title: e.target.value, ...(isEdit ? {} : { slug: autoSlug(e.target.value) }) }))}
                  placeholder="e.g. Chanderi Silk Anarkali Set"
                />
              </Field>
              <Field id="pe-category" label="Category" required>
                <select id="pe-category" className={inputCls} value={form.categoryId} onChange={(e) => setField('categoryId', e.target.value)}>
                  <option value="">Choose a category</option>
                  {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
              </Field>
              <Field id="pe-brand" label="Brand" hint="Leave empty if it has none.">
                <input id="pe-brand" className={inputCls} value={form.brand} onChange={(e) => setField('brand', e.target.value)} />
              </Field>
              <Field id="pe-desc" label="Description" hint="Material, size, how it is used, how to care for it. Shoppers read this on the product page.">
                <RichTextEditor
                  value={form.descriptionHtml}
                  onChange={(html) => setField('descriptionHtml', html)}
                  placeholder="What makes this product worth buying?"
                />
              </Field>
            </div>
          )}

          {/* ── 2. PHOTOS ───────────────────────────────────────────────── */}
          {step === 'photos' && (
            <div className="space-y-5">
              <StepTitle title="Photos">
                The first photo is the cover shoppers see in the list. JPG, PNG or WebP. You need at least one to go live.
              </StepTitle>
              {uploadError && (
                <div role="alert" className="rounded-card border border-danger bg-danger-soft p-3 text-sm font-bold text-danger">{uploadError}</div>
              )}
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {photos.map((url, i) => (
                  <div key={url + i} className="relative overflow-hidden rounded-card border border-line bg-surface-muted">
                    <img src={url} alt={i === 0 ? 'Cover photo' : `Photo ${i + 1}`} className="aspect-square w-full object-cover" />
                    {i === 0 ? (
                      <span className="absolute left-2 top-2 rounded-pill bg-inverse px-2 py-0.5 text-2xs font-black text-ink-inverse">Cover</span>
                    ) : (
                      <button
                        type="button"
                        onClick={() => makeCover(i)}
                        className="absolute left-2 top-2 inline-flex items-center gap-1 rounded-pill bg-surface px-2 py-0.5 text-2xs font-black text-ink shadow-subtle"
                      >
                        <Star className="h-3 w-3" /> Make cover
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => setPhotos(photos.filter((_, j) => j !== i))}
                      aria-label={`Remove photo ${i + 1}`}
                      className="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-pill bg-danger text-on-primary"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ))}
                <label className="flex aspect-square cursor-pointer flex-col items-center justify-center gap-2 rounded-card border-2 border-dashed border-line text-center text-sm font-bold text-ink-muted hover:border-line-strong hover:bg-surface-muted">
                  <Upload className="h-6 w-6" />
                  <span className="sr-only">Add photos</span>
                  <span aria-hidden="true">{uploading === 'photos' ? 'Uploading…' : 'Add photos'}</span>
                  <input
                    type="file"
                    accept="image/*"
                    multiple
                    className="sr-only"
                    onChange={(e) => { addPhotos(e.target.files); e.target.value = ''; }}
                  />
                </label>
              </div>
              <Disclosure title="Add a photo from a web link instead">
                <div className="flex gap-2">
                  <input
                    aria-label="Image link"
                    type="url"
                    className={inputCls}
                    value={linkInput}
                    onChange={(e) => setLinkInput(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addLink(); } }}
                    placeholder="https://…"
                  />
                  <Button variant="secondary" size="sm" onClick={addLink}>Add</Button>
                </div>
              </Disclosure>
            </div>
          )}

          {/* ── 3. PRICE & STOCK ────────────────────────────────────────── */}
          {step === 'price' && (
            <div className="space-y-5">
              <StepTitle title="Price & stock">What shoppers pay, and the printed price it is discounted from.</StepTitle>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field id="pe-price" label="Selling price (₹)" required>
                  <input id="pe-price" type="number" min="0" inputMode="decimal" className={inputCls} value={form.price} onChange={(e) => setField('price', e.target.value)} placeholder="499" />
                </Field>
                <Field id="pe-mrp" label="Printed price, MRP (₹)" hint="Leave empty if there is no discount.">
                  <input id="pe-mrp" type="number" min="0" inputMode="decimal" className={inputCls} value={form.mrp} onChange={(e) => setField('mrp', e.target.value)} placeholder="799" />
                </Field>
              </div>
              {discount > 0 && (
                <p className="rounded-card border border-success bg-success-soft px-4 py-2.5 text-sm font-bold text-success">
                  Shoppers will see {discount}% off.
                </p>
              )}

              <label className="grid cursor-pointer grid-cols-[auto_1fr] gap-x-3 rounded-card border border-line p-4">
                <input type="checkbox" className="row-span-2 mt-1 h-4 w-4 accent-accent" checked={hasOptions} onChange={(e) => toggleOptions(e.target.checked)} />
                <span className="text-sm font-black text-ink">It comes in sizes or colours</span>
                <span className="text-xs font-medium text-ink-subtle">
                  {hasOptions ? 'Give each one its own stock, and a price only if it differs.' : 'Leave off for a single item; you only enter how many you have.'}
                </span>
              </label>

              {!hasOptions && (
                <Field id="pe-stock" label="How many do you have?" required>
                  <input
                    id="pe-stock"
                    type="number"
                    min="0"
                    inputMode="numeric"
                    className={`${inputCls} sm:max-w-48`}
                    value={form.variants[0]?.stock ?? ''}
                    onChange={(e) => updateVariant(0, 'stock', e.target.value)}
                  />
                </Field>
              )}

              {hasOptions && (
                <div className="space-y-3">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-xs font-bold text-ink-muted">Quick add sizes:</span>
                    {SIZE_CHIPS.map((s) => (
                      <button key={s} type="button" onClick={() => addSize(s)} className="rounded-pill border border-line px-3 py-1 text-xs font-bold text-ink hover:border-line-strong">
                        + {s}
                      </button>
                    ))}
                  </div>
                  {form.variants.map((v, i) => (
                    <div key={v.id || i} className="rounded-card border border-line bg-surface-muted p-3">
                      <div className="grid grid-cols-2 gap-2 sm:grid-cols-[1.3fr_1fr_0.8fr_1fr_auto]">
                        <div className="col-span-2 sm:col-span-1">
                          <label className="mb-1 block text-xs font-bold text-ink-muted" htmlFor={`pe-vc-${i}`}>Colour</label>
                          <div className="flex items-center gap-2">
                            <input id={`pe-vc-${i}`} className={smallInputCls} value={v.color} onChange={(e) => updateVariant(i, 'color', e.target.value)} placeholder="e.g. Navy" />
                            <input
                              type="color"
                              aria-label={`Swatch colour for variant ${i + 1}`}
                              title="Swatch shown to shoppers (optional)"
                              value={v.colorHex || '#cccccc'}
                              onChange={(e) => updateVariant(i, 'colorHex', e.target.value.toUpperCase())}
                              className="h-9 w-9 shrink-0 cursor-pointer rounded-pill border border-line bg-transparent p-0"
                            />
                          </div>
                        </div>
                        <div>
                          <label className="mb-1 block text-xs font-bold text-ink-muted" htmlFor={`pe-vs-${i}`}>Size</label>
                          <input id={`pe-vs-${i}`} className={smallInputCls} value={v.size} onChange={(e) => updateVariant(i, 'size', e.target.value)} placeholder="e.g. M" />
                        </div>
                        <div>
                          <label className="mb-1 block text-xs font-bold text-ink-muted" htmlFor={`pe-vk-${i}`}>Stock</label>
                          <input id={`pe-vk-${i}`} type="number" min="0" className={smallInputCls} value={v.stock} onChange={(e) => updateVariant(i, 'stock', e.target.value)} />
                        </div>
                        <div>
                          <label className="mb-1 block text-xs font-bold text-ink-muted" htmlFor={`pe-vp-${i}`}>Own price (₹)</label>
                          <input id={`pe-vp-${i}`} type="number" min="0" className={smallInputCls} value={v.price} onChange={(e) => updateVariant(i, 'price', e.target.value)} placeholder="Same" />
                        </div>
                        <div className="flex items-end justify-end">
                          {form.variants.length > 1 && (
                            <button type="button" onClick={() => removeVariant(i)} aria-label={`Remove variant ${i + 1}`} className="rounded-pill p-2 text-danger hover:bg-danger-soft">
                              <Trash2 className="h-4 w-4" />
                            </button>
                          )}
                        </div>
                      </div>
                      <details className="mt-2">
                        <summary className="cursor-pointer text-xs font-bold text-ink-subtle">More: SKU code, printed price</summary>
                        <div className="mt-2 grid grid-cols-2 gap-2">
                          <div>
                            <label className="mb-1 block text-xs font-bold text-ink-muted" htmlFor={`pe-vu-${i}`}>SKU code</label>
                            <input id={`pe-vu-${i}`} className={`${smallInputCls} font-mono`} value={v.sku} onChange={(e) => updateVariant(i, 'sku', e.target.value)} placeholder="Made up for you if empty" />
                          </div>
                          <div>
                            <label className="mb-1 block text-xs font-bold text-ink-muted" htmlFor={`pe-vm-${i}`}>Own printed price (₹)</label>
                            <input id={`pe-vm-${i}`} type="number" min="0" className={smallInputCls} value={v.mrp} onChange={(e) => updateVariant(i, 'mrp', e.target.value)} placeholder="Same" />
                          </div>
                        </div>
                      </details>
                    </div>
                  ))}
                  <Button variant="secondary" size="sm" onClick={() => addVariant()} leadingIcon={<Plus className="h-4 w-4" />}>Add another</Button>
                  <p className="text-xs font-bold text-ink-muted">Total in stock: {totalStock}</p>

                  {Object.keys(colourMap).length > 0 && (
                    <Disclosure title="Photos for each colour" hint="Optional. When a shopper picks a colour, these replace the main photos.">
                      {Object.entries(colourMap).map(([key, { name, photos: list }]) => (
                        <div key={key} className="space-y-2">
                          <div className="flex items-center justify-between gap-2">
                            <span className="text-sm font-black text-ink">{name}</span>
                            <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-control border border-line px-3 py-1.5 text-xs font-bold text-ink hover:border-line-strong">
                              <Upload className="h-3.5 w-3.5" /> <span className="sr-only">Add photos for {name}</span><span aria-hidden="true">{uploading === `color-${key}` ? 'Uploading…' : 'Add photos'}</span>
                              <input type="file" accept="image/*" multiple className="sr-only" onChange={(e) => { addColourPhotos(key, e.target.files); e.target.value = ''; }} />
                            </label>
                          </div>
                          {list.length === 0 ? (
                            <p className="text-xs text-ink-subtle">Using the main photos.</p>
                          ) : (
                            <div className="flex flex-wrap gap-2">
                              {list.map((url, i) => (
                                <div key={url + i} className="relative">
                                  <img src={url} alt={`${name}, view ${i + 1}`} className="h-20 w-20 rounded-control border border-line object-cover" />
                                  <button type="button" aria-label={`Remove ${name} photo ${i + 1}`} onClick={() => setColourPhotos(key, list.filter((_, j) => j !== i))} className="absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-pill bg-danger text-on-primary">
                                    <X className="h-3 w-3" />
                                  </button>
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      ))}
                    </Disclosure>
                  )}
                </div>
              )}
            </div>
          )}

          {/* ── 4. DELIVERY ─────────────────────────────────────────────── */}
          {step === 'delivery' && (
            <div className="space-y-5">
              <StepTitle title="Delivery">
                Couriers charge by weight and size. Without a weight the shop assumes a default, which can make delivery prices wrong.
              </StepTitle>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field id="pe-weight" label="Weight when packed (grams)" hint="1 kg is 1000.">
                  <input id="pe-weight" type="number" min="1" inputMode="numeric" className={inputCls} value={form.weightGrams} onChange={(e) => setField('weightGrams', e.target.value)} placeholder="500" />
                </Field>
              </div>
              <div>
                <p className="mb-1.5 text-sm font-bold text-ink">Parcel size in cm <span className="font-normal text-ink-subtle">(optional)</span></p>
                <div className="grid grid-cols-3 gap-3">
                  {[['lengthCm', 'Length'], ['widthCm', 'Width'], ['heightCm', 'Height']].map(([key, label]) => (
                    <div key={key}>
                      <label className="mb-1 block text-xs font-bold text-ink-muted" htmlFor={`pe-${key}`}>{label}</label>
                      <input id={`pe-${key}`} type="number" min="1" inputMode="numeric" className={inputCls} value={form[key]} onChange={(e) => setField(key, e.target.value)} />
                    </div>
                  ))}
                </div>
              </div>
              <label className="flex cursor-pointer items-center gap-3 text-sm font-bold text-ink">
                <input type="checkbox" className="h-4 w-4 accent-accent" checked={form.requiresVehicle} onChange={(e) => setField('requiresVehicle', e.target.checked)} />
                Too big for a bike: needs a vehicle
              </label>
              <label className="grid cursor-pointer grid-cols-[auto_1fr] gap-x-3 rounded-card border border-line p-4">
                <input type="checkbox" className="row-span-2 mt-1 h-4 w-4 accent-accent" checked={form.codAvailable} onChange={(e) => setField('codAvailable', e.target.checked)} />
                <span className="text-sm font-black text-ink">Allow cash on delivery</span>
                <span className="text-xs font-medium text-ink-subtle">Turn off for items you only want to sell prepaid.</span>
              </label>
              <Disclosure title="Delivery speed" hint="Leave on the category's setting unless this item is different.">
                <div className="grid gap-4 sm:grid-cols-[2fr_1fr]">
                  <Field id="pe-profile" label="Delivery type">
                    <select id="pe-profile" className={inputCls} value={form.deliveryProfile} onChange={(e) => setField('deliveryProfile', e.target.value)}>
                      <option value="">Same as the category</option>
                      {DELIVERY_PROFILES.map((d) => <option key={d.value} value={d.value}>{d.label}</option>)}
                    </select>
                  </Field>
                  <Field id="pe-prep" label="Ready in (minutes)">
                    <input id="pe-prep" type="number" min="0" max="1440" className={inputCls} value={form.prepMinutes} onChange={(e) => setField('prepMinutes', e.target.value)} placeholder="Category's" />
                  </Field>
                </div>
                {DELIVERY_PROFILES.find((d) => d.value === form.deliveryProfile) && (
                  <p className="text-xs text-ink-muted">{DELIVERY_PROFILES.find((d) => d.value === form.deliveryProfile).hint}</p>
                )}
              </Disclosure>
            </div>
          )}

          {/* ── 5. DETAILS ──────────────────────────────────────────────── */}
          {step === 'details' && (
            <div className="space-y-5">
              <StepTitle title="Details">All optional. This is what shoppers read before they buy.</StepTitle>

              <div>
                <p className="mb-1.5 text-sm font-bold text-ink">Key points <span className="font-normal text-ink-subtle">(short bullet points)</span></p>
                <div className="flex gap-2">
                  <input
                    aria-label="Add a key point"
                    className={inputCls}
                    value={featureInput}
                    onChange={(e) => setFeatureInput(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        if (featureInput.trim()) { setField('features', [...form.features, featureInput.trim()]); setFeatureInput(''); }
                      }
                    }}
                    placeholder="e.g. Pure cotton, machine washable — press Enter"
                  />
                  <Button variant="secondary" size="sm" onClick={() => { if (featureInput.trim()) { setField('features', [...form.features, featureInput.trim()]); setFeatureInput(''); } }}>Add</Button>
                </div>
                {form.features.length > 0 && (
                  <ul className="mt-2 space-y-1.5">
                    {form.features.map((f, i) => (
                      <li key={i} className="flex items-center justify-between gap-2 rounded-control bg-surface-muted px-3 py-2 text-sm font-semibold text-ink">
                        <span>{f}</span>
                        <button type="button" aria-label={`Remove: ${f}`} onClick={() => setField('features', form.features.filter((_, j) => j !== i))} className="text-ink-subtle hover:text-danger"><X className="h-4 w-4" /></button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              <div>
                <p className="mb-1 text-sm font-bold text-ink">Specifications</p>
                <p className="mb-3 text-xs font-medium text-ink-subtle">Shown as a table under &quot;All details&quot;. Rows missing a name or a value are left out.</p>
                <SpecificationsEditor groups={form.specifications} onChange={(g) => setField('specifications', g)} template={category?.specTemplate || []} />
              </div>

              <div>
                <p className="mb-1 text-sm font-bold text-ink">Manufacturer</p>
                <p className="mb-3 text-xs font-medium text-ink-subtle">Packaged goods sold in India must show who made and packed them. Leave out what does not apply.</p>
                <div className="grid gap-3 sm:grid-cols-2">
                  {MANUFACTURER_FIELDS.map(([key, label, hint]) => (
                    <div key={key} className={key.endsWith('address') ? 'sm:col-span-2' : ''}>
                      <label className="mb-1 block text-xs font-bold text-ink-muted" htmlFor={`pe-mf-${key}`}>{label}</label>
                      <input id={`pe-mf-${key}`} className={inputCls} value={form.manufacturer[key] || ''} placeholder={hint} onChange={(e) => setField('manufacturer', { ...form.manufacturer, [key]: e.target.value })} />
                    </div>
                  ))}
                </div>
              </div>

              {filterGroups.length > 0 && (
                <Disclosure title={`Filters for ${category.name}`} hint="Tick what applies, so the product shows up when shoppers filter this category." defaultOpen>
                  {filterGroups.map((group) => (
                    <div key={group.id} className="space-y-1.5">
                      <span className="text-xs font-bold text-ink-muted">{group.label}</span>
                      <div className="flex flex-wrap gap-1.5">
                        {(group.options || []).map((opt) => {
                          const value = opt.value || opt.label;
                          const on = form.lifestyleBadges.includes(value) || form.lifestyleBadges.includes(opt.label) || (group.id === 'brand' && form.brand === value);
                          return (
                            <button key={value} type="button" aria-pressed={on} onClick={() => toggleFilter(group, opt)}
                              className={`rounded-pill border px-3 py-1 text-xs font-bold transition ${on ? 'border-accent bg-accent text-on-accent' : 'border-line bg-surface text-ink hover:border-line-strong'}`}>
                              {on ? '✓ ' : '+ '}{opt.label}
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  ))}
                </Disclosure>
              )}

              <Disclosure title="More options" hint="Rarely needed: a NEW tag, choices the shopper makes, a video clip.">
                <label className="flex cursor-pointer items-center gap-3 text-sm font-bold text-ink">
                  <input type="checkbox" className="h-4 w-4 accent-accent" checked={form.isNew} onChange={(e) => setField('isNew', e.target.checked)} />
                  Show a &quot;NEW&quot; tag on the product
                </label>

                <div>
                  <p className="mb-1.5 text-sm font-bold text-ink">Choices the shopper makes <span className="font-normal text-ink-subtle">(portion, add-ons, a message…)</span></p>
                  {(() => {
                    const template = category?.optionGroups || [];
                    const modes = [
                      ['inherit', `Use the category's choices${template.length ? ` (${template.length})` : ' (none set)'}`],
                      ['custom', 'Set them for this product'],
                      ['none', 'No choices'],
                    ];
                    const pick = (mode) => {
                      if (mode === 'custom' && form.optionMode !== 'custom') {
                        const start = form.customOptions.length ? form.customOptions : template;
                        setForm((f) => ({ ...f, optionMode: 'custom', customOptions: JSON.parse(JSON.stringify(start)) }));
                      } else setField('optionMode', mode);
                    };
                    return (
                      <div className="flex flex-wrap gap-2">
                        {modes.map(([id, label]) => (
                          <label key={id} className={`flex cursor-pointer items-center gap-2 rounded-card border px-3 py-2 text-xs font-bold ${form.optionMode === id ? 'border-accent bg-accent-soft text-ink' : 'border-line text-ink-muted'}`}>
                            <input type="radio" name="pe-option-mode" className="accent-accent" checked={form.optionMode === id} onChange={() => pick(id)} />
                            {label}
                          </label>
                        ))}
                      </div>
                    );
                  })()}
                  {form.optionMode === 'custom' && (
                    <div className="mt-3"><OptionGroupsEditor groups={form.customOptions} onChange={(g) => setField('customOptions', g)} allowStock /></div>
                  )}
                </div>

                <Field id="pe-reel" label="Video clip link" hint="Only products with a clip appear in the Reels feed.">
                  <input id="pe-reel" type="url" className={inputCls} value={form.reelVideoUrl} onChange={(e) => setField('reelVideoUrl', e.target.value)} placeholder="https://…mp4" />
                </Field>
                {form.reelVideoUrl && (
                  <Field id="pe-reelcap" label="Clip caption">
                    <input id="pe-reelcap" maxLength={160} className={inputCls} value={form.reelCaption} onChange={(e) => setField('reelCaption', e.target.value)} />
                  </Field>
                )}
              </Disclosure>
            </div>
          )}

          {/* ── 6. REVIEW ───────────────────────────────────────────────── */}
          {step === 'review' && (
            <div className="space-y-5">
              <StepTitle title="Review">Check it, then choose whether it goes live.</StepTitle>

              <div className="flex gap-4 rounded-card border border-line p-4">
                {form.image ? (
                  <img src={form.image} alt="" className="h-24 w-24 shrink-0 rounded-control object-cover" />
                ) : (
                  <div className="flex h-24 w-24 shrink-0 items-center justify-center rounded-control bg-surface-sunken text-xs font-bold text-ink-subtle">No photo</div>
                )}
                <div className="min-w-0 text-sm">
                  <p className="truncate font-black text-ink">{form.title || 'Untitled product'}</p>
                  <p className="text-ink-subtle">{category?.name || 'No category'}{form.brand ? ` · ${form.brand}` : ''}</p>
                  <p className="mt-1 font-black text-ink">
                    {parseFloat(form.price) > 0 ? `₹${parseFloat(form.price).toLocaleString('en-IN')}` : 'No price yet'}
                    {discount > 0 && <span className="ml-2 text-xs font-bold text-success"> {discount}% off</span>}
                  </p>
                  <p className="text-ink-subtle">
                    {totalStock} in stock{hasOptions ? ` across ${form.variants.length} options` : ''}
                    {form.weightGrams ? ` · ${form.weightGrams} g` : ''}
                  </p>
                </div>
              </div>

              {check.required.length > 0 && (
                <div className="rounded-card border border-danger bg-danger-soft p-4">
                  <p className="text-sm font-black text-danger">Needed before it can go live</p>
                  <ul className="mt-2 space-y-1.5">
                    {check.required.map((r, i) => (
                      <li key={i} className="flex items-center justify-between gap-3 text-sm font-semibold text-ink">
                        {r.text}
                        <button type="button" onClick={() => go(r.step)} className="shrink-0 text-xs font-black text-accent underline underline-offset-2">Fix</button>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              {check.suggested.length > 0 && (
                <div className="rounded-card border border-warning bg-warning-soft p-4">
                  <p className="text-sm font-black text-warning">Suggested, not required</p>
                  <ul className="mt-2 space-y-1.5">
                    {check.suggested.map((r, i) => (
                      <li key={i} className="flex items-center justify-between gap-3 text-sm font-semibold text-ink">
                        {r.text}
                        <button type="button" onClick={() => go(r.step)} className="shrink-0 text-xs font-black text-accent underline underline-offset-2">Add</button>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              {check.ready && check.suggested.length === 0 && (
                <p className="flex items-center gap-2 rounded-card border border-success bg-success-soft p-3 text-sm font-bold text-success">
                  <Check className="h-4 w-4" /> Everything is filled in.
                </p>
              )}

              <fieldset>
                <legend className="mb-2 text-sm font-black text-ink">Status</legend>
                <div className="grid gap-2 sm:grid-cols-3">
                  {[
                    ['ACTIVE', 'Live', 'Shoppers can find and buy it.'],
                    ['DRAFT', 'Draft', 'Hidden from the shop until you publish.'],
                    ['DISCONTINUED', 'Discontinued', 'Hidden, kept for your records.'],
                  ].map(([value, label, hint]) => (
                    <label key={value} className={`cursor-pointer rounded-card border p-3 ${form.status === value ? 'border-accent bg-accent-soft' : 'border-line'}`}>
                      <span className="flex items-center gap-2 text-sm font-black text-ink">
                        <input type="radio" name="pe-status" className="accent-accent" checked={form.status === value} onChange={() => setField('status', value)} />
                        {label}
                      </span>
                      <span className="mt-1 block text-xs font-medium text-ink-subtle">{hint}</span>
                    </label>
                  ))}
                </div>
                {form.status === 'OUT_OF_STOCK' && (
                  <p className="mt-2 text-xs font-medium text-ink-subtle">This product is marked out of stock. Saving keeps that.</p>
                )}
              </fieldset>

              {isEdit && (
                <div className="flex items-start justify-between gap-4 rounded-card border border-dashed border-line p-4">
                  <div className="text-sm">
                    <p className="font-black text-ink">Showcase options</p>
                    <p className="mt-0.5 text-xs font-medium text-ink-subtle">360° view, image hotspots, hover photo, search-result text, badges and store pickup. Most products never need these.</p>
                  </div>
                  <Button
                    variant="secondary"
                    size="sm"
                    disabled={dirty}
                    title={dirty ? 'Save your changes first' : undefined}
                    onClick={() => setShowAdvanced(true)}
                    leadingIcon={<Settings2 className="h-4 w-4" />}
                    className="shrink-0"
                  >
                    Open
                  </Button>
                </div>
              )}
            </div>
          )}
        </main>

        {/* How it looks to a shopper, beside the form on a wide screen. */}
        <aside className="hidden lg:block">
          <div className="sticky top-32 rounded-panel border border-line bg-surface p-4">
            <p className="mb-3 text-xs font-black uppercase tracking-wider text-ink-subtle">How shoppers see it</p>
            <div className="overflow-hidden rounded-card border border-line">
              {form.image ? (
                <img src={form.image} alt="" className="aspect-square w-full object-cover" />
              ) : (
                <div className="flex aspect-square w-full items-center justify-center bg-surface-sunken text-xs font-bold text-ink-subtle">Cover photo</div>
              )}
              <div className="space-y-1 p-3">
                {form.brand && <p className="text-2xs font-bold uppercase tracking-wide text-ink-subtle">{form.brand}</p>}
                <p className="line-clamp-2 text-sm font-bold text-ink">{form.title || 'Product name'}</p>
                <p className="text-sm font-black text-ink">
                  {parseFloat(form.price) > 0 ? `₹${parseFloat(form.price).toLocaleString('en-IN')}` : '₹ —'}
                  {discount > 0 && (
                    <>
                      <span className="ml-2 text-xs font-medium text-ink-subtle line-through">₹{parseFloat(form.mrp).toLocaleString('en-IN')}</span>
                      <span className="ml-2 text-xs font-bold text-success">{discount}% off</span>
                    </>
                  )}
                </p>
                {totalStock === 0 && <p className="text-xs font-bold text-danger">Sold out</p>}
              </div>
            </div>
          </div>
        </aside>
      </div>

      {/* Always-visible action bar. */}
      <div className="fixed inset-x-0 bottom-0 z-30 border-t border-line bg-surface">
        <div className="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3">
          <Button variant="ghost" size="md" disabled={stepIndex === 0} onClick={() => go(STEPS[stepIndex - 1].id)} leadingIcon={<ArrowLeft className="h-4 w-4" />}>
            Back
          </Button>
          <div className="flex-1" />
          {step !== 'review' && (
            <Button
              variant="secondary"
              size="md"
              loading={saving}
              onClick={() => save(isEdit ? form.status : 'DRAFT')}
            >
              {isEdit ? 'Save changes' : 'Save draft'}
            </Button>
          )}
          {step !== 'review' ? (
            <Button variant="primary" size="md" onClick={() => go(STEPS[stepIndex + 1].id)} trailingIcon={<ArrowRight className="h-4 w-4" />}>
              Next
            </Button>
          ) : (
            <Button variant="primary" size="md" loading={saving} onClick={() => save(form.status)}>
              {liveLabel}
            </Button>
          )}
        </div>
      </div>

      {showAdvanced && product && (
        <ProductFormModal
          isOpen
          onClose={() => setShowAdvanced(false)}
          product={product}
          categories={categories}
          token={token}
          onSaved={(data) => { load(mapProduct(data)); setShowAdvanced(false); }}
        />
      )}
    </div>
  );
}
