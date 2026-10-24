'use client';

import React, { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { ArrowLeft, Image as ImageIcon, RotateCcw, Save, Shapes, Type, Tag } from 'lucide-react';
import { apiFetch } from '../../../lib/apiClient';
import { tokens } from '@ds/tokens';
import { brand as shippedBrand } from '@ds/brand';
import { useAdminAuth } from '../../../components/admin/AdminAuthContext';

const RADIUS_FIELDS = [
  { key: 'radius-chip', label: 'Chip', hint: 'Tags and small badges' },
  { key: 'radius-control', label: 'Control', hint: 'Inputs and small buttons' },
  { key: 'radius-card', label: 'Card', hint: 'Product cards, list rows' },
  { key: 'radius-panel', label: 'Panel', hint: 'Modals and page sections' },
];

const BRAND_FIELDS = [
  { key: 'name', label: 'Brand name', hint: 'Used in titles, emails and the app' },
  { key: 'nameDisplay', label: 'Logo text', hint: 'The part before the accent letter' },
  { key: 'nameAccent', label: 'Accent letter', hint: 'Rendered in the accent colour' },
  { key: 'logoInitials', label: 'Logo initials', hint: 'Two characters for the logo mark' },
  { key: 'tagline', label: 'Tagline', hint: 'Sits under the logo' },
  { key: 'supportEmail', label: 'Support email', hint: 'Shown to customers' },
  { key: 'legalEntity', label: 'Legal entity', hint: 'Footer and invoices' },
];

/**
 * Design management: geometry and brand identity.
 *
 * Separate from colour because it changes at a different rate and carries
 * different risk. Colours get tuned seasonally; corner radii and the legal
 * entity name are set once and touched rarely — and getting the legal entity
 * wrong is an invoicing problem, not an aesthetic one.
 *
 * Radii are role-named rather than sized, same as the tokens: you set what a
 * *card* looks like, not what "16px" means.
 */
export default function DesignPage() {
  const { token } = useAdminAuth();

  const [geometry, setGeometry] = useState({});
  const [brandOverrides, setBrandOverrides] = useState({});
  const [loaded, setLoaded] = useState(false);
  const [logoUrl, setLogoUrl] = useState(null);
  const [logoBusy, setLogoBusy] = useState(false);
  const [saving, setSaving] = useState(false);
  const [status, setStatus] = useState(null);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      // apiFetch hands back the whole response; the theme is what is inside `data`.
      const body = await apiFetch('/admin/theme', { token });
      const data = body?.data ?? body;
      setGeometry(data?.overrides?.geometry || {});
      setBrandOverrides(data?.overrides?.brand || {});
      setLogoUrl(data?.logo_url || null);
      setLoaded(true);
    } catch (e) {
      setError(e.message);
      setLoaded(true);
    }
  }, [token]);

  useEffect(() => {
    if (token) load();
  }, [token, load]);

  const defaultRadius = (key) => parseFloat(tokens.radius[key.replace('radius-', '')]) || 0;
  const radiusValue = (key) =>
    Object.prototype.hasOwnProperty.call(geometry, key) ? geometry[key] : defaultRadius(key);

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      await apiFetch('/admin/theme', {
        method: 'PUT',
        token,
        body: { geometry, brand: brandOverrides },
      });
      setStatus('Saved. The storefront picks this up within a minute.');
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000/api/v1';

  // The logo is saved the moment it is chosen: it is a file, not a field, so
  // there is nothing to review before it goes live.
  const uploadLogo = async (file) => {
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) {
      setError('The logo must be 2 MB or smaller.');
      return;
    }
    setLogoBusy(true);
    setError(null);
    try {
      const form = new FormData();
      form.append('file', file);
      const res = await fetch(`${API_BASE}/admin/theme/logo`, {
        method: 'POST',
        headers: { Accept: 'application/json', Authorization: `Bearer ${token}` },
        body: form,
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(json.errors ? Object.values(json.errors).flat().join(' ') : json.message || 'The logo could not be uploaded.');
      }
      setLogoUrl(json.data?.logo_url || null);
      setStatus('Logo updated. The website and the app pick it up within a minute.');
    } catch (e) {
      setError(e.message);
    } finally {
      setLogoBusy(false);
    }
  };

  const removeLogo = async () => {
    if (!window.confirm('Remove the logo and go back to the initials mark?')) return;
    setLogoBusy(true);
    setError(null);
    try {
      await apiFetch('/admin/theme/logo', { method: 'DELETE', token });
      setLogoUrl(null);
      setStatus('Logo removed.');
    } catch (e) {
      setError(e.message);
    } finally {
      setLogoBusy(false);
    }
  };

  const reset = async (scope) => {
    if (!window.confirm(`Reset ${scope === 'brand' ? 'brand identity' : 'geometry'} to the shipped values?`)) {
      return;
    }
    setSaving(true);
    try {
      await apiFetch('/admin/theme/reset', { method: 'POST', token, body: { scope } });
      if (scope === 'brand') setBrandOverrides({});
      else setGeometry({});
      setStatus('Reset to the shipped values.');
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  if (!loaded) {
    return (
      <div className="min-h-screen bg-canvas p-8">
        <p className="text-ink-muted text-base">Loading design settings…</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-canvas">
      <header className="sticky top-0 z-header bg-surface border-b border-line">
        <div className="max-w-5xl mx-auto px-6 py-4 flex items-center gap-4">
          <Link href="/admin" className="text-ink-muted hover:text-ink" aria-label="Back to admin">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <div className="flex-1">
            <h1 className="text-xl font-black text-ink flex items-center gap-2">
              <Shapes className="w-5 h-5 text-accent" />
              Design management
            </h1>
            <p className="text-xs text-ink-muted">Geometry and brand identity</p>
          </div>
          <Link
            href="/admin/appearance"
            className="px-4 py-2 rounded-pill border border-line text-xs font-bold text-ink-muted hover:text-ink transition"
          >
            Colours →
          </Link>
          <button
            type="button"
            onClick={save}
            disabled={saving}
            className="flex items-center gap-1.5 px-5 py-2 rounded-pill bg-primary text-on-primary text-xs font-bold shadow-button hover:bg-primary-hover transition disabled:opacity-50"
          >
            <Save className="w-3.5 h-3.5" /> {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-6 py-8">
        {error && (
          <div className="mb-6 rounded-control bg-danger-soft border border-danger/20 px-4 py-3 text-base text-danger">
            {error}
          </div>
        )}
        {status && (
          <div className="mb-6 rounded-control bg-success-soft border border-success/20 px-4 py-3 text-base text-success">
            {status}
          </div>
        )}

        {/* ── Geometry ────────────────────────────────────────────────── */}
        <section className="mb-12">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-black text-ink">Corner radius</h2>
              <p className="text-base text-ink-muted">
                Named by role, so you set what a card looks like — not what a number means.
              </p>
            </div>
            <button
              type="button"
              onClick={() => reset('geometry')}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-pill border border-line text-2xs font-bold text-ink-muted hover:text-danger hover:border-danger transition"
            >
              <RotateCcw className="w-3 h-3" /> Reset
            </button>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            {RADIUS_FIELDS.map(({ key, label, hint }) => {
              const value = radiusValue(key);
              return (
                <div key={key} className="rounded-card border border-line bg-surface p-5">
                  <div className="flex items-center justify-between mb-1">
                    <label htmlFor={`radius-${key}`} className="text-base font-bold text-ink">
                      {label}
                    </label>
                    <span className="font-mono text-xs text-ink-muted">{value}px</span>
                  </div>
                  <p className="text-xs text-ink-subtle mb-4">{hint}</p>

                  <div className="flex items-center gap-4">
                    <div
                      className="w-14 h-14 shrink-0 bg-surface-sunken border border-line-strong"
                      style={{ borderRadius: `${value}px` }}
                      aria-hidden="true"
                    />
                    <input
                      id={`radius-${key}`}
                      type="range"
                      min="0"
                      max="48"
                      value={value}
                      onChange={(e) => {
                        setGeometry((p) => ({ ...p, [key]: Number(e.target.value) }));
                        setStatus(null);
                      }}
                      className="flex-1 accent-accent"
                    />
                  </div>

                  <p className="mt-3 text-2xs text-ink-subtle font-mono">
                    default {defaultRadius(key)}px
                  </p>
                </div>
              );
            })}
          </div>
        </section>

        {/* ── Typography (read-only) ──────────────────────────────────── */}
        <section className="mb-12">
          <h2 className="text-lg font-black text-ink mb-1 flex items-center gap-2">
            <Type className="w-4 h-4 text-accent" /> Typography
          </h2>
          <p className="text-base text-ink-muted mb-4">
            The type scale is fixed in the design system. Fonts are bundled into the
            mobile app and preloaded on the web, so swapping a family is a build
            change rather than a setting — editing it here would break the mobile
            app, which cannot download a new font at runtime.
          </p>
          <div className="rounded-card border border-line bg-surface p-5 space-y-2">
            {Object.entries(tokens.font).map(([role, stack]) => (
              <div key={role} className="flex items-baseline gap-4">
                <span className="font-mono text-xs text-ink-subtle w-20 shrink-0">{role}</span>
                <span className="text-md text-ink truncate" style={{ fontFamily: stack }}>
                  The quick brown fox jumps over the lazy dog
                </span>
              </div>
            ))}
          </div>
        </section>

        {/* ── Logo ────────────────────────────────────────────────────── */}
        <section className="mb-12" aria-labelledby="logo-heading">
          <h2 id="logo-heading" className="text-lg font-black text-ink flex items-center gap-2">
            <ImageIcon className="w-4 h-4 text-accent" /> Logo
          </h2>
          <p className="text-base text-ink-muted mb-4">
            Shown in the website header and footer and at the top of the app. A square image works best.
            Without one, the two-letter mark below is used.
          </p>
          <div className="rounded-card border border-line bg-surface p-6 flex flex-wrap items-center gap-6">
            <div className="w-24 h-24 rounded-card border border-line bg-surface-muted flex items-center justify-center overflow-hidden">
              {logoUrl ? (
                <img src={logoUrl} alt="Current logo" className="max-w-full max-h-full object-contain" />
              ) : (
                <span className="font-display font-black text-2xl text-ink-subtle">
                  {(brandOverrides.logoInitials ?? shippedBrand.logoInitials ?? 'BX').slice(0, 2)}
                </span>
              )}
            </div>
            <div className="space-y-2">
              <div className="flex flex-wrap gap-2">
                <label
                  htmlFor="logo-file"
                  className={`px-5 py-2 rounded-pill bg-primary text-on-primary text-xs font-bold shadow-button cursor-pointer hover:bg-primary-hover transition ${logoBusy ? 'opacity-50 pointer-events-none' : ''}`}
                >
                  {logoBusy ? 'Working…' : logoUrl ? 'Change logo' : 'Upload logo'}
                </label>
                <input
                  id="logo-file"
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  className="sr-only"
                  disabled={logoBusy}
                  onChange={(e) => {
                    uploadLogo(e.target.files?.[0]);
                    e.target.value = '';
                  }}
                />
                {logoUrl && (
                  <button
                    type="button"
                    onClick={removeLogo}
                    disabled={logoBusy}
                    className="px-4 py-2 rounded-pill border border-line text-xs font-bold text-ink-muted hover:text-danger hover:border-danger transition disabled:opacity-40"
                  >
                    Remove
                  </button>
                )}
              </div>
              <p className="text-2xs text-ink-subtle">PNG, JPG or WebP, at least 64 × 64 px, up to 2 MB. A transparent PNG looks best.</p>
            </div>
          </div>
        </section>

        {/* ── Brand identity ──────────────────────────────────────────── */}
        <section className="mb-12">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-black text-ink flex items-center gap-2">
                <Tag className="w-4 h-4 text-accent" /> Brand identity
              </h2>
              <p className="text-base text-ink-muted">
                Names and legal text. Leave a field blank to use the shipped value.
              </p>
            </div>
            <button
              type="button"
              onClick={() => reset('brand')}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-pill border border-line text-2xs font-bold text-ink-muted hover:text-danger hover:border-danger transition"
            >
              <RotateCcw className="w-3 h-3" /> Reset
            </button>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            {BRAND_FIELDS.map(({ key, label, hint }) => (
              <div key={key}>
                <label htmlFor={`brand-${key}`} className="block text-xs font-bold text-ink-muted mb-1.5">
                  {label}
                </label>
                <input
                  id={`brand-${key}`}
                  type="text"
                  value={brandOverrides[key] ?? ''}
                  placeholder={shippedBrand[key] ?? ''}
                  onChange={(e) => {
                    const v = e.target.value;
                    setBrandOverrides((p) => {
                      const next = { ...p };
                      if (v.trim() === '') delete next[key];
                      else next[key] = v;
                      return next;
                    });
                    setStatus(null);
                  }}
                  className="w-full bg-surface border border-line rounded-control px-3.5 py-2.5 text-base text-ink placeholder:text-ink-subtle focus:outline-none focus:border-accent"
                />
                <p className="mt-1 text-2xs text-ink-subtle">{hint}</p>
              </div>
            ))}
          </div>

          <div className="mt-6 rounded-card border border-line bg-surface p-6">
            <p className="text-2xs font-black uppercase tracking-wider text-ink-subtle mb-3">
              Logo preview
            </p>
            <div className="flex items-center gap-3">
              {logoUrl ? (
                <img src={logoUrl} alt="" className="w-11 h-11 object-contain" />
              ) : (
                <div className="w-11 h-11 rounded-control bg-inverse flex items-center justify-center">
                  <span className="font-display font-black text-sm text-ink-inverse">
                    {(brandOverrides.logoInitials ?? shippedBrand.logoInitials ?? 'BX').slice(0, 2)}
                  </span>
                </div>
              )}
              <div>
                <p className="font-display font-black text-xl text-ink leading-none">
                  {brandOverrides.nameDisplay ?? shippedBrand.nameDisplay}
                  <span className="text-accent">
                    {brandOverrides.nameAccent ?? shippedBrand.nameAccent}
                  </span>
                </p>
                <p className="text-2xs font-black tracking-widest text-ink-subtle uppercase mt-0.5">
                  {brandOverrides.tagline ?? shippedBrand.tagline}
                </p>
              </div>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
