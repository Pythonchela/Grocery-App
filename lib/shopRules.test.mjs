import test from 'node:test';
import assert from 'node:assert/strict';
import {
  FALLBACK_STORE_CONFIG,
  readStoreConfig,
  cartShop,
  shopConflict,
  offersSelling,
} from './shopRules.js';

const line = (shopId, soldBy) => ({ cartItemId: `p-${shopId}`, shopId, soldBy, quantity: 1 });
const config = { ...FALLBACK_STORE_CONFIG, one_shop_per_cart: true };

test('the home carries shops unless the store says otherwise', () => {
  assert.equal(readStoreConfig({}).home_shows_shops, true, 'an older server that never says');
  assert.equal(readStoreConfig({ home_shows_shops: false }).home_shows_shops, false);
});

test('an empty basket never conflicts', () => {
  assert.equal(shopConflict([], { shopId: 'a' }, config), null);
  assert.equal(shopConflict(undefined, { shopId: 'a' }, config), null);
});

test('adding from the same shop is fine', () => {
  assert.equal(shopConflict([line('a', 'Sharma Kirana')], { shopId: 'a' }, config), null);
});

test('adding from another shop names the shop already in the basket', () => {
  assert.equal(shopConflict([line('a', 'Sharma Kirana')], { shopId: 'b' }, config), 'Sharma Kirana');
});

test('a shop with no name still conflicts, and says so plainly', () => {
  assert.equal(shopConflict([line('a', null)], { shopId: 'b' }, config), 'another shop');
});

test('goods that do not say which shop never conflict, either way round', () => {
  assert.equal(shopConflict([line('a', 'Sharma Kirana')], { id: 'reel' }, config), null);
  assert.equal(shopConflict([{ cartItemId: 'x', quantity: 1 }], { shopId: 'b' }, config), null);
});

test('a store that lets a basket mix shops never conflicts', () => {
  assert.equal(shopConflict([line('a', 'Sharma Kirana')], { shopId: 'b' }, { ...config, one_shop_per_cart: false }), null);
});

test('the shop is read from the first line that names one', () => {
  assert.deepEqual(cartShop([{ cartItemId: 'x' }, line('a', 'Sharma Kirana')]), { id: 'a', name: 'Sharma Kirana' });
  assert.equal(cartShop([]), null);
});

test('the server answer is laid over the fallback so a missing key does not hide anything', () => {
  assert.equal(readStoreConfig({ mode: 'single', vendors_enabled: false }).shows_shops, true);
  assert.equal(readStoreConfig({ mode: 'single', vendors_enabled: false }).mode, 'single');
  assert.deepEqual(readStoreConfig(null), FALLBACK_STORE_CONFIG);
});

test('only a single-business store stops offering to sell', () => {
  assert.equal(offersSelling({ vendors_enabled: false }), false);
  assert.equal(offersSelling({ vendors_enabled: true }), true);
  assert.equal(offersSelling(null), true);
});
