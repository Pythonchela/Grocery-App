import test from 'node:test';
import assert from 'node:assert/strict';
import { GUIDES } from './integrationGuides.js';

// Every settings tab has a guide, and a guide is plain data: no markup, no
// scripts, and links only to https pages.

const TABS_WITH_GUIDES = ['overview', 'general', 'google', 'email', 'sms', 'couriers', 'push', 'storage', 'gemini', 'payments'];

test('every settings tab has a guide with steps', () => {
  for (const id of TABS_WITH_GUIDES) {
    const guide = GUIDES[id];
    assert.ok(guide, `no guide for ${id}`);
    assert.ok(guide.title && guide.intro, `${id}: title and intro`);
    assert.ok(guide.parts.length > 0, `${id}: parts`);
    for (const part of guide.parts) {
      assert.ok(part.steps.length > 0, `${id}: steps`);
      for (const step of part.steps) assert.ok(step.title && step.body, `${id}: a step needs a title and a body`);
    }
  }
});

test('the guides that explain keys say how long it takes and what it costs', () => {
  for (const id of ['google', 'email', 'sms', 'couriers', 'push', 'storage', 'gemini', 'payments']) {
    const labels = GUIDES[id].facts.map(([label]) => label);
    assert.ok(labels.includes('Time'), `${id}: Time`);
    assert.ok(labels.includes('Cost'), `${id}: Cost`);
  }
});

test('links go to https pages only', () => {
  for (const [id, guide] of Object.entries(GUIDES)) {
    for (const part of guide.parts) {
      for (const step of part.steps) {
        if (step.link) assert.match(step.link.href, /^https:\/\/[a-z0-9.-]+\//i, `${id}: ${step.link.href}`);
      }
    }
  }
});

test('guide text is plain: no HTML and no scripts', () => {
  const text = JSON.stringify(GUIDES);
  // Placeholders such as <region> are fine: React shows them as text. Real tags are not.
  const tags = /<\/?(script|style|iframe|img|a|div|span|svg|link|object|embed|form|input)\b/i;
  const handlers = /\bon[a-z]+\s*=/i;
  assert.doesNotMatch(text, tags, 'looks like HTML');
  assert.doesNotMatch(text, handlers, 'looks like an event handler');
  assert.doesNotMatch(text, /javascript:/i);
});

test('a guide never contains something that looks like a real key', () => {
  const text = JSON.stringify(GUIDES);
  assert.doesNotMatch(text, /AIza[0-9A-Za-z_-]{30,}/);
  assert.doesNotMatch(text, /rzp_(test|live)_[0-9A-Za-z]{10,}/);
  assert.doesNotMatch(text, /AKIA[0-9A-Z]{12,}/);
});

test('trouble and fill rows are pairs', () => {
  for (const [id, guide] of Object.entries(GUIDES)) {
    for (const row of [...(guide.trouble ?? []), ...(guide.fill ?? [])]) assert.equal(row.length, 2, `${id}: ${row[0]}`);
  }
});

test('the guides name no vendor, seller or shop-owner features', () => {
  assert.doesNotMatch(JSON.stringify(GUIDES), /\b(seller|vendor|KYC)\b/i);
});
