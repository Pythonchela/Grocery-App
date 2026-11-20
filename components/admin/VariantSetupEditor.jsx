'use client';

import React, { useEffect, useRef, useState } from 'react';
import { Plus, X } from 'lucide-react';
import { currentKind } from '../../lib/storeKind';

/** Starting points, so nobody types a shoe size chart from nothing. */
export const SETUP_PRESETS = [
  {
    id: 'clothes',
    label: 'Clothes',
    setup: {
      size_label: 'Size',
      sizes: ['XS', 'S', 'M', 'L', 'XL', 'XXL'],
      color_label: 'Colour',
      colors: [
        { name: 'Black', hex: '#111111' }, { name: 'White', hex: '#FFFFFF' }, { name: 'Navy', hex: '#1F2A5A' },
        { name: 'Red', hex: '#C62828' }, { name: 'Green', hex: '#2E7D32' }, { name: 'Grey', hex: '#9E9E9E' },
      ],
    },
  },
  {
    id: 'shoes',
    label: 'Shoes',
    setup: {
      size_label: 'UK size',
      sizes: ['5', '6', '7', '8', '9', '10', '11'],
      color_label: 'Colour',
      colors: [{ name: 'Black', hex: '#111111' }, { name: 'White', hex: '#FFFFFF' }, { name: 'Brown', hex: '#6D4C41' }, { name: 'Blue', hex: '#1565C0' }],
    },
  },
  {
    id: 'phones',
    label: 'Phones and gadgets',
    setup: {
      size_label: 'Storage',
      sizes: ['64 GB', '128 GB', '256 GB', '512 GB'],
      color_label: 'Colour',
      colors: [{ name: 'Black', hex: '#111111' }, { name: 'Silver', hex: '#C0C0C0' }, { name: 'Blue', hex: '#1565C0' }],
    },
  },
  {
    id: 'packs',
    label: 'Food packs',
    setup: { size_label: 'Pack size', sizes: ['100 g', '250 g', '500 g', '1 kg'], color_label: 'Flavour', colors: [] },
  },
  {
    id: 'kids',
    label: 'Kids clothes',
    setup: {
      size_label: 'Age',
      sizes: ['0-1 yr', '1-2 yr', '2-3 yr', '3-4 yr', '5-6 yr', '7-8 yr'],
      color_label: 'Colour',
      colors: [{ name: 'Pink', hex: '#EC407A' }, { name: 'Blue', hex: '#1E88E5' }, { name: 'Yellow', hex: '#FDD835' }],
    },
  },
  {
    id: 'portion',
    label: 'Dish portions',
    setup: { size_label: 'Portion', sizes: ['Half plate', 'Full plate'], color_label: 'Flavour', colors: [] },
  },
  {
    id: 'drinks',
    label: 'Drinks',
    setup: { size_label: 'Size', sizes: ['250 ml', '500 ml', '1 L', '2 L'], color_label: 'Flavour', colors: [] },
  },
  {
    id: 'multipack',
    label: 'Multipacks',
    setup: { size_label: 'Pack of', sizes: ['1', '2', '4', '6', '12'], color_label: 'Flavour', colors: [] },
  },
  {
    id: 'sofas',
    label: 'Sofas and chairs',
    setup: {
      size_label: 'Seats',
      sizes: ['1-seater', '2-seater', '3-seater', '5-seater L-shape'],
      color_label: 'Fabric colour',
      colors: [
        { name: 'Grey', hex: '#6B7280' }, { name: 'Teal', hex: '#0F766E' }, { name: 'Beige', hex: '#D6C7A1' },
        { name: 'Navy', hex: '#1F2A5A' }, { name: 'Brown', hex: '#6D4C41' },
      ],
    },
  },
  {
    id: 'beds',
    label: 'Beds and mattresses',
    setup: {
      size_label: 'Bed size',
      sizes: ['Single', 'Double', 'Queen', 'King'],
      color_label: 'Finish',
      colors: [{ name: 'Walnut', hex: '#5D4037' }, { name: 'Teak', hex: '#8B5A2B' }, { name: 'White', hex: '#FFFFFF' }, { name: 'Grey', hex: '#6B7280' }],
    },
  },
  {
    id: 'storage',
    label: 'Wardrobes, tables and storage',
    setup: {
      size_label: 'Size',
      sizes: ['2-door', '3-door', '4-door', '4 ft', '6 ft'],
      color_label: 'Finish',
      colors: [{ name: 'Walnut', hex: '#5D4037' }, { name: 'Teak', hex: '#8B5A2B' }, { name: 'White', hex: '#FFFFFF' }, { name: 'Oak', hex: '#C8A165' }],
    },
  },
  {
    id: 'laundry',
    label: 'Washing machines',
    setup: {
      size_label: 'Capacity',
      sizes: ['6 kg', '6.5 kg', '7 kg', '8 kg', '9 kg'],
      color_label: 'Colour',
      colors: [{ name: 'White', hex: '#FFFFFF' }, { name: 'Silver', hex: '#C0C0C0' }, { name: 'Dark grey', hex: '#4B5563' }],
    },
  },
  {
    id: 'cooling',
    label: 'Fridges, ACs and coolers',
    setup: {
      size_label: 'Capacity',
      sizes: ['190 L', '260 L', '340 L', '1 ton', '1.5 ton', '2 ton'],
      color_label: 'Colour',
      colors: [{ name: 'White', hex: '#FFFFFF' }, { name: 'Silver', hex: '#C0C0C0' }, { name: 'Black', hex: '#111111' }],
    },
  },
];

