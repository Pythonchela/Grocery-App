'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { ArrowLeft, RotateCcw, Save, Palette, Moon, Sun, AlertTriangle } from 'lucide-react';
import { apiFetch } from '../../../lib/apiClient';
import { tokens } from '@ds/tokens';
import { useAdminAuth } from '../../../components/admin/AdminAuthContext';

/**
 * Colour management.
 *
 * Edits the design tokens rather than individual screens. Changing `accent`
 * here moves every `bg-accent`, `text-accent` and `ring-accent` in the web app
 * and the same token in the Flutter app — because they all resolve through the
 * one variable. That is the payoff of the token layer: an admin gets to
 * re-colour the product without a designer or a deploy, and nothing can drift
 * out of sync because there is only one place a colour lives.
 *
 * Only tokens that are actually edited are saved. Anything untouched keeps
 * following the shipped default, so a future palette change still reaches it.
 */
/**
 * One-click brand palettes. Each sets only the four accent tokens (the colour of
 * links, highlights, badges and active states) for both themes; surfaces, text
 * and status colours are left alone so contrast stays sound. "Blue" is the
 * shipped default, so choosing it simply clears the accent overrides.
 */
const PRESETS = [
  { id: 'blue', label: 'Blue (default)', swatch: '#1A56FF', light: null, dark: null },
  {
    id: 'orange', label: 'Orange', swatch: '#F97316',
    light: { accent: '#EA580C', 'accent-hover': '#C2410C', 'accent-soft': '#FFF1E6', 'on-accent': '#FFFFFF' },
    dark: { accent: '#FB923C', 'accent-hover': '#F97316', 'accent-soft': '#2A1A0E', 'on-accent': '#1A0E04' },
  },
  {
    id: 'emerald', label: 'Emerald', swatch: '#059669',
    light: { accent: '#059669', 'accent-hover': '#047857', 'accent-soft': '#E6F7F1', 'on-accent': '#FFFFFF' },
    dark: { accent: '#34D399', 'accent-hover': '#10B981', 'accent-soft': '#0E2A22', 'on-accent': '#04140F' },
  },
  {
    id: 'violet', label: 'Violet', swatch: '#7C3AED',
    light: { accent: '#7C3AED', 'accent-hover': '#6D28D9', 'accent-soft': '#F1EBFE', 'on-accent': '#FFFFFF' },
    dark: { accent: '#A78BFA', 'accent-hover': '#8B5CF6', 'accent-soft': '#1E1633', 'on-accent': '#0F0A1F' },
  },
  {
    id: 'rose', label: 'Rose', swatch: '#E11D48',
    light: { accent: '#E11D48', 'accent-hover': '#BE123C', 'accent-soft': '#FEE9ED', 'on-accent': '#FFFFFF' },
    dark: { accent: '#FB7185', 'accent-hover': '#F43F5E', 'accent-soft': '#2D1118', 'on-accent': '#1F060B' },
  },
  {
    id: 'teal', label: 'Teal', swatch: '#0D9488',
    light: { accent: '#0D9488', 'accent-hover': '#0F766E', 'accent-soft': '#E4F6F4', 'on-accent': '#FFFFFF' },
    dark: { accent: '#2DD4BF', 'accent-hover': '#14B8A6', 'accent-soft': '#0C2926', 'on-accent': '#03140F' },
  },
];

const ACCENT_TOKENS = ['accent', 'accent-hover', 'accent-soft', 'on-accent'];

