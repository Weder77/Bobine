// The site must derive the same account keys as the app: both are checked
// against test/fixtures/sync_key_vectors.json (tool/sync_key_vectors.py).
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

import { deriveKeys, normalizeEmail } from '../src/lib/keys.js';

const vectors = JSON.parse(await readFile(new URL('../../test/fixtures/sync_key_vectors.json', import.meta.url), 'utf8'));

for (const v of vectors) {
  test(`keys of ${v.email} (${v.iterations} iterations)`, async () => {
    const keys = await deriveKeys(v.email, v.password, v.iterations);
    assert.equal(keys.authSecret, v.authSecret);
    assert.equal(Buffer.from(keys.encKey).toString('base64'), v.encKey);
    assert.equal(Buffer.from(keys.idKey).toString('base64'), v.idKey);
  });
}

test('the default iterations are those of the app', async () => {
  const v = vectors.find((x) => x.iterations === 600000);
  assert.ok(v, 'a vector with 600 000 iterations');
  assert.equal((await deriveKeys(v.email, v.password)).authSecret, v.authSecret);
});

test('addresses are compared trimmed and in lower case', () => {
  assert.equal(normalizeEmail('  Camille@Exemple.FR '), 'camille@exemple.fr');
});