/** The quick starts that fit this kind of store, in the order it lists them. */
const KIND_PRESETS = (currentKind.setupPresets || [])
  .map((id) => SETUP_PRESETS.find((p) => p.id === id))
  .filter(Boolean);

const inputCls =
  'w-full bg-surface-muted border border-line rounded-control px-3 py-2 text-xs font-medium focus:outline-none focus:border-line-strong';

const EMPTY = { size_label: 'Size', sizes: [], color_label: 'Colour', colors: [] };

const parseList = (text) => {
  const seen = new Set();
  return text
    .split(/[,\n]/)
    .map((s) => s.trim())
    .filter((s) => s && !seen.has(s.toLowerCase()) && seen.add(s.toLowerCase()));
};

/**
 * What the shoppers of a category choose between: what the two choices are called (Size and
 * Colour for clothes, Storage for phones, Pack size for food) and the values to offer. Adding a
 * product in the category is then picking from these, not typing them again.
 */
export default function VariantSetupEditor({ value, onChange }) {
  const setup = { ...EMPTY, ...(value || {}) };
  const [sizeText, setSizeText] = useState((setup.sizes || []).join(', '));
  const [colourName, setColourName] = useState('');
  const [colourHex, setColourHex] = useState('#888888');
  const emitted = useRef(setup.sizes.join('|'));

  // A quick start (or another category) replaced the sizes from outside: show them.
  useEffect(() => {
    const incoming = (value?.sizes || []).join('|');
    if (incoming !== emitted.current) {
      emitted.current = incoming;
      setSizeText((value?.sizes || []).join(', '));
    }
  }, [value]);

  const emit = (patch) => onChange({ ...setup, ...patch });
  const setSizes = (text) => {
    setSizeText(text);
    const sizes = parseList(text);
    emitted.current = sizes.join('|');
    emit({ sizes });
  };
  const addColour = () => {
    const name = colourName.trim();
    if (!name || setup.colors.some((c) => c.name.toLowerCase() === name.toLowerCase())) return;
    emit({ colors: [...setup.colors, { name, hex: colourHex.toUpperCase() }] });
    setColourName('');
  };

  return (
    <div className="space-y-4">
      <div>
        <p className="mb-1.5 text-[11px] font-semibold text-ink-muted">Start from</p>
        <div className="flex flex-wrap gap-2">
          {(KIND_PRESETS.length ? KIND_PRESETS : SETUP_PRESETS).map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => onChange(JSON.parse(JSON.stringify(p.setup)))}
              className="rounded-pill border border-line px-3 py-1.5 text-xs font-bold text-ink hover:border-line-strong"
            >
              {p.label}
            </button>
          ))}
          <button type="button" onClick={() => onChange(null)} className="rounded-pill border border-line px-3 py-1.5 text-xs font-bold text-ink-muted hover:border-line-strong">
            None
          </button>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2 rounded-card border border-line p-3">
          <label className="block">
            <span className="mb-1 block text-[11px] font-semibold text-ink-muted">First choice is called</span>
            <input className={inputCls} value={setup.size_label} maxLength={30} onChange={(e) => emit({ size_label: e.target.value })} placeholder="Size, Storage, Pack size…" />
          </label>
          <label className="block">
            <span className="mb-1 block text-[11px] font-semibold text-ink-muted">Values to offer (separate with commas)</span>
            <textarea rows={3} className={inputCls} value={sizeText} onChange={(e) => setSizes(e.target.value)} placeholder="S, M, L, XL" />
          </label>
        </div>

        <div className="space-y-2 rounded-card border border-line p-3">
          <label className="block">
            <span className="mb-1 block text-[11px] font-semibold text-ink-muted">Second choice is called</span>
            <input className={inputCls} value={setup.color_label} maxLength={30} onChange={(e) => emit({ color_label: e.target.value })} placeholder="Colour, Flavour, Finish…" />
          </label>
          <div>
            <span className="mb-1 block text-[11px] font-semibold text-ink-muted">Values to offer</span>
            <div className="mb-2 flex flex-wrap gap-1.5">
              {setup.colors.map((c) => (
                <span key={c.name} className="inline-flex items-center gap-1.5 rounded-pill border border-line bg-surface px-2 py-1 text-xs font-bold text-ink">
                  {c.hex && <span className="h-3.5 w-3.5 rounded-pill border border-line" style={{ background: c.hex }} />}
                  {c.name}
                  <button type="button" aria-label={`Remove ${c.name}`} onClick={() => emit({ colors: setup.colors.filter((x) => x.name !== c.name) })} className="text-ink-subtle hover:text-danger">
                    <X className="h-3 w-3" />
                  </button>
                </span>
              ))}
            </div>
            <div className="flex items-center gap-2">
              <input
                className={inputCls}
                value={colourName}
                maxLength={30}
                onChange={(e) => setColourName(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addColour(); } }}
                placeholder="Add a value, e.g. Navy"
              />
              <input type="color" aria-label="Swatch colour" value={colourHex} onChange={(e) => setColourHex(e.target.value)} className="h-8 w-9 shrink-0 cursor-pointer rounded-control border border-line bg-transparent p-0.5" />
              <button type="button" onClick={addColour} aria-label="Add value" className="shrink-0 rounded-pill bg-inverse p-2 text-ink-inverse"><Plus className="h-3.5 w-3.5" /></button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
