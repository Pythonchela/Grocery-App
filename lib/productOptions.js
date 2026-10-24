/**
 * Custom selection options - portion, add-ons, "leave out", colour swatches, a
 * weight in kg - as the API describes them for a product.
 *
 * The server prices an order from the shopper's choices; the arithmetic here
 * only previews the price while they pick. It mirrors `ProductOptions::resolve()`
 * on the backend and `ProductOptionMath` in the mobile app, rule for rule.
 *
 * A selection is `{ [groupKey]: [choiceId, ...] | number }`.
 */

const round2 = (n) => Math.round(n * 100) / 100;

export function isStepper(group) {
  return group.type === 'stepper';
}

/** "1.5" not "1.500", "2" not "2.0". */
export function formatOptionNumber(value) {
  return String(Number(Number(value).toFixed(3)));
}

export function formatStepperValue(group, value) {
  const unit = group.stepper?.unit;
  return `${formatOptionNumber(value)}${unit ? ` ${unit}` : ''}`;
}

/** Choice ids picked in a group (always an array). */
export function pickedIds(selection, key) {
  const v = selection?.[key];
  return Array.isArray(v) ? v : [];
}

/** What the product page opens with: flagged choices, steppers at their start. */
export function selectionDefaults(groups = []) {
  const selection = {};
  for (const g of groups) {
    if (isStepper(g)) {
      if (g.required && g.stepper) selection[g.key] = g.stepper.default ?? g.stepper.min;
      continue;
    }
    const flagged = (g.choices || []).filter((c) => c.default && isSelectable(c));
    if (flagged.length) selection[g.key] = g.type === 'multi' ? flagged.map((c) => c.id) : [flagged[0].id];
  }
  return selection;
}

export function isSelectable(choice) {
  return choice.available !== false && (choice.stock === null || choice.stock === undefined || choice.stock > 0);
}

/** Equal selections share a signature - used to merge identical cart lines. */
export function selectionSignature(selection) {
  return Object.entries(selection || {})
    .filter(([, v]) => (Array.isArray(v) ? v.length > 0 : v !== null && v !== undefined))
    .map(([k, v]) => `${k}=${Array.isArray(v) ? [...v].sort().join(',') : formatOptionNumber(v)}`)
    .sort()
    .join('|');
}

export function hasSelection(selection) {
  return selectionSignature(selection) !== '';
}

/** The unit price with the shopper's picks on it. */
export function optionUnitPrice(base, groups = [], selection = {}) {
  let setPrice = null;
  let multiplier = 1;
  let add = 0;

  for (const g of groups) {
    if (isStepper(g)) {
      const v = selection[g.key];
      if (v === undefined || v === null || !g.stepper) continue;
      if (g.price_mode === 'multiply') multiplier *= Number(v);
      else add += Number(v) * Number(g.stepper.price || 0);
      continue;
    }
    for (const id of pickedIds(selection, g.key)) {
      const c = (g.choices || []).find((x) => x.id === id);
      if (!c) continue;
      if (g.price_mode === 'set') setPrice = Number(c.price);
      else add += Number(c.price);
    }
  }

  return round2((setPrice ?? base) * multiplier + add);
}

/** The first thing wrong with the selection, or null when it can be ordered. */
export function selectionProblem(groups = [], selection = {}) {
  for (const g of groups) {
    if (isStepper(g)) {
      const v = selection[g.key];
      if (v === undefined || v === null) {
        if (g.required) return `Choose ${g.label}`;
        continue;
      }
      const s = g.stepper;
      if (v < s.min - 1e-9 || v > s.max + 1e-9) return `${g.label} is out of range`;
      continue;
    }

    const picked = pickedIds(selection, g.key);
    if (picked.length === 0) {
      if (g.required || g.min > 0) return `Choose ${g.label}`;
      continue;
    }
    if (picked.length < (g.min || 0)) return `Choose at least ${g.min} for ${g.label}`;
    if (g.type === 'multi' && picked.length > g.max) return `Choose at most ${g.max} for ${g.label}`;
    for (const id of picked) {
      const c = (g.choices || []).find((x) => x.id === id);
      if (!c || !isSelectable(c)) return `${c?.label || id} is not available`;
    }
  }
  return null;
}

/**
 * "Portion: Full plate", "Leave out: Onion" - the picks as printable lines.
 * Works on live selections (with the product's groups) ...
 */
export function selectionSummary(groups = [], selection = {}) {
  const picks = [];
  for (const g of groups) {
    if (isStepper(g)) {
      const v = selection[g.key];
      if (v !== undefined && v !== null) picks.push({ label: g.label, value: formatStepperValue(g, v), removal: false });
      continue;
    }
    const names = pickedIds(selection, g.key)
      .map((id) => (g.choices || []).find((c) => c.id === id)?.label)
      .filter(Boolean);
    if (names.length) picks.push({ label: g.label, value: names.join(', '), removal: Boolean(g.remove) });
  }
  return picks;
}

/** ... and on what an order stored (`selected_options`). */
export function picksFromOrderItem(selectedOptions) {
  if (!Array.isArray(selectedOptions)) return [];
  const picks = [];
  for (const g of selectedOptions) {
    if (g.type === 'stepper') {
      if (typeof g.value === 'number') {
        picks.push({ label: g.label, value: `${formatOptionNumber(g.value)}${g.unit ? ` ${g.unit}` : ''}`, removal: false });
      }
      continue;
    }
    const names = (g.choices || []).map((c) => c.label);
    if (names.length) picks.push({ label: g.label, value: names.join(', '), removal: Boolean(g.remove) });
  }
  return picks;
}

