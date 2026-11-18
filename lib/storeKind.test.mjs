// Run with: npm test   (node's built-in test runner, no dependencies)
//
// Each copy of the project is one kind of store. The kind is set in lib/storeKind.js, and the
// starter seeder must agree with it, or a food app would ship with furniture samples.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { STORE_KIND, STORE_KINDS, currentKind, defaultProfile } from './storeKind.js';

const seeder = fs.readFileSync(new URL('../laravel-backend/database/seeders/StarterCatalogSeeder.php', import.meta.url), 'utf8');

test('the app is set to one of the three kinds', () => {
  assert.ok(Object.keys(STORE_KINDS).includes(STORE_KIND), `unknown STORE_KIND "${STORE_KIND}"`);
  assert.equal(currentKind, STORE_KINDS[STORE_KIND]);
  assert.equal(defaultProfile, currentKind.profile);
});

test('every category the starter seeder makes is delivered the way this app delivers', () => {
  const profiles = [...seeder.matchAll(/'delivery_profile'\s*=>\s*'(\w+)'/g)].map((m) => m[1]);
  assert.ok(profiles.length > 0, 'the starter seeder sets no delivery type');
  assert.deepEqual([...new Set(profiles)], [currentKind.profile]);
});

test('only food and grocery ask for the veg mark', () => {
  for (const kind of Object.values(STORE_KINDS)) assert.equal(kind.diet, kind.id === 'instant');
});

test('only heavy items require a weight and size to go live', () => {
  for (const kind of Object.values(STORE_KINDS)) {
    assert.equal(kind.needs.weight, kind.id === 'heavy');
    assert.equal(kind.needs.dimensions, kind.id === 'heavy');
  }
});
