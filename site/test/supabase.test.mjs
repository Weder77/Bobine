import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createApi, SUPABASE_KEY, SUPABASE_URL } from '../src/lib/supabase.js';

function recorder(status = 200, body = '') {
  const requests = [];
  const fetch = async (url, init) => {
    requests.push({ url, ...init });
    return { status, text: async () => (typeof body === 'string' ? body : JSON.stringify(body)) };
  };
  return { requests, api: createApi({ fetch }) };
}

test('calls carry the publishable key, and the session when there is one', async () => {
  const { api, requests } = recorder(204);
  await api.wipe('jeton');
  const [r] = requests;
  assert.equal(r.method, 'DELETE');
  assert.equal(r.url, `${SUPABASE_URL}/rest/v1/sync_items?rev=gte.0`);
  assert.equal(r.headers.apikey, SUPABASE_KEY);
  assert.equal(r.headers.Authorization, 'Bearer jeton');
  assert.equal(r.body, undefined);
});

test('signing in posts the secret and returns a session', async () => {
  const { api, requests } = recorder(200, { access_token: 'a', refresh_token: 'r', expires_in: 3600, user: { email: 'camille@exemple.fr' } });
  const session = await api.signIn('camille@exemple.fr', 'secret');
  assert.equal(requests[0].url, `${SUPABASE_URL}/auth/v1/token?grant_type=password`);
  assert.deepEqual(JSON.parse(requests[0].body), { email: 'camille@exemple.fr', password: 'secret' });
  assert.equal(requests[0].headers.Authorization, undefined);
  assert.equal(session.accessToken, 'a');
  assert.equal(session.email, 'camille@exemple.fr');
  assert.ok(session.expiresAt > Date.now() + 3500e3);
});

test('signing out everywhere asks for the global scope', async () => {
  const { api, requests } = recorder(204);
  await api.signOut('jeton', 'global');
  assert.equal(requests[0].url, `${SUPABASE_URL}/auth/v1/logout?scope=global`);
});

test('errors come back in French', async () => {
  await assert.rejects(recorder(400, { error_code: 'invalid_credentials' }).api.signIn('a@b.c', 's'), {
    message: 'E-mail ou mot de passe incorrect.',
    code: 'invalid_credentials',
  });
  await assert.rejects(recorder(403, { error_code: 'otp_expired' }).api.verify('a@b.c', '1', 'recovery'), {
    message: 'Code incorrect ou expiré.',
  });
  await assert.rejects(recorder(503, 'Service Unavailable').api.user('t'), { network: true });
});

test('no answer at all is a network error', async () => {
  const api = createApi({ fetch: async () => Promise.reject(new TypeError('Failed to fetch')) });
  await assert.rejects(api.recover('a@b.c'), { message: 'Pas de connexion au service du compte.', network: true });
});
