'use client';

import React from 'react';
import { ArrowDown, ArrowUp, Plus, Trash2, X } from 'lucide-react';
import { BLANK_GROUP, OPTION_PRESETS } from '../../lib/productOptions';

const TYPES = [
  { value: 'single', label: 'Pick one (chips)' },
  { value: 'multi', label: 'Pick several (checklist)' },
  { value: 'swatch', label: 'Colour swatches' },
  { value: 'stepper', label: 'Number (weight, quantity)' },
];

const inputCls =
  'w-full bg-surface-muted border border-line rounded-control px-3 py-2 text-xs font-medium focus:outline-none focus:border-line-strong';

function Field({ label, hint, children, className = '' }) {
  return (
    <label className={`block ${className}`}>
      <span className="block text-[11px] font-semibold text-ink-muted mb-1">{label}</span>
      {children}
      {hint && <span className="block text-[11px] text-ink-subtle mt-1">{hint}</span>}
    </label>
  );
}

/**
 * Builds a list of custom option groups: portion, add-ons, "leave out", colour
 * swatches, a weight in kg.
 *
 * Used twice - on a category (the template every product in it starts from) and
 * on a product (its own list). The only difference is `allowStock`: a choice can
 * track its own stock ("only 3 portions of the special left") on a product, but
 * not on a template that many products share.
 */