export function hasRequiredOptions(groups = []) {
  return groups.some((g) => g.required || g.min > 0);
}

/** Common colour names -> a swatch, so a variant called "Navy" needs no setup. */
const NAMED_COLOURS = {
  black: '#1B1B1F', white: '#FFFFFF', red: '#D32F2F', maroon: '#7B1E2B', pink: '#EC6A9B',
  orange: '#F57C00', yellow: '#FBC02D', mustard: '#D4A017', green: '#2E7D32', olive: '#6B7A2A',
  teal: '#00897B', blue: '#1E5BD8', navy: '#1F2A5A', 'sky blue': '#5DADE2', purple: '#7B3FA0',
  violet: '#7E57C2', brown: '#6D4C41', beige: '#D9C7A3', cream: '#F3EAD3', grey: '#8E8E93',
  gray: '#8E8E93', silver: '#BFC3C9', gold: '#D4AF37', tan: '#B98B5E',
};

export function swatchForName(name) {
  return NAMED_COLOURS[String(name || '').trim().toLowerCase()] || null;
}

/** A variant's own hex wins over the name lookup. */
export function variantSwatch(variant) {
  return variant?.colorHex || variant?.color_hex || (variant?.color ? swatchForName(variant.color) : null);
}

/** Variants that form a colour x size grid get swatches and size chips. */
export function isVariantGrid(variants = []) {
  if (variants.length < 2) return false;
  if (variants.some((v) => !v.color || !v.size)) return false;
  const colours = new Set(variants.map((v) => v.color));
  const sizes = new Set(variants.map((v) => v.size));
  const pairs = new Set(variants.map((v) => `${v.color}|${v.size}`));
  return (colours.size > 1 || sizes.size > 1) && pairs.size === variants.length;
}

/** The request body for one cart line. */
export function cartLineRequest(item) {
  return {
    product_id: item.id,
    variant_id: item.variantId || null,
    quantity: item.quantity,
    ...(hasSelection(item.options) ? { options: item.options } : {}),
  };
}

// ── Delivery ─────────────────────────────────────────────────────────────────
// How a kind of item travels. Matches DeliveryProfile on the API: a category sets
// the default and a product can override it.
export const DELIVERY_PROFILES = [
  { value: 'instant', label: 'Quick local delivery', hint: 'Food, groceries - a rider brings it within hours, never as a multi-day parcel.' },
  { value: 'parcel', label: 'Courier parcel', hint: 'Clothes, electronics, books - express or standard courier, tracked by status.' },
  { value: 'heavy', label: 'Heavy item', hint: 'Furniture, appliances - a truck in a booked slot.' },
];

// ── Admin presets ────────────────────────────────────────────────────────────
// One click fills the editor with a sensible starting point for a kind of
// store. Everything in them is editable; nothing is special-cased downstream.

const choice = (label, price = 0, extra = {}) => ({ label, price, ...extra });

export const OPTION_PRESETS = [
  {
    id: 'food',
    name: 'Food & restaurant',
    description: 'Half / full plate, add-ons, leave-outs, spice level',
    groups: () => [
      {
        label: 'Portion', type: 'single', required: true, price_mode: 'set',
        help: 'Each portion has its own price.',
        choices: [choice('Half plate', 150, { default: true }), choice('Full plate', 250)],
      },
      { label: 'Add-ons', type: 'multi', max: 3, choices: [choice('Extra cheese', 30), choice('Extra gravy', 20)] },
      { label: 'Leave out', type: 'multi', remove: true, max: 3, choices: [choice('Onion'), choice('Garlic')] },
      { label: 'Spice level', type: 'single', choices: [choice('Mild'), choice('Medium', 0, { default: true }), choice('Hot')] },
    ],
  },
  {
    id: 'grocery',
    name: 'Grocery & produce',
    description: 'Pick the weight - the price is per kg',
    groups: () => [
      {
        label: 'Weight', type: 'stepper', required: true, price_mode: 'multiply',
        help: 'The price shown is per kg.',
        stepper: { min: 0.5, max: 10, step: 0.5, unit: 'kg', default: 1 },
      },
    ],
  },
  {
    id: 'fashion',
    name: 'Clothing & fashion',
    description: 'Colour swatches (from variants) plus a fit option',
    groups: () => [
      { label: 'Fit', type: 'single', choices: [choice('Regular', 0, { default: true }), choice('Slim'), choice('Relaxed')] },
    ],
    note: 'Colours and sizes come from each product\'s variants - give a variant a colour (and optionally a swatch colour) and the product page shows swatches and size chips with their own stock.',
  },
  {
    id: 'gifting',
    name: 'Gifting & custom',
    description: 'Gift wrap and a packing choice',
    groups: () => [
      { label: 'Gift wrap', type: 'single', choices: [choice('No wrap', 0, { default: true }), choice('Standard wrap', 49), choice('Premium wrap', 99)] },
    ],
  },
];

export const BLANK_GROUP = () => ({
  label: '',
  type: 'single',
  required: false,
  price_mode: 'add',
  choices: [{ label: '', price: 0 }],
});