export default function AppearancePage() {
  const { token } = useAdminAuth();

  const [schema, setSchema] = useState(null);
  const [light, setLight] = useState({});
  const [dark, setDark] = useState({});
  const [mode, setMode] = useState('light');
  const [saving, setSaving] = useState(false);
  const [status, setStatus] = useState(null);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      // apiFetch hands back the whole response; the theme is what is inside `data`.
      const body = await apiFetch('/admin/theme', { token });
      const data = body?.data ?? body;
      setSchema(data);
      setLight(data.overrides?.colors || {});
      setDark(data.overrides?.colors_dark || {});
    } catch (e) {
      setError(e.message);
    }
  }, [token]);

  useEffect(() => {
    if (token) load();
  }, [token, load]);

  const current = mode === 'light' ? light : dark;
  const setCurrent = mode === 'light' ? setLight : setDark;

  // The shipped default for a token, shown as the reset target and used as the
  // starting value when a colour has never been overridden.
  const defaultFor = useCallback(
    (name) => (mode === 'light' ? tokens.color[name] : tokens.colorDark[name]) || '#000000',
    [mode],
  );

  const dirtyCount = useMemo(
    () => Object.keys(light).length + Object.keys(dark).length,
    [light, dark],
  );

  const applyPreset = (preset) => {
    const apply = (prev, values) => {
      const next = { ...prev };
      ACCENT_TOKENS.forEach((t) => delete next[t]);
      return values ? { ...next, ...values } : next;
    };
    setLight((prev) => apply(prev, preset.light));
    setDark((prev) => apply(prev, preset.dark));
    setStatus(`${preset.label} palette applied - press Save to publish it.`);
  };

  const setColor = (name, value) => {
    setCurrent((prev) => ({ ...prev, [name]: value.toUpperCase() }));
    setStatus(null);
  };

  const clearColor = (name) => {
    setCurrent((prev) => {
      const next = { ...prev };
      delete next[name];
      return next;
    });
    setStatus(null);
  };

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      await apiFetch('/admin/theme', {
        method: 'PUT',
        token,
        body: { colors: light, colors_dark: dark },
      });
      setStatus('Saved. The storefront picks this up within a minute.');
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const resetAll = async () => {
    if (!window.confirm('Reset every colour back to the shipped palette?')) return;
    setSaving(true);
    try {
      await apiFetch('/admin/theme/reset', { method: 'POST', token, body: { scope: 'colors' } });
      setLight({});
      setDark({});
      setStatus('Reset to the shipped palette.');
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  if (!schema) {
    return (
      <div className="min-h-screen bg-canvas p-8">
        <p className="text-ink-muted text-base">Loading the palette…</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-canvas">
      <header className="sticky top-0 z-header bg-surface border-b border-line">
        <div className="max-w-6xl mx-auto px-6 py-4 flex items-center gap-4">
          <Link href="/admin" className="text-ink-muted hover:text-ink" aria-label="Back to admin">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <div className="flex-1">
            <h1 className="text-xl font-black text-ink flex items-center gap-2">
              <Palette className="w-5 h-5 text-accent" />
              Colour management
            </h1>
            <p className="text-xs text-ink-muted">
              {dirtyCount === 0
                ? 'Every colour is following the shipped palette.'
                : `${dirtyCount} colour${dirtyCount === 1 ? '' : 's'} overridden.`}
            </p>
          </div>

          <div className="flex items-center gap-1 rounded-pill border border-line p-1">
            {[
              { id: 'light', label: 'Light', Icon: Sun },
              { id: 'dark', label: 'Dark', Icon: Moon },
            ].map(({ id, label, Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => setMode(id)}
                aria-pressed={mode === id}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-pill text-xs font-bold transition ${
                  mode === id ? 'bg-primary text-on-primary' : 'text-ink-muted hover:text-ink'
                }`}
              >
                <Icon className="w-3.5 h-3.5" />
                {label}
              </button>
            ))}
          </div>

          <button
            type="button"
            onClick={resetAll}
            disabled={saving || dirtyCount === 0}
            className="flex items-center gap-1.5 px-4 py-2 rounded-pill border border-line text-xs font-bold text-ink-muted hover:text-danger hover:border-danger transition disabled:opacity-40"
          >
            <RotateCcw className="w-3.5 h-3.5" /> Reset
          </button>
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

      <main className="max-w-6xl mx-auto px-6 py-8">
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

        <div className="mb-8 rounded-card bg-warning-soft border border-warning/25 px-4 py-3 flex items-start gap-3">
          <AlertTriangle className="w-4 h-4 text-warning mt-0.5 shrink-0" />
          <p className="text-base text-warning leading-relaxed">
            These are design tokens, not page styles. Changing one here changes it
            everywhere that token is used — across the storefront, the admin panel
            and the mobile app. Check contrast before saving: a pale{' '}
            <code className="font-mono text-sm">ink</code> on a pale{' '}
            <code className="font-mono text-sm">surface</code> is unreadable in both themes.
          </p>
        </div>

        <section className="mb-10" aria-labelledby="presets-heading">
          <h2 id="presets-heading" className="text-sm font-bold text-ink mb-1">Quick palettes</h2>
          <p className="text-xs text-ink-muted mb-3">
            Pick a brand colour in one click; fine-tune any shade below afterwards.
          </p>
          <div className="flex flex-wrap gap-2">
            {PRESETS.map((preset) => (
              <button
                key={preset.id}
                type="button"
                onClick={() => applyPreset(preset)}
                className="flex items-center gap-2 px-3 py-2 rounded-control border border-line bg-surface hover:border-line-strong text-xs font-semibold text-ink transition"
              >
                <span className="w-4 h-4 rounded-pill border border-line" style={{ backgroundColor: preset.swatch }} />
                {preset.label}
              </button>
            ))}
          </div>
        </section>

        {Object.entries(schema.color_groups || {}).map(([group, names]) => (
          <section key={group} className="mb-10">
            <h2 className="text-md font-black text-ink mb-1">{group}</h2>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {names.map((name) => {
                const overridden = Object.prototype.hasOwnProperty.call(current, name);
                const value = overridden ? current[name] : defaultFor(name);

                return (
                  <div
                    key={name}
                    className={`rounded-card border p-4 bg-surface transition ${
                      overridden ? 'border-accent' : 'border-line'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <label className="relative shrink-0" htmlFor={`color-${mode}-${name}`}>
                        {/* The swatch is the visible affordance; the name still
                            has to reach the accessibility tree. */}
                        <span className="sr-only">{`${name} colour, ${mode} theme`}</span>
                        <span
                          aria-hidden="true"
                          className="block w-11 h-11 rounded-control border border-line"
                          style={{ backgroundColor: value }}
                        />
                        <input
                          id={`color-${mode}-${name}`}
                          type="color"
                          value={value}
                          onChange={(e) => setColor(name, e.target.value)}
                          className="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
                        />
                      </label>

                      <div className="min-w-0 flex-1">
                        <p className="font-mono text-xs font-bold text-ink truncate">{name}</p>
                        <input
                          type="text"
                          value={value}
                          onChange={(e) => {
                            const v = e.target.value;
                            if (/^#[0-9a-fA-F]{0,6}$/.test(v)) setColor(name, v);
                          }}
                          aria-label={`${name} hex value`}
                          className="mt-1 w-full font-mono text-xs bg-surface-muted border border-line rounded-chip px-2 py-1 text-ink-muted focus:outline-none focus:border-accent"
                        />
                      </div>
                    </div>

                    <div className="mt-3 flex items-center justify-between">
                      <span className="text-2xs text-ink-subtle font-mono">
                        default {defaultFor(name)}
                      </span>
                      {overridden && (
                        <button
                          type="button"
                          onClick={() => clearColor(name)}
                          className="text-2xs font-bold text-ink-muted hover:text-danger"
                        >
                          Revert
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </section>
        ))}

        <section className="mb-10">
          <h2 className="text-md font-black text-ink mb-3">Preview</h2>
          <div
            className="rounded-panel border border-line p-6"
            style={{
              backgroundColor: light.canvas || tokens.color.canvas,
              color: light.ink || tokens.color.ink,
            }}
          >
            <div
              className="rounded-card p-5 border"
              style={{
                backgroundColor: light.surface || tokens.color.surface,
                borderColor: light.line || tokens.color.line,
              }}
            >
              <p className="font-black text-lg mb-1">Sample card</p>
              <p className="text-base mb-4" style={{ color: light['ink-muted'] || tokens.color['ink-muted'] }}>
                This is how body copy sits on a surface with your palette.
              </p>
              <div className="flex flex-wrap gap-3">
                <span
                  className="px-5 py-2.5 rounded-pill text-sm font-bold"
                  style={{
                    backgroundColor: light.primary || tokens.color.primary,
                    color: light['on-primary'] || tokens.color['on-primary'],
                  }}
                >
                  Primary action
                </span>
                <span
                  className="px-5 py-2.5 rounded-pill text-sm font-bold"
                  style={{
                    backgroundColor: light.accent || tokens.color.accent,
                    color: light['on-accent'] || tokens.color['on-accent'],
                  }}
                >
                  Accent action
                </span>
                <span
                  className="px-4 py-2 rounded-pill text-xs font-bold"
                  style={{
                    backgroundColor: light['success-soft'] || tokens.color['success-soft'],
                    color: light.success || tokens.color.success,
                  }}
                >
                  In stock
                </span>
                <span
                  className="px-4 py-2 rounded-pill text-xs font-bold"
                  style={{
                    backgroundColor: light['danger-soft'] || tokens.color['danger-soft'],
                    color: light.danger || tokens.color.danger,
                  }}
                >
                  Out of stock
                </span>
              </div>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