export default function OptionGroupsEditor({ groups, onChange, allowStock = false, showPresets = true }) {
  // Spelled out in full so Tailwind can see the class names.
  const cols = allowStock
    ? 'sm:grid-cols-[1fr_90px_60px_60px_70px_28px]'
    : 'sm:grid-cols-[1fr_90px_60px_60px_28px]';
  const update = (gi, patch) => onChange(groups.map((g, i) => (i === gi ? { ...g, ...patch } : g)));
  const updateChoice = (gi, ci, patch) =>
    update(gi, { choices: groups[gi].choices.map((c, i) => (i === ci ? { ...c, ...patch } : c)) });
  const move = (gi, dir) => {
    const to = gi + dir;
    if (to < 0 || to >= groups.length) return;
    const next = [...groups];
    [next[gi], next[to]] = [next[to], next[gi]];
    onChange(next);
  };

  const setType = (gi, type) => {
    const g = groups[gi];
    const patch = { type };
    if (type === 'stepper') {
      patch.price_mode = 'multiply';
      patch.stepper = g.stepper || { min: 1, max: 10, step: 1, unit: '', default: 1, price: 0 };
    } else {
      if (g.price_mode === 'multiply') patch.price_mode = 'add';
      if (!g.choices?.length) patch.choices = [{ label: '', price: 0 }];
    }
    if (type !== 'multi') { patch.remove = false; patch.min = 0; patch.max = 1; }
    update(gi, patch);
  };

  const setStepper = (gi, key, value) => update(gi, { stepper: { ...groups[gi].stepper, [key]: value } });

  const setPriceMode = (gi, mode) => {
    // Only one group may set the price; turning this one on turns the others off.
    if (mode === 'set') {
      onChange(groups.map((g, i) => (i === gi ? { ...g, price_mode: 'set' } : g.price_mode === 'set' ? { ...g, price_mode: 'add' } : g)));
    } else {
      update(gi, { price_mode: mode });
    }
  };

  const setDefault = (gi, ci) => {
    const g = groups[gi];
    update(gi, {
      choices: g.choices.map((c, i) => ({
        ...c,
        default: g.type === 'multi' ? (i === ci ? !c.default : c.default) : i === ci ? !c.default : false,
      })),
    });
  };

  return (
    <div className="space-y-4 text-xs">
      {showPresets && (
        <div className="border border-line rounded-card p-4 bg-surface-muted">
          <p className="font-semibold text-ink mb-1">Start from a template</p>
          <p className="text-ink-muted mb-3">
            Fills in a sensible set of options for a kind of store. Everything stays editable, and it replaces what is below.
          </p>
          <div className="flex flex-wrap gap-2">
            {OPTION_PRESETS.map((p) => (
              <button
                key={p.id}
                type="button"
                title={p.description}
                onClick={() => {
                  if (groups.length && !window.confirm(`Replace the current options with the "${p.name}" template?`)) return;
                  onChange(p.groups());
                }}
                className="px-3 py-1.5 rounded-control border border-line bg-surface font-semibold text-ink hover:border-accent hover:text-accent transition"
              >
                {p.name}
              </button>
            ))}
          </div>
          <p className="text-[11px] text-ink-subtle mt-3">
            Colours and sizes come from each product&apos;s variants (set a colour and an optional swatch colour on a variant).
            Use options for everything else: portions, add-ons, gift wrap, weights.
          </p>
        </div>
      )}

      {groups.map((g, gi) => {
        const isStepper = g.type === 'stepper';
        return (
          <div key={gi} className="border border-line rounded-card overflow-hidden">
            <div className="flex items-center gap-2 px-4 py-3 bg-surface-muted border-b border-line">
              <input
                value={g.label}
                onChange={(e) => update(gi, { label: e.target.value })}
                placeholder="Group name (e.g. Portion, Add-ons, Weight)"
                aria-label="Option group name"
                className="flex-1 bg-transparent font-semibold text-sm text-ink placeholder:text-ink-subtle focus:outline-none"
              />
              <select
                value={g.type}
                onChange={(e) => setType(gi, e.target.value)}
                aria-label="Option group type"
                className="bg-surface border border-line rounded-control px-2 py-1 text-[11px] font-semibold focus:outline-none"
              >
                {TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
              </select>
              <button type="button" onClick={() => move(gi, -1)} disabled={gi === 0} aria-label="Move up" className="p-1 text-ink-muted disabled:opacity-30"><ArrowUp className="w-4 h-4" /></button>
              <button type="button" onClick={() => move(gi, 1)} disabled={gi === groups.length - 1} aria-label="Move down" className="p-1 text-ink-muted disabled:opacity-30"><ArrowDown className="w-4 h-4" /></button>
              <button type="button" onClick={() => onChange(groups.filter((_, i) => i !== gi))} aria-label="Delete group" className="p-1 text-danger"><Trash2 className="w-4 h-4" /></button>
            </div>

            <div className="p-4 space-y-4">
              <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
                <label className="inline-flex items-center gap-2 font-medium text-ink">
                  <input type="checkbox" checked={Boolean(g.required)} onChange={(e) => update(gi, { required: e.target.checked })} className="w-4 h-4 accent-primary" />
                  Shopper must choose
                </label>
                {g.type === 'multi' && (
                  <label className="inline-flex items-center gap-2 font-medium text-ink">
                    <input type="checkbox" checked={Boolean(g.remove)} onChange={(e) => update(gi, { remove: e.target.checked })} className="w-4 h-4 accent-primary" />
                    These are things to leave out (free)
                  </label>
                )}
              </div>

              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                {!g.remove && (
                  <Field label="How it changes the price" className="col-span-2">
                    <select value={g.price_mode || 'add'} onChange={(e) => setPriceMode(gi, e.target.value)} className={inputCls}>
                      {isStepper ? (
                        <>
                          <option value="multiply">Price is per unit (multiplied by the amount)</option>
                          <option value="add">Adds a fixed price per step</option>
                        </>
                      ) : (
                        <>
                          <option value="add">Adds to the price (+ ₹)</option>
                          <option value="set">Sets the price (Half ₹180 / Full ₹320)</option>
                        </>
                      )}
                    </select>
                  </Field>
                )}
                {g.type === 'multi' && (
                  <>
                    <Field label="At least"><input type="number" min="0" value={g.min ?? 0} onChange={(e) => update(gi, { min: Number(e.target.value) })} className={inputCls} /></Field>
                    <Field label="At most"><input type="number" min="1" value={g.max ?? g.choices.length} onChange={(e) => update(gi, { max: Number(e.target.value) })} className={inputCls} /></Field>
                  </>
                )}
              </div>

              <Field label="Help text (optional)">
                <input value={g.help || ''} onChange={(e) => update(gi, { help: e.target.value })} placeholder="Shown under the group name" className={inputCls} />
              </Field>

              {isStepper ? (
                <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
                  {[['min', 'Smallest'], ['max', 'Largest'], ['step', 'Step'], ['default', 'Starts at']].map(([key, label]) => (
                    <Field key={key} label={label}>
                      <input type="number" step="any" value={g.stepper?.[key] ?? ''} onChange={(e) => setStepper(gi, key, Number(e.target.value))} className={inputCls} />
                    </Field>
                  ))}
                  <Field label="Unit"><input value={g.stepper?.unit || ''} onChange={(e) => setStepper(gi, 'unit', e.target.value)} placeholder="kg, pcs" className={inputCls} /></Field>
                  {g.price_mode === 'add' && (
                    <Field label="₹ per step"><input type="number" min="0" step="any" value={g.stepper?.price ?? 0} onChange={(e) => setStepper(gi, 'price', Number(e.target.value))} className={inputCls} /></Field>
                  )}
                  {g.price_mode !== 'add' && (
                    <p className="col-span-2 sm:col-span-5 text-[11px] text-ink-subtle">
                      Enter the product&apos;s price <strong>per {g.stepper?.unit || 'unit'}</strong>; the shopper&apos;s total is that price × the amount they pick.
                    </p>
                  )}
                </div>
              ) : (
                <div className="space-y-2">
                  <div className={`hidden sm:grid gap-2 px-1 text-[11px] font-semibold text-ink-subtle ${cols}`}>
                    <span>Choice</span>
                    <span>{g.price_mode === 'set' ? 'Price (₹)' : g.remove ? '—' : 'Extra (₹)'}</span>
                    <span>Default</span>
                    <span>Offered</span>
                    {allowStock && <span>Stock</span>}
                    <span />
                  </div>
                  {g.choices.map((c, ci) => (
                    <div key={ci} className={`grid items-center gap-2 grid-cols-2 ${cols}`}>
                      <div className="flex items-center gap-2 col-span-2 sm:col-span-1">
                        {g.type === 'swatch' && (
                          <input
                            type="color"
                            value={c.color || '#cccccc'}
                            onChange={(e) => updateChoice(gi, ci, { color: e.target.value.toUpperCase() })}
                            aria-label="Swatch colour"
                            className="w-8 h-8 p-0 border border-line rounded-pill bg-transparent cursor-pointer shrink-0"
                          />
                        )}
                        <input value={c.label} onChange={(e) => updateChoice(gi, ci, { label: e.target.value })} placeholder={g.type === 'swatch' ? 'Colour name' : 'Choice (e.g. Full plate)'} aria-label="Choice name" className={inputCls} />
                      </div>
                      <input
                        type="number" min="0" step="any"
                        value={g.remove ? 0 : c.price ?? 0}
                        disabled={g.remove}
                        onChange={(e) => updateChoice(gi, ci, { price: Number(e.target.value) })}
                        aria-label="Price"
                        className={`${inputCls} disabled:opacity-40`}
                      />
                      <label className="flex items-center justify-center"><input type="checkbox" checked={Boolean(c.default)} onChange={() => setDefault(gi, ci)} aria-label="Selected by default" className="w-4 h-4 accent-primary" /></label>
                      <label className="flex items-center justify-center"><input type="checkbox" checked={c.available !== false} onChange={(e) => updateChoice(gi, ci, { available: e.target.checked })} aria-label="Offered today" className="w-4 h-4 accent-primary" /></label>
                      {allowStock && (
                        <input type="number" min="0" value={c.stock ?? ''} placeholder="∞" onChange={(e) => updateChoice(gi, ci, { stock: e.target.value === '' ? null : Number(e.target.value) })} aria-label="Stock (blank = not counted)" className={inputCls} />
                      )}
                      <button type="button" onClick={() => update(gi, { choices: g.choices.filter((_, i) => i !== ci) })} disabled={g.choices.length <= 1} aria-label="Remove choice" className="text-danger disabled:opacity-30 justify-self-end"><X className="w-4 h-4" /></button>
                    </div>
                  ))}
                  <button type="button" onClick={() => update(gi, { choices: [...g.choices, { label: '', price: 0 }] })} className="inline-flex items-center gap-1.5 text-accent font-semibold hover:underline">
                    <Plus className="w-3.5 h-3.5" /> Add choice
                  </button>
                </div>
              )}
            </div>
          </div>
        );
      })}

      <button
        type="button"
        onClick={() => onChange([...groups, BLANK_GROUP()])}
        className="w-full flex items-center justify-center gap-2 py-3 border-2 border-dashed border-line rounded-card text-ink-muted font-semibold hover:border-accent hover:text-accent transition"
      >
        <Plus className="w-4 h-4" /> Add option group
      </button>

      {groups.length === 0 && (
        <p className="text-center py-3 text-ink-subtle">
          No custom options. Shoppers just pick a variant (if any) and add to cart.
        </p>
      )}
    </div>
  );
}
