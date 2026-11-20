'use client';

import React from 'react';
import { Check, Minus, Plus } from 'lucide-react';
import {
  formatStepperValue,
  isSelectable,
  isStepper,
  isVariantGrid,
  pickedIds,
  variantSwatch,
} from '../../lib/productOptions';
import { colourPhoto } from '../../lib/productPage';

const money = (n) => `₹${Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`;

function priceHint(group, choice) {
  if (!(choice.price > 0)) return '';
  return group.price_mode === 'set' ? money(choice.price) : `+${money(choice.price)}`;
}

function hintFor(group) {
  if (isStepper(group)) return group.required ? 'Required' : 'Optional';
  if (group.type === 'multi') {
    if (group.min > 0 && group.max > group.min) return `Choose ${group.min}-${group.max}`;
    if (group.min > 0) return `Choose ${group.min}`;
    return group.max < (group.choices || []).length ? `Up to ${group.max}` : 'Optional';
  }
  return group.required ? 'Required' : 'Optional';
}

/** A colour dot, or a small rounded photo when the colour has pictures of its own. */
function Swatch({ colour, label, image, selected, disabled, onClick, square = false }) {
  const shape = square ? 'rounded-card' : 'rounded-pill';
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      aria-pressed={selected}
      title={label}
      className={`relative p-[3px] border-2 transition disabled:opacity-35 disabled:cursor-not-allowed ${shape} ${
        square ? 'w-14 h-16' : 'w-10 h-10'
      } ${selected ? 'border-accent' : 'border-line hover:border-line-strong'}`}
    >
      <span
        className={`block w-full h-full overflow-hidden border border-line/60 bg-surface-sunken ${shape}`}
        style={colour && !image ? { backgroundColor: colour } : undefined}
      >
        {image && <img src={image} alt="" className="w-full h-full object-cover" />}
        {!colour && !image && (
          <span className="flex w-full h-full items-center justify-center text-[11px] font-semibold text-ink-muted">
            {label?.[0]}
          </span>
        )}
      </span>
    </button>
  );
}

function Chip({ selected, disabled, onClick, children, hint }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={selected}
      className={`min-h-[40px] px-3.5 py-1.5 rounded-control border text-sm font-medium text-center transition disabled:opacity-40 disabled:cursor-not-allowed ${
        selected
          ? 'bg-primary text-on-primary border-primary'
          : 'bg-surface text-ink border-line hover:border-line-strong'
      } ${disabled ? 'line-through' : ''}`}
    >
      <span className="block leading-tight">{children}</span>
      {hint && <span className={`block text-[11px] ${selected ? 'opacity-80' : 'text-ink-subtle'}`}>{hint}</span>}
    </button>
  );
}

