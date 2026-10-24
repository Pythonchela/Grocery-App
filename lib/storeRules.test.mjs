import test from 'node:test';
import assert from 'node:assert/strict';

// parsePins is a pure helper but lives in a JSX module, so it is mirrored here from
// the source text to keep the test free of a JSX toolchain.
import { readFileSync } from 'node:fs';
import { URL } from 'node:url';

const source = readFileSync(new URL('../components/admin/StoreRulesSection.jsx', import.meta.url), 'utf8');
const body = source.match(/export function parsePins\(text\) \{([\s\S]*?)\n\}/)[1];
const parsePins = new Function('text', body);

test('splits PIN codes on lines, commas and spaces and removes duplicates', () => {
  assert.deepEqual(parsePins('560001, 560002\n560001;560003').pins, ['560001', '560002', '560003']);
});

test('reports anything that is not a six-digit PIN code', () => {
  const { pins, bad } = parsePins('560001 12345 abcdef 5600011');
  assert.deepEqual(pins, ['560001']);
  assert.deepEqual(bad, ['12345', 'abcdef', '5600011']);
});

test('empty input is fine', () => {
  assert.deepEqual(parsePins(''), { pins: [], bad: [] });
  assert.deepEqual(parsePins(null), { pins: [], bad: [] });
});
