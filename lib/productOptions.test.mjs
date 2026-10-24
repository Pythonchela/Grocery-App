// Run with: npm test   (node's built-in test runner, no dependencies)
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  OPTION_PRESETS,
  cartLineRequest,
  hasRequiredOptions,
  isVariantGrid,
  optionUnitPrice,
  picksFromOrderItem,
  selectionDefaults,
  selectionProblem,
  selectionSignature,
  selectionSummary,
  swatchForName,
  variantSwatch,
} from './productOptions.js';

const food = [
  {
    key: 'portion', label: 'Portion', type: 'single', required: true, price_mode: 'set', min: 1, max: 1,
    choices: [
      { id: 'half_plate', label: 'Half plate', price: 180, default: true },
      { id: 'full_plate', label: 'Full plate', price: 320 },
    ],
  },
  {
    key: 'add_ons', label: 'Add-ons', type: 'multi', price_mode: 'add', min: 0, max: 2,
    choices: [
      { id: 'extra_cheese', label: 'Extra cheese', price: 30 },
      { id: 'egg', label: 'Egg', price: 20 },
      { id: 'paneer', label: 'Paneer', price: 50 },
    ],
  },
  {
    key: 'leave_out', label: 'Leave out', type: 'multi', remove: true, min: 0, max: 2,
    choices: [{ id: 'onion', label: 'Onion', price: 0 }, { id: 'garlic', label: 'Garlic', price: 0 }],
  },
];

const weight = [{
  key: 'weight', label: 'Weight', type: 'stepper', required: true, price_mode: 'multiply',
  stepper: { min: 0.5, max: 5, step: 0.5, unit: 'kg', default: 1, price: 0 },
}];

test('a set-price choice replaces the base; add-ons add; leave-outs are free', () => {
  assert.equal(optionUnitPrice(180, food, { portion: ['full_plate'] }), 320);
  assert.equal(optionUnitPrice(180, food, { portion: ['half_plate'], add_ons: ['extra_cheese', 'egg'], leave_out: ['onion'] }), 230);
});

test('a weight multiplies the per-unit price', () => {
  assert.equal(optionUnitPrice(60, weight, { weight: 1.5 }), 90);
});

test('defaults pre-select the flagged choice and start a required stepper', () => {
  assert.deepEqual(selectionDefaults(food), { portion: ['half_plate'] });
  assert.deepEqual(selectionDefaults(weight), { weight: 1 });
});

test('says what is missing, and when it is fine', () => {
  assert.equal(selectionProblem(food, {}), 'Choose Portion');
  assert.equal(selectionProblem(food, { portion: ['half_plate'] }), null);
  assert.equal(selectionProblem(food, { portion: ['half_plate'], add_ons: ['egg', 'paneer', 'extra_cheese'] }), 'Choose at most 2 for Add-ons');
  assert.equal(selectionProblem(weight, {}), 'Choose Weight');
});

test('a sold-out or withdrawn choice cannot be picked', () => {
  const g = [{ key: 'f', label: 'Flavour', type: 'single', required: true, min: 1, max: 1, choices: [
    { id: 'a', label: 'Mango', price: 0, stock: 0 },
    { id: 'b', label: 'Plain', price: 0, available: false },
    { id: 'c', label: 'Lime', price: 0 },
  ] }];
  assert.equal(selectionProblem(g, { f: ['a'] }), 'Mango is not available');
  assert.equal(selectionProblem(g, { f: ['b'] }), 'Plain is not available');
  assert.equal(selectionProblem(g, { f: ['c'] }), null);
});

test('equal selections share a signature regardless of order', () => {
  const a = { add_ons: ['egg', 'extra_cheese'], portion: ['half_plate'] };
  const b = { portion: ['half_plate'], add_ons: ['extra_cheese', 'egg'] };
  assert.equal(selectionSignature(a), selectionSignature(b));
  assert.equal(selectionSignature({}), '');
  assert.equal(selectionSignature({ add_ons: [] }), '');
});

test('a cart line sends the choices and never a price', () => {
  const req = cartLineRequest({ id: 'p1', variantId: 'v1', quantity: 2, price: 1, options: { portion: ['full_plate'] } });
  assert.deepEqual(req, { product_id: 'p1', variant_id: 'v1', quantity: 2, options: { portion: ['full_plate'] } });
  assert.equal('price' in req, false);
  assert.deepEqual(cartLineRequest({ id: 'p1', quantity: 1, options: {} }), { product_id: 'p1', variant_id: null, quantity: 1 });
});

test('the summary reads as the shopper would say it', () => {
  const picks = selectionSummary(food, { portion: ['full_plate'], leave_out: ['onion', 'garlic'] });
  assert.deepEqual(picks.map((p) => `${p.label}: ${p.value}`), ['Portion: Full plate', 'Leave out: Onion, Garlic']);
  assert.equal(picks[1].removal, true);
  assert.deepEqual(selectionSummary(weight, { weight: 1.5 }).map((p) => p.value), ['1.5 kg']);
});

test('an order line remembers what was chosen', () => {
  const picks = picksFromOrderItem([
    { key: 'portion', label: 'Portion', type: 'single', choices: [{ id: 'full_plate', label: 'Full plate', price: 320 }] },
    { key: 'weight', label: 'Weight', type: 'stepper', value: 2, unit: 'kg', choices: [] },
  ]);
  assert.deepEqual(picks.map((p) => `${p.label}: ${p.value}`), ['Portion: Full plate', 'Weight: 2 kg']);
  assert.deepEqual(picksFromOrderItem(null), []);
});

test('only a required choice blocks a one-tap add', () => {
  assert.equal(hasRequiredOptions(food), true);
  assert.equal(hasRequiredOptions(food.slice(1)), false);
  assert.equal(hasRequiredOptions([]), false);
});

test('colour names and variant swatches', () => {
  assert.equal(swatchForName(' Navy '), '#1F2A5A');
  assert.equal(swatchForName('Chartreuse-ish'), null);
  assert.equal(variantSwatch({ color: 'Navy', colorHex: '#112233' }), '#112233');
  assert.equal(variantSwatch({ color: 'Navy' }), '#1F2A5A');
});

test('a colour x size list is a grid; anything else is a plain list', () => {
  const v = (id, color, size) => ({ id, color, size });
  assert.equal(isVariantGrid([v(1, 'Navy', 'S'), v(2, 'Navy', 'M'), v(3, 'Red', 'S')]), true);
  assert.equal(isVariantGrid([v(1, 'Navy', 'S')]), false);
  assert.equal(isVariantGrid([v(1, 'Navy', ''), v(2, 'Red', '')]), false);
  assert.equal(isVariantGrid([v(1, 'Navy', 'S'), v(2, 'Navy', 'S')]), false);
});

test('every preset is a usable starting point', () => {
  for (const p of OPTION_PRESETS) {
    const groups = p.groups();
    assert.ok(groups.length > 0, p.id);
    assert.ok(groups.every((g) => g.label), p.id);
    assert.ok(groups.filter((g) => g.price_mode === 'set').length <= 1, `${p.id}: one set-price group at most`);
  }
});
