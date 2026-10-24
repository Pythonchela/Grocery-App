import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * This is a single-business store. The website must not grow vendor pages, links or
 * API calls back by accident: this reads the source and fails if it does.
 */

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function sourceFiles(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) sourceFiles(full, out);
    else if (/\.(js|jsx)$/.test(entry.name) && !/\.test\./.test(entry.name)) {
      out.push({ rel: path.relative(ROOT, full).replaceAll('\\', '/'), source: fs.readFileSync(full, 'utf8') });
    }
  }
  return out;
}

const files = [...sourceFiles(path.join(ROOT, 'app')), ...sourceFiles(path.join(ROOT, 'components')), ...sourceFiles(path.join(ROOT, 'lib'))];

test('there are no vendor pages', () => {
  for (const dir of ['app/sell', 'app/seller', 'app/shops', 'app/shop', 'app/admin/sellers', 'app/admin/payouts', 'components/seller']) {
    assert.equal(fs.existsSync(path.join(ROOT, dir)), false, dir);
  }
});

test('nothing calls a vendor endpoint', () => {
  const calls = /['"`]\/(seller\/|sellers\/|shops\b|admin\/sellers|admin\/payout|admin\/bank-changes|admin\/category-requests)/;
  const offenders = files.filter((f) => calls.test(f.source)).map((f) => f.rel);
  assert.deepEqual(offenders, [], offenders.join('\n'));
});

test('nothing links to a vendor page', () => {
  const links = /href=["'{`]+\/(sell|seller|shops|shop\/)/;
  const offenders = files.filter((f) => links.test(f.source)).map((f) => f.rel);
  assert.deepEqual(offenders, [], offenders.join('\n'));
});
