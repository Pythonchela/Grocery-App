// Run with: npm test   (node's built-in test runner, no dependencies)
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  attention,
  commitBody,
  formFromImportRow,
  isReady,
  mergeResults,
  planBatches,
  sortedForReview,
} from './importRows.js';

const file = (name) => ({ name });

test('a spreadsheet is read on its own, photos in groups of six', () => {
  const photos = Array.from({ length: 8 }, (_, i) => file(`p${i}.jpg`));
  const batches = planBatches([file('list.xlsx'), ...photos]);

  assert.equal(batches.length, 3);
  assert.deepEqual(batches[0].files.map((f) => f.name), ['list.xlsx']);
  assert.equal(batches[1].files.length, 6);
  assert.equal(batches[2].files.length, 2);
});

test('each document and the pasted text is its own request', () => {
  const batches = planBatches([file('a.pdf'), file('b.docx')], 'Shoe 100');

  assert.equal(batches.length, 3);
  assert.deepEqual(batches.map((b) => b.files.length), [1, 1, 0]);
  assert.equal(batches[2].text, 'Shoe 100');
});

test('photos and a document travel together when the owner says they belong together', () => {
  const batches = planBatches([file('prices.pdf'), file('a.jpg'), file('b.jpg')], '', { together: true });

  assert.equal(batches.length, 1);
  assert.deepEqual(batches[0].files.map((f) => f.name), ['prices.pdf', 'a.jpg', 'b.jpg']);
});

test('together is ignored when there is too much to send in one go', () => {
  const photos = Array.from({ length: 12 }, (_, i) => file(`p${i}.jpg`));

  assert.equal(planBatches([file('prices.pdf'), ...photos], '', { together: true }).length, 3);
});

test('results are joined, renumbered, and their warnings listed once', () => {
  const merged = mergeResults([
    { rows: [{ index: 0, title: 'A' }], problems: ['x'], notes: [], driver: 'table', categories: [{ id: 1 }] },
    { rows: [{ index: 0, title: 'B' }], problems: ['x', 'y'], notes: ['n'], driver: 'ai', categories: [{ id: 1 }] },
    null,
  ]);

  assert.deepEqual(merged.rows.map((r) => [r.index, r.title]), [[0, 'A'], [1, 'B']]);
  assert.deepEqual(merged.problems, ['x', 'y']);
  assert.deepEqual(merged.drivers, ['table', 'ai']);
  assert.equal(merged.categories.length, 1);
});

const ready = { title: 'Shoe', price: 100, mrp: 150, category_id: 'c1', issues: [], confidence: {} };

test('a row is ready only with a title, both prices and a category', () => {
  assert.ok(isReady(ready));
  assert.ok(!isReady({ ...ready, category_id: null }));
  assert.ok(!isReady({ ...ready, price: null }));
  assert.ok(!isReady({ ...ready, title: '  ' }));
  assert.ok(isReady({ ...ready, price: 0 }), 'free is a price; the server decides about going live');
});

test('doubtful numbers and possible duplicates need checking, other warnings are notes', () => {
  assert.equal(attention(ready), 'ok');
  assert.equal(attention({ ...ready, issues: ['No photo yet'] }), 'note');
  assert.equal(attention({ ...ready, confidence: { price: 0.35 } }), 'check');
  assert.equal(attention({ ...ready, possible_duplicate: 'p1' }), 'check');
  assert.equal(attention({ ...ready, category_id: null }), 'check');
});

test('rows that need checking come first', () => {
  const rows = [
    { ...ready, index: 0 },
    { ...ready, index: 1, confidence: { price: 0.3 } },
    { ...ready, index: 2, issues: ['n'] },
  ];

  assert.deepEqual(sortedForReview(rows).map((r) => r.index), [1, 2, 0]);
});

test('only ticked, ready rows are committed, with numbers as numbers', () => {
  const body = commitBody([
    { ...ready, include: true, price: '99.5', mrp: '150', variants: [{ color: 'Red', size: 'M', stock: '3', sku: '', price: '' }], features: ['a', ''] },
    { ...ready, include: false },
    { ...ready, include: true, category_id: null },
  ], 'DRAFT');

  assert.equal(body.rows.length, 1);
  assert.equal(body.rows[0].price, 99.5);
  assert.deepEqual(body.rows[0].variants[0], { color: 'Red', size: 'M', sku: null, stock: 3, price: null, mrp: null });
  assert.deepEqual(body.rows[0].features, ['a']);
  assert.equal(body.status, 'DRAFT');
});

const emptyForm = {
  title: '', brand: '', categoryId: '', price: '', mrp: '', description: '', descriptionHtml: '',
  features: [], specifications: [], lifestyleBadges: [], manufacturer: {}, image: '', gallery: [],
  weightGrams: '', lengthCm: '', widthCm: '', heightCm: '',
  variants: [{ color: '', colorHex: '', size: '', sku: '', stock: '10', price: '', mrp: '' }],
};

const parsed = {
  title: 'Canvas Sneaker', brand: 'Acme', category_id: 'c1', price: 1499, mrp: 2499,
  description: 'A sneaker.\n\nSoft sole.', features: ['Rubber sole'], specifications: [{ title: 'General', rows: [{ label: 'Upper', value: 'Canvas' }] }],
  manufacturer: { country_of_origin: 'India' }, weight_grams: 600, images: ['a.jpg', 'b.jpg', 'c.jpg'],
  variants: [{ color: 'White', size: 'UK 7', stock: 4, price: 1599 }],
};

test('a parsed row fills an empty form', () => {
  const { form, filled } = formFromImportRow(emptyForm, parsed);

  assert.equal(form.title, 'Canvas Sneaker');
  assert.equal(form.price, '1499');
  assert.equal(form.categoryId, 'c1');
  assert.equal(form.image, 'a.jpg');
  assert.deepEqual(form.gallery, ['b.jpg', 'c.jpg']);
  assert.equal(form.descriptionHtml, '<p>A sneaker.</p><p>Soft sole.</p>');
  assert.equal(form.variants[0].size, 'UK 7');
  assert.equal(form.variants[0].price, '1599');
  assert.equal(form.weightGrams, '600');
  assert.ok(filled.includes('title') && filled.includes('colours and sizes'));
});

test('what the owner already typed is never overwritten', () => {
  const typed = {
    ...emptyForm, title: 'My own title', price: '999', features: ['Mine'],
    variants: [{ color: 'Blue', colorHex: '', size: 'L', sku: '', stock: '2', price: '', mrp: '' }],
  };

  const { form, filled } = formFromImportRow(typed, parsed);

  assert.equal(form.title, 'My own title');
  assert.equal(form.price, '999');
  assert.deepEqual(form.features, ['Mine']);
  assert.equal(form.variants[0].color, 'Blue');
  assert.ok(!filled.includes('title') && !filled.includes('price') && !filled.includes('colours and sizes'));
  assert.equal(form.mrp, '2499', 'empty fields are still filled');
});
