// Run with: npm test   (node's built-in test runner, no dependencies)
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { brand } from '../packages/brand/index.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const read = (p) => readFileSync(join(root, p), 'utf8');

function files(dir, out = []) {
  for (const name of readdirSync(join(root, dir))) {
    const rel = `${dir}/${name}`;
    if (name === 'node_modules' || name === '.next') continue;
    if (statSync(join(root, rel)).isDirectory()) files(rel, out);
    else if (/\.(js|jsx|json|xml|txt)$/.test(name) && !name.endsWith('.test.mjs')) out.push(rel);
  }
  return out;
}

test('the app is called Haatvia, with a wordmark that spells it', () => {
  assert.equal(brand.name, 'Haatvia');
  assert.equal(brand.nameDisplay + brand.nameAccent, brand.nameUpper);
  assert.equal(brand.logoInitials, 'HV');
});

test('no invented company or unowned domain is shown as the shop\'s own', () => {
  assert.ok(!/pvt|ltd/i.test(brand.legalEntity));
  assert.ok(!/bazaar/i.test(`${brand.domain} ${brand.supportEmail} ${brand.legalEntity}`));
});

test('the old name appears nowhere a shopper or the Play Store could read it', () => {
  const visible = ['app', 'components', 'lib', 'public', 'packages/brand'].flatMap((d) => files(d));
  // Storage keys and event names (bazaarx_cart, bazaarx:unauthorized) are internal and kept on purpose.
  const hits = visible.filter((f) => /BazaarX|BAZAARX|bazaarx\.(in|com)/.test(read(f)));
  assert.deepEqual(hits, []);
});

test('the Android package id in the guides is the one the app is built with', () => {
  const gradle = read('marketplace_app/android/app/build.gradle.kts');
  const built = /applicationId\s*=\s*"([^"]+)"/.exec(gradle)[1];
  assert.equal(built, 'in.haatvia.shop');
  assert.ok(read('lib/integrationGuides.js').includes(`'${built}'`));
});
