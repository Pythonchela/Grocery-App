import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * A store that sells only its own goods must show no trace of vendors: no "Sell on"
 * link, no shops row, no application page. The server tells the site what kind of
 * store it is (`vendors_enabled`, `shows_shops`...), and every place that mentions
 * vendors has to ask. This reads the source and fails when a new one forgets to.
 *
 * It is a guard, not a proof: it catches the usual mistake (a link or row added with
 * no check beside it). The behaviour itself is covered in the API tests.
 */

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Everything a shopper's browser can load: pages and components, not the seller or admin areas. */
function shopperFiles() {
  const out = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      const rel = path.relative(ROOT, full).replaceAll('\\', '/');
      if (entry.isDirectory()) {
        if (/^(app|components)\/(admin|seller)$/.test(rel) || entry.name === 'node_modules') continue;
        walk(full);
      } else if (/\.(js|jsx)$/.test(entry.name) && !/\.test\./.test(entry.name)) {
        out.push({ rel, source: fs.readFileSync(full, 'utf8') });
      }
    }
  };
  walk(path.join(ROOT, 'app'));
  walk(path.join(ROOT, 'components'));
  return out;
}

/** Files that do [mentions] and do not [asks]. */
function ungated(files, mentions, asks) {
  return files.filter((f) => mentions.test(f.source) && !asks.test(f.source)).map((f) => f.rel);
}

const RULES = [
  {
    why: 'a link into the seller area must check that the store takes sellers (offersSelling)',
    mentions: /sellerEntry\(/,
    asks: /offersSelling/,
  },
  {
    why: 'a link to the shops page must check that the store shows shops (shows_shops)',
    mentions: /href=["'{][^>]*\/shops["'`]/,
    asks: /shows_shops|showsShops/,
  },
  {
    why: 'the shops row must only be placed where the store layout allows it (shops_first)',
    mentions: /<ShopsRail/,
    asks: /shops_first/,
  },
];

test('the guard notices a vendor link that forgot to ask', () => {
  const sample = [{ rel: 'components/New.jsx', source: 'const e = sellerEntry(state); return <a href={e.href}>Sell</a>;' }];
  assert.deepEqual(ungated(sample, RULES[0].mentions, RULES[0].asks), ['components/New.jsx']);

  const fixed = [{ rel: 'components/New.jsx', source: 'const e = offersSelling(c) ? sellerEntry(state) : null;' }];
  assert.deepEqual(ungated(fixed, RULES[0].mentions, RULES[0].asks), []);
});

for (const rule of RULES) {
  test(rule.why, () => {
    const offenders = ungated(shopperFiles(), rule.mentions, rule.asks);
    assert.deepEqual(offenders, [], `${rule.why}:\n${offenders.join('\n')}`);
  });
}

test('the application and dashboard pages say so when the store has no vendors', () => {
  for (const file of ['components/seller/SellerOnboardingClient.jsx', 'components/seller/SellerDashboardClient.jsx']) {
    const source = fs.readFileSync(path.join(ROOT, file), 'utf8');
    assert.match(source, /offersSelling\(storeConfig\)/, file);
    assert.match(source, /VendorsOff/, file);
  }
});

test('the shops page sends a store without shops back to the home page', () => {
  const source = fs.readFileSync(path.join(ROOT, 'app/shops/page.js'), 'utf8');
  assert.match(source, /shows_shops/);
  assert.match(source, /redirect\(/);
});

test('the home page asks the store layout before showing shops', () => {
  const source = fs.readFileSync(path.join(ROOT, 'components/storefront/home/ShopsRail.jsx'), 'utf8');
  assert.match(source, /home_shows_shops/);
});
