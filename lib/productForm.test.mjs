// Run with: npm test   (node's built-in test runner, no dependencies)
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  EMPTY_FORM, formFromProduct, payloadFromForm, colourPhotosOf, hasVariantOptions, readiness, autoSlug,
} from './productForm.js';
import { STORE_KINDS } from './storeKind.js';

const { instant, parcel, heavy } = STORE_KINDS;

// A product as mapProduct() hands it over, with everything the advanced editor can set.
const saved = {
  id: 'p1',
  title: 'Brass Lamp',
  slug: 'brass-lamp',
  categoryId: 'c1',
  brand: 'Haat',
  price: 1200,
  mrp: 1500,
  isNew: true,
  status: 'ACTIVE',
  image: 'https://x/fallback.jpg',
  images: ['https://x/1.jpg', 'https://x/2.jpg'],
  authenticityGrade: 'GI Heritage Certified',
  rolloverImage: 'https://x/hover.jpg',
  hotspots: [{ id: 'h1', top: '10%', left: '20%', title: 'Base' }],
  spinImages: ['https://x/s1.jpg', 'https://x/s2.jpg'],
  lifestyleBadges: ['Handmade'],
  localStoreAvailable: false,
  local_store_name: 'Pune store',
  expressPincodes: ['411001'],
  features: ['Pure brass'],
  description: 'Plain',
  descriptionHtml: '<p>Rich</p>',
  specifications: [{ title: 'General', rows: [{ label: 'Height', value: '20 cm' }] }],
  manufacturer: { country_of_origin: 'India' },
  meta_description: 'Buy a brass lamp',
  reelVideoUrl: 'https://x/reel.mp4',
  reelCaption: 'Lit',
  customOptions: [{ id: 'g', name: 'Wick' }],
  deliveryProfile: 'parcel',
  prepMinutes: 15,
  weight_grams: 800,
  length_cm: 20,
  width_cm: 10,
  height_cm: 30,
  requires_vehicle: false,
  variants: [{ id: 'v1', color: 'Gold', colorHex: '#FFD700', size: '', sku: 'BL-G', stock: 4, price: null, mrp: null, images: ['https://x/g.jpg'] }],
};

test('editing a product on the page does not wipe what only the advanced editor can set', () => {
  const body = payloadFromForm(formFromProduct(saved));
  assert.deepEqual(body.hotspots, saved.hotspots);
  assert.deepEqual(body.spin_images, saved.spinImages);
  assert.equal(body.rollover_image, 'https://x/hover.jpg');
  assert.equal(body.authenticity_grade, 'GI Heritage Certified');
  assert.equal(body.meta_description, 'Buy a brass lamp');
  assert.equal(body.local_store_name, 'Pune store');
  assert.equal(body.local_store_available, false);
  assert.deepEqual(body.express_pincodes, ['411001']);
  assert.equal(body.reel_video_url, 'https://x/reel.mp4');
  assert.deepEqual(body.custom_options, [{ id: 'g', name: 'Wick' }]);
  assert.deepEqual(body.tags, ['Handmade']);
});

test('cash on delivery is on unless the product says otherwise', () => {
  assert.equal(payloadFromForm(formFromProduct(saved)).cod_available, true);
  assert.equal(payloadFromForm(formFromProduct({ ...saved, codAvailable: false })).cod_available, false);
});

test('photos come from the product\'s own list, never the storefront stand-in picture', () => {
  const form = formFromProduct({ ...saved, images: [], image: 'https://x/fallback.jpg' });
  assert.equal(form.image, '');
  assert.deepEqual(payloadFromForm(form).images, []);
  const withPhotos = payloadFromForm(formFromProduct(saved));
  assert.deepEqual(withPhotos.images, ['https://x/1.jpg', 'https://x/2.jpg']);
});

test('an existing variant keeps its id and colour photos', () => {
  const [v] = payloadFromForm(formFromProduct(saved)).variants;
  assert.equal(v.id, 'v1');
  assert.equal(v.stock, 4);
  assert.deepEqual(v.images, ['https://x/g.jpg']);
});

test('a blank product saves as a draft with a zero price, never NaN', () => {
  const body = payloadFromForm({ ...EMPTY_FORM, title: ' Mug ', categoryId: 'c1', status: 'DRAFT' });
  assert.equal(body.title, 'Mug');
  assert.equal(body.price, 0);
  assert.equal(body.mrp, 0);
  assert.equal(body.slug, 'mug');
  assert.equal(body.custom_options, null);
});

