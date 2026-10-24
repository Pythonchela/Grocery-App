import test from 'node:test';
import assert from 'node:assert/strict';
import { clock, hoursLines, mapShop, shopSubtitle, shopMetaLine } from './shops.js';

const money = (n) => `₹${n}`;

test('clock times read the way people say them', () => {
  assert.equal(clock('21:00'), '9:00 PM');
  assert.equal(clock('09:30'), '9:30 AM');
  assert.equal(clock('00:05'), '12:05 AM');
  assert.equal(clock('12:00'), '12:00 PM');
});

test('a shop that set no hours has no hours to list', () => {
  assert.deepEqual(hoursLines(null), []);
  assert.deepEqual(hoursLines({}), []);
});

test('the week lists every day, with closed days said plainly', () => {
  const lines = hoursLines({ mon: { open: '09:00', close: '21:00' }, tue: null });

  assert.equal(lines.length, 7);
  assert.deepEqual(lines[0], { day: 'Monday', hours: '9:00 AM – 9:00 PM' });
  assert.deepEqual(lines[1], { day: 'Tuesday', hours: 'Closed' });
  assert.equal(lines[2].hours, 'Closed'); // a day left out is closed too
});

test('a shop is read from the API with sensible defaults', () => {
  const shop = mapShop({ id: 7, name: 'Sharma Kirana', slug: 'sharma-kirana', is_open: false, closed_text: 'Opens tomorrow at 9:00 AM', min_order_amount: '149.00', prep_minutes: 20, categories: ['Groceries', 'Dairy'] });

  assert.equal(shop.id, '7');
  assert.equal(shop.isOpen, false);
  assert.equal(shop.closedText, 'Opens tomorrow at 9:00 AM');
  assert.equal(shop.minOrder, 149);
  assert.equal(shop.logoUrl, null);
  assert.deepEqual(shop.hours, []);
});

test('a shop with nothing but a name is open and has no minimum', () => {
  const shop = mapShop({ id: 'x', name: 'Bare' });

  assert.equal(shop.isOpen, true);
  assert.equal(shop.minOrder, 0);
  assert.equal(shop.prepMinutes, null);
  assert.deepEqual(shop.categories, []);
});

test('the subtitle prefers the shop tagline over the categories', () => {
  assert.equal(shopSubtitle(mapShop({ id: 1, tagline: 'Fresh every morning', categories: ['Dairy'] })), 'Fresh every morning');
  assert.equal(shopSubtitle(mapShop({ id: 1, categories: ['Groceries', 'Dairy'] })), 'Groceries · Dairy');
});

test('the meta line has only the parts the shop has', () => {
  assert.equal(shopMetaLine(mapShop({ id: 1, prep_minutes: 20, min_order_amount: 149 }), money), '20 mins · Min ₹149');
  assert.equal(shopMetaLine(mapShop({ id: 1, min_order_amount: 149 }), money), 'Min ₹149');
  assert.equal(shopMetaLine(mapShop({ id: 1 }), money), '');
});
