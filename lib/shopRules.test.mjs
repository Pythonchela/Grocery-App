import test from 'node:test';
import assert from 'node:assert/strict';
import { FALLBACK_STORE_CONFIG, readStoreConfig } from './shopRules.js';

test('until the server answers, the store is a single business', () => {
  assert.equal(FALLBACK_STORE_CONFIG.mode, 'single');
  assert.equal(FALLBACK_STORE_CONFIG.vendors_enabled, false);
  assert.equal(FALLBACK_STORE_CONFIG.shows_shops, false);
});

test('what the server sends wins, and a missing key keeps the fallback', () => {
  assert.equal(readStoreConfig({ store_name: 'Corner Shop' }).store_name, 'Corner Shop');
  assert.equal(readStoreConfig({ store_name: 'Corner Shop' }).vendors_enabled, false);
});

test('nonsense from the server is ignored', () => {
  assert.deepEqual(readStoreConfig(null), FALLBACK_STORE_CONFIG);
  assert.deepEqual(readStoreConfig('x'), FALLBACK_STORE_CONFIG);
});
