// Run with: npm test   (node's built-in test runner, no dependencies)
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  assurances,
  bundlePartner,
  colourPhoto,
  etaHeadline,
  etaPhrase,
  fastestOption,
  galleryImages,
  generalDelivery,
  openingVariant,
  ratingWord,
  usableBundle,
} from './productPage.js';

test('the page opens on the first variant in stock, else the first', () => {
  const sold = { id: 'a', stock: 0 };
  const live = { id: 'b', stock: 3 };
  assert.equal(openingVariant([sold, live]).id, 'b');
  assert.equal(openingVariant([sold, { id: 'c', stock: 0 }]).id, 'a');
  assert.equal(openingVariant([]), null);
});

test('a colour with its own pictures replaces the gallery', () => {
  const product = { images: ['p1', 'p2'] };
  assert.deepEqual(galleryImages(product, { images: ['r1'] }), ['r1']);
  assert.deepEqual(galleryImages(product, { images: [] }), ['p1', 'p2']);
  assert.deepEqual(galleryImages(product, null), ['p1', 'p2']);
});

test('a colour photo is the first picture any variant of that colour has', () => {
  const variants = [
    { color: 'Red', size: 'S', images: [] },
    { color: 'Red', size: 'M', images: ['red.jpg', 'red2.jpg'] },
    { color: 'Blue', size: 'S', images: [] },
  ];
  assert.equal(colourPhoto(variants, 'Red'), 'red.jpg');
  assert.equal(colourPhoto(variants, 'Blue'), null);
});

test('rating words match the phone app', () => {
  assert.equal(ratingWord(4.6), 'Excellent');
  assert.equal(ratingWord(4), 'Very good');
  assert.equal(ratingWord(3.2), 'Good');
  assert.equal(ratingWord(2), 'Fair');
  assert.equal(ratingWord(1.4), 'Poor');
});

test('assurances follow cash on delivery and the delivery profile', () => {
  const labels = (p) => assurances(p, 7).map((a) => a.label);
  assert.deepEqual(labels({ codAvailable: true }), ['7-day return', 'Cash on delivery']);
  assert.deepEqual(labels({ codAvailable: false }), ['7-day return', 'Prepaid only']);
  assert.deepEqual(labels({ codAvailable: true, deliveryProfile: 'instant' }), [
    '7-day return',
    'Cash on delivery',
    'Quick delivery',
  ]);
});

test('delivery headline reads in minutes, hours, or the server wording', () => {
  assert.equal(etaHeadline({ eta_minutes: 25 }), '25 mins');
  assert.equal(etaHeadline({ eta_minutes: 90 }), '1 hr 30 mins');
  assert.equal(etaHeadline({ eta_minutes: 185 }), '3 hrs');
  assert.equal(etaHeadline({ eta_minutes: 235 }), '4 hrs');
  assert.equal(etaHeadline({ eta_minutes: 2880, eta_label: '2 days' }), '2 days');
});

test('a day or more becomes tomorrow or a date', () => {
  const now = new Date(2026, 9, 14, 10, 0); // Wed 14 Oct 2026
  assert.deepEqual(etaPhrase({ eta_minutes: 25 }, now), { lead: 'Delivery in', when: '25 mins' });
  assert.deepEqual(etaPhrase({ eta_minutes: 24 * 60 }, now), { lead: 'Delivery', when: 'tomorrow' });
  const later = etaPhrase({ eta_minutes: 3 * 24 * 60 }, now);
  assert.equal(later.lead, 'Delivery by');
  assert.match(later.when, /^Sat 17 Oct$/);
  assert.deepEqual(etaPhrase({ eta_minutes: 0, eta_label: 'today' }, now), { lead: 'Delivery', when: 'today' });
});

test('the fastest option wins', () => {
  assert.equal(fastestOption([{ eta_minutes: 2880 }, { eta_minutes: 60 }, { eta_minutes: 600 }]).eta_minutes, 60);
  assert.equal(fastestOption([]), null);
});

test('without a PIN code the page says how this item travels', () => {
  assert.equal(generalDelivery({ deliveryProfile: 'heavy' }), 'Delivered by truck in a booked slot');
  assert.match(generalDelivery({ deliveryProfile: 'instant', prepMinutes: 20 }), /ready in about 20 mins/);
  assert.match(generalDelivery({ deliveryProfile: 'parcel' }, 1500), /free above ₹1,500/);
  assert.equal(generalDelivery({}, 1999), 'Free delivery above ₹1,999');
});

test('a bundle shows only when it is a complete pair with this product in it', () => {
  const deal = { products: [{ id: 'a' }, { id: 'b' }] };
  assert.ok(usableBundle(deal, 'a'));
  assert.ok(!usableBundle(deal, 'z'));
  assert.ok(!usableBundle({ products: [{ id: 'a' }] }, 'a'));
  assert.ok(!usableBundle(null, 'a'));
  assert.equal(bundlePartner(deal, 'a').id, 'b');
  assert.equal(bundlePartner(deal, 'b').id, 'a');
});