function Group({ group, selection, onChange }) {
  const chosen = pickedIds(selection, group.key);

  const set = (ids) => {
    const next = { ...selection };
    if (ids.length) next[group.key] = ids;
    else delete next[group.key];
    onChange(next);
  };

  const pick = (choice) => {
    if (group.type === 'multi') {
      if (chosen.includes(choice.id)) return set(chosen.filter((id) => id !== choice.id));
      if (chosen.length >= group.max) return group.max === 1 ? set([choice.id]) : undefined;
      return set([...chosen, choice.id]);
    }
    if (chosen.includes(choice.id)) return group.required ? undefined : set([]);
    return set([choice.id]);
  };

  const chosenLabel = (group.choices || []).filter((c) => chosen.includes(c.id)).map((c) => c.label).join(', ');

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <h3 className="text-sm font-semibold text-ink">
          {group.label}
          {group.type === 'swatch' && chosenLabel && (
            <span className="ml-2 font-normal text-ink-muted">{chosenLabel}</span>
          )}
        </h3>
        <span className="text-xs text-ink-subtle shrink-0">{hintFor(group)}</span>
      </div>
      {group.help && <p className="text-xs text-ink-muted mt-0.5">{group.help}</p>}

      <div className="mt-2">
        {isStepper(group) ? (
          <Stepper group={group} selection={selection} onChange={onChange} />
        ) : group.type === 'swatch' ? (
          <div className="flex flex-wrap gap-3">
            {group.choices.map((c) => (
              <Swatch
                key={c.id}
                colour={c.color}
                image={c.image}
                label={c.label}
                selected={chosen.includes(c.id)}
                disabled={!isSelectable(c)}
                onClick={() => pick(c)}
              />
            ))}
          </div>
        ) : group.type === 'multi' ? (
          <ul className="divide-y divide-line border border-line rounded-card overflow-hidden">
            {group.choices.map((c) => {
              const on = chosen.includes(c.id);
              const ok = isSelectable(c);
              return (
                <li key={c.id}>
                  <button
                    type="button"
                    onClick={() => pick(c)}
                    disabled={!ok}
                    aria-pressed={on}
                    className="w-full flex items-center gap-3 px-3 py-2.5 text-left hover:bg-surface-sunken disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    <span
                      className={`w-5 h-5 rounded-chip border flex items-center justify-center shrink-0 ${
                        on ? 'bg-primary border-primary text-on-primary' : 'border-line-strong bg-surface'
                      }`}
                    >
                      {on && <Check className="w-3.5 h-3.5" />}
                    </span>
                    <span className={`flex-1 text-sm text-ink ${ok ? '' : 'line-through'}`}>
                      {group.remove ? `No ${c.label}` : c.label}
                    </span>
                    {priceHint(group, c) && (
                      <span className="text-sm font-medium text-ink-muted">{priceHint(group, c)}</span>
                    )}
                  </button>
                </li>
              );
            })}
          </ul>
        ) : (
          <div className="flex flex-wrap gap-2">
            {group.choices.map((c) => (
              <Chip
                key={c.id}
                selected={chosen.includes(c.id)}
                disabled={!isSelectable(c)}
                hint={priceHint(group, c)}
                onClick={() => pick(c)}
              >
                {c.label}
              </Chip>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Stepper({ group, selection, onChange }) {
  const s = group.stepper;
  const value = selection[group.key];

  const set = (v) => {
    const next = { ...selection };
    if (v === null) delete next[group.key];
    else next[group.key] = Math.round(v * 1000) / 1000;
    onChange(next);
  };

  if (value === undefined || value === null) {
    return (
      <button
        type="button"
        onClick={() => set(s.default ?? s.min)}
        className="px-4 py-2 rounded-control border border-line text-sm font-medium text-ink hover:border-line-strong"
      >
        Choose {group.label.toLowerCase()}
      </button>
    );
  }

  const canLess = value - s.step >= s.min - 1e-9;
  const canMore = value + s.step <= s.max + 1e-9;

  return (
    <div className="inline-flex items-center gap-2">
      <button
        type="button"
        aria-label={`Less ${group.label.toLowerCase()}`}
        disabled={!canLess && group.required}
        onClick={() => (canLess ? set(value - s.step) : set(null))}
        className="w-10 h-10 rounded-control border border-line flex items-center justify-center hover:border-line-strong disabled:opacity-40"
      >
        <Minus className="w-4 h-4" />
      </button>
      <span className="min-w-[88px] text-center text-base font-semibold text-ink">
        {formatStepperValue(group, value)}
      </span>
      <button
        type="button"
        aria-label={`More ${group.label.toLowerCase()}`}
        disabled={!canMore}
        onClick={() => set(value + s.step)}
        className="w-10 h-10 rounded-control border border-line flex items-center justify-center hover:border-line-strong disabled:opacity-40"
      >
        <Plus className="w-4 h-4" />
      </button>
    </div>
  );
}

/** The product page's custom options: one block per group the store configured. */
export function OptionPicker({ groups = [], selection, onChange }) {
  if (!groups.length) return null;
  return (
    <div className="space-y-5 pt-4">
      {groups.map((g) => (
        <Group key={g.key} group={g} selection={selection} onChange={onChange} />
      ))}
    </div>
  );
}

/**
 * Variants as colour swatches and size chips - the way clothing is shopped -
 * when they form a colour x size grid; otherwise a single list of labels.
 */
export function VariantPicker({ variants = [], selected, onChange, sizeLabel = 'Size', colourLabel = 'Colour' }) {
  if (variants.length < 2) return null;

  if (!isVariantGrid(variants)) {
    return (
      <div className="space-y-2">
        <h3 className="text-sm font-semibold text-ink">Select variant</h3>
        <div className="flex flex-wrap gap-2">
          {variants.map((v) => (
            <Chip
              key={v.id}
              selected={selected?.id === v.id}
              disabled={v.stock <= 0}
              onClick={() => onChange(v)}
            >
              {[v.color, v.size].filter(Boolean).join(' · ') || 'Default'}
            </Chip>
          ))}
        </div>
      </div>
    );
  }

  const colours = [...new Set(variants.map((v) => v.color))];
  const sizes = [...new Set(variants.map((v) => v.size))];
  const colour = selected?.color ?? colours[0];
  const size = selected?.size ?? sizes[0];
  const find = (c, s) => variants.find((v) => v.color === c && v.size === s);

  return (
    <div className="space-y-5">
      {colours.length > 1 && (
        <div className="space-y-2">
          <h3 className="text-sm font-semibold text-ink">
            {colourLabel} <span className="ml-2 font-normal text-ink-muted">{colour}</span>
          </h3>
          <div className="flex flex-wrap gap-3">
            {colours.map((c) => {
              const inStock = variants.some((v) => v.color === c && v.stock > 0);
              const photo = colourPhoto(variants, c);
              return (
                <Swatch
                  key={c}
                  label={c}
                  image={photo}
                  square={Boolean(photo)}
                  colour={variants.filter((v) => v.color === c).map(variantSwatch).find(Boolean) || null}
                  selected={c === colour}
                  disabled={!inStock}
                  onClick={() => {
                    // Keep the chosen size when this colour has it in stock.
                    const same = find(c, size);
                    onChange(same && same.stock > 0 ? same : variants.find((v) => v.color === c && v.stock > 0));
                  }}
                />
              );
            })}
          </div>
        </div>
      )}
      {sizes.length > 1 && (
        <div className="space-y-2">
          <h3 className="text-sm font-semibold text-ink">{sizeLabel}</h3>
          <div className="flex flex-wrap gap-2">
            {sizes.map((s) => {
              const v = find(colour, s);
              return (
                <Chip key={s} selected={s === size} disabled={!v || v.stock <= 0} onClick={() => v && onChange(v)}>
                  {s}
                </Chip>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

/** "Portion: Full plate" lines under a cart, order or invoice row. */
export function OptionPicks({ picks = [], className = '' }) {
  if (!picks.length) return null;
  return (
    <ul className={`text-xs leading-snug ${className}`}>
      {picks.map((p) => (
        <li key={`${p.label}-${p.value}`}>
          <span className="text-ink-subtle">{p.label}: </span>
          <span className={p.removal ? 'text-danger font-medium' : 'text-ink-muted font-medium'}>
            {p.removal ? `no ${p.value}` : p.value}
          </span>
        </li>
      ))}
    </ul>
  );
}
