import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LEGAL } from './legal.js';

/**
 * The privacy policy is what the Play Store listing points at, so it has to exist,
 * be reachable from the footer, name who to contact, and cover the things Google
 * asks a policy to cover. These read the source rather than render it.
 */

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');

const privacy = read('app/privacy/page.js');
const deletion = read('app/delete-account/page.js');

test('both pages exist and are public server pages', () => {
  for (const source of [privacy, deletion]) {
    assert.doesNotMatch(source, /^'use client'/m, 'a policy page must render on the server');
    assert.match(source, /export const metadata/);
  }
});

test('the policy says who to contact, and the contact is real', () => {
  assert.match(LEGAL.email, /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i);
  assert.match(privacy, /LEGAL\.email/);
  assert.match(deletion, /LEGAL\.email/);
});

test('the policy covers what a store listing is asked about', () => {
  for (const id of ['collect', 'use', 'share', 'keep', 'rights', 'security', 'children', 'contact']) {
    assert.match(privacy, new RegExp(`id: '${id}'`), `section ${id}`);
  }
  for (const name of ['Razorpay', 'Google', 'Firebase', 'Anthropic', 'delivery', 'delete']) {
    assert.match(privacy, new RegExp(name, 'i'), name);
  }
});

test('the deletion page explains how, what goes and what stays', () => {
  for (const id of ['how', 'deleted', 'kept']) assert.match(deletion, new RegExp(`id="${id}"`), id);
  assert.match(deletion, /mailto:/);
});

test('nothing is left as a placeholder', () => {
  for (const source of [privacy, deletion]) {
    assert.doesNotMatch(source, /lorem ipsum|TODO|FIXME|\[your |\[company|example\.com/i);
  }
});

test('a single-business policy names no sellers', () => {
  assert.doesNotMatch(privacy + deletion, /\bsellers?\b/i);
});

test('the footer links to both pages', () => {
  const footer = read('components/providers/ClientLayout.jsx');
  assert.match(footer, /label:'Privacy Policy', href:'\/privacy'/);
  assert.match(footer, /label:'Delete Account', href:'\/delete-account'/);
});

// ── The shop policies ──────────────────────────────────────────────────────

const POLICY_PAGES = {
  terms: read('app/terms/page.js'),
  'refund-policy': read('app/refund-policy/page.js'),
  'shipping-policy': read('app/shipping-policy/page.js'),
  about: read('app/about/page.js'),
  contact: read('app/contact/page.js'),
  faqs: read('app/faqs/page.js'),
};

test('every policy page exists, renders on the server and has its own metadata', () => {
  for (const [name, source] of Object.entries(POLICY_PAGES)) {
    assert.doesNotMatch(source, /^'use client'/m, `${name} must render on the server`);
    assert.match(source, /export const metadata/, name);
    assert.match(source, new RegExp(`canonical: '/${name}'`), `${name} canonical`);
  }
});

test('the return window in the policies is the one the server enforces', () => {
  const controller = fs.readFileSync(
    path.join(ROOT, 'laravel-backend/app/Http/Controllers/Api/ReturnController.php'),
    'utf8',
  );
  const enforced = Number(controller.match(/RETURN_WINDOW_DAYS\s*=\s*(\d+)/)[1]);

  assert.equal(LEGAL.returnDays, enforced, 'lib/legal.js returnDays must match ReturnController');
  assert.match(POLICY_PAGES['refund-policy'], /LEGAL\.returnDays/);
});

test('the policies promise only what exists: no password reset, no sellers', () => {
  for (const [name, source] of Object.entries(POLICY_PAGES)) {
    assert.doesNotMatch(source, /sellers?|vendors?/i, `${name} mentions sellers`);
  }
  assert.doesNotMatch(POLICY_PAGES.faqs, /use the forgot password/i);
});

test('the policies name a real contact and leave nothing as a placeholder', () => {
  for (const [name, source] of Object.entries(POLICY_PAGES)) {
    assert.doesNotMatch(source, /lorem ipsum|TODO|FIXME|\[your |\[company|example\.com/i, name);
  }
  assert.match(POLICY_PAGES.contact, /LEGAL\.email/);
  assert.match(POLICY_PAGES.contact, /48 hours/);
});

test('every footer link goes somewhere: no dead # links remain', () => {
  const footer = read('components/providers/ClientLayout.jsx');

  assert.doesNotMatch(footer, /href:'#'/);
  for (const href of ['/terms', '/refund-policy', '/shipping-policy', '/about', '/contact', '/faqs', '/privacy', '/delete-account']) {
    assert.match(footer, new RegExp(`href:'${href}'`), href);
  }
});