test('an empty printed price falls back to the selling price', () => {
  const body = payloadFromForm({ ...EMPTY_FORM, title: 'Mug', categoryId: 'c1', price: '499', mrp: '' });
  assert.equal(body.mrp, 499);
});

test('every size of a colour shares one set of photos', () => {
  const photos = colourPhotosOf([
    { color: 'Red', size: 'S', images: [] },
    { color: 'red ', size: 'M', images: ['a.jpg'] },
    { color: '', size: 'L' },
  ]);
  assert.deepEqual(Object.keys(photos), ['red']);
  assert.deepEqual(photos.red.photos, ['a.jpg']);
});

test('only a named colour or size, or several variants, counts as "comes in options"', () => {
  assert.equal(hasVariantOptions([{ color: '', size: '' }]), false);
  assert.equal(hasVariantOptions([{ color: 'Standard', size: 'Free Size' }]), false);
  assert.equal(hasVariantOptions([{ color: 'Red', size: '' }]), true);
  assert.equal(hasVariantOptions([{ color: '', size: '' }, { color: '', size: '' }]), true);
});

test('going live needs a name, category, photo and price; weight and description are only suggested', () => {
  const empty = readiness(EMPTY_FORM, parcel);
  assert.equal(empty.ready, false);
  assert.deepEqual(empty.required.map((r) => r.step), ['basics', 'basics', 'photos', 'price']);

  const ok = readiness({
    ...EMPTY_FORM, title: 'Mug', categoryId: 'c1', image: 'a.jpg', price: '299', mrp: '399',
  }, parcel);
  assert.equal(ok.ready, true);
  assert.ok(ok.suggested.some((s) => s.step === 'delivery'));
  assert.ok(ok.suggested.some((s) => /description/.test(s.text)));
});

test('a printed price below the selling price is refused', () => {
  const r = readiness({ ...EMPTY_FORM, title: 'Mug', categoryId: 'c1', image: 'a.jpg', price: '500', mrp: '400' }, parcel);
  assert.equal(r.ready, false);
  assert.match(r.required[0].text, /MRP/);
});

const base = { ...EMPTY_FORM, title: 'Thing', categoryId: 'c1', image: 'a.jpg', price: '299', mrp: '399' };

test('the veg mark travels with the product', () => {
  assert.equal(payloadFromForm(formFromProduct({ ...saved, diet: 'veg' })).diet, 'veg');
  assert.equal(payloadFromForm(formFromProduct(saved)).diet, null);
});

test('food and grocery: no weight or parcel size is asked for, only the veg mark is suggested', () => {
  const r = readiness(base, instant);
  assert.equal(r.ready, true);
  assert.ok(!r.suggested.some((s) => s.step === 'delivery'), 'no delivery nags for food');
  assert.ok(r.suggested.some((s) => /veg/.test(s.text)));
  assert.equal(readiness({ ...base, diet: 'veg' }, instant).suggested.some((s) => /veg/.test(s.text)), false);
});

test('shopping: a weight is suggested but never blocks going live', () => {
  const r = readiness(base, parcel);
  assert.equal(r.ready, true);
  assert.ok(r.suggested.some((s) => /weight/.test(s.text)));
  assert.ok(!r.suggested.some((s) => /veg/.test(s.text)));
});

test('heavy items: going live needs the packed weight and all three sizes', () => {
  const none = readiness(base, heavy);
  assert.equal(none.ready, false);
  assert.deepEqual(none.required.map((r) => r.step), ['delivery', 'delivery']);

  const weightOnly = readiness({ ...base, weightGrams: '40000' }, heavy);
  assert.equal(weightOnly.required.length, 1);
  assert.match(weightOnly.required[0].text, /size/);

  const ok = readiness({ ...base, weightGrams: '40000', lengthCm: '200', widthCm: '90', heightCm: '85' }, heavy);
  assert.equal(ok.ready, true);
});

test('every kind has a delivery type, a spec starter and a stock default', () => {
  for (const [id, kind] of Object.entries(STORE_KINDS)) {
    assert.equal(kind.id, id);
    assert.ok(['instant', 'parcel', 'heavy'].includes(kind.profile));
    assert.ok(kind.specStarter.every((g) => g.title && g.labels.length));
    assert.ok(parseInt(kind.defaultStock, 10) > 0);
  }
  assert.equal(heavy.defaultVehicle, true);
  assert.equal(instant.colours, false);
});

test('slugs are lower-case words joined with dashes', () => {
  assert.equal(autoSlug('Hand-Embroidered  Anarkali Set!'), 'hand-embroidered-anarkali-set');
});
