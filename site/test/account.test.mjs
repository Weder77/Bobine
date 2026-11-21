import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createAccount } from '../src/lib/account.js';
import { ApiError } from '../src/lib/supabase.js';

// Keys as "secret:<email>:<password>", fast and easy to read in the calls.
const derive = async (email, password) => ({ authSecret: `secret:${email}:${password}` });

function fakeApi(overrides = {}) {
  const calls = [];
  const session = (email) => ({ accessToken: `token:${email}`, refreshToken: 'r', expiresAt: Date.now() + 3600e3, email });
  const api = {
    signIn: async (email, secret) => (calls.push(['signIn', email, secret]), session(email)),
    verify: async (email, code, type) => (calls.push(['verify', email, code, type]), session(email)),
    recover: async (email) => calls.push(['recover', email]),
    wipe: async (token) => calls.push(['wipe', token]),
    setPassword: async (token, secret) => calls.push(['setPassword', token, secret]),
    signOut: async (token, scope) => calls.push(['signOut', token, scope]),
    deleteAccount: async (token) => calls.push(['deleteAccount', token]),
    user: async () => ({ email: 'camille@exemple.fr', created_at: '2026-03-12T10:00:00Z' }),
    summary: async () => ({ items: 1284, bytes: 3250585, last_change: 1795000000000 }),
    ...overrides,
  };
  return { api, calls };
}

test('signing in sends the derived secret, never the password', async () => {
  const { api, calls } = fakeApi();
  await createAccount(api, derive).signIn('  Camille@Exemple.FR ', 'motdepasse');
  assert.deepEqual(calls, [['signIn', 'camille@exemple.fr', 'secret:camille@exemple.fr:motdepasse']]);
});

test('a password change checks the current one, empties the account, then sets the new one', async () => {
  const { api, calls } = fakeApi();
  await createAccount(api, derive).changePassword('camille@exemple.fr', 'ancien-mdp', 'nouveau-mdp');
  assert.deepEqual(calls, [
    ['signIn', 'camille@exemple.fr', 'secret:camille@exemple.fr:ancien-mdp'],
    // Emptied first, as in the app: if setting the password fails, the old
    // password still opens what it encrypted.
    ['wipe', 'token:camille@exemple.fr'],
    ['setPassword', 'token:camille@exemple.fr', 'secret:camille@exemple.fr:nouveau-mdp'],
    ['signOut', 'token:camille@exemple.fr', 'global'],
  ]);
});

test('a wrong current password changes nothing', async () => {
  const { api, calls } = fakeApi({
    signIn: async () => {
      throw new ApiError('E-mail ou mot de passe incorrect.', { code: 'invalid_credentials', status: 400 });
    },
  });
  await assert.rejects(createAccount(api, derive).changePassword('camille@exemple.fr', 'faux', 'nouveau-mdp'), {
    message: 'Mot de passe actuel incorrect.',
  });
  assert.deepEqual(calls, []);
});

test('the same password, or a short one, is refused before anything is sent', async () => {
  const { api, calls } = fakeApi();
  const account = createAccount(api, derive);
  await assert.rejects(account.changePassword('camille@exemple.fr', 'pareil-mdp', 'pareil-mdp'), { code: 'same_password' });
  await assert.rejects(account.changePassword('camille@exemple.fr', 'ancien-mdp', 'court'), { code: 'weak_password' });
  await assert.rejects(account.resetPassword('camille@exemple.fr', '123456', 'court'), { code: 'weak_password' });
  assert.deepEqual(calls, []);
});

test('a forgotten password is replaced with the code, the account emptied first', async () => {
  const { api, calls } = fakeApi();
  await createAccount(api, derive).resetPassword('Camille@exemple.fr', ' 123456 ', 'nouveau-mdp');
  assert.deepEqual(calls, [
    ['verify', 'camille@exemple.fr', ' 123456 ', 'recovery'],
    ['wipe', 'token:camille@exemple.fr'],
    ['setPassword', 'token:camille@exemple.fr', 'secret:camille@exemple.fr:nouveau-mdp'],
    ['signOut', 'token:camille@exemple.fr', 'global'],
  ]);
});

test('the account can be deleted with a code, without the password', async () => {
  const { api, calls } = fakeApi();
  const account = createAccount(api, derive);
  await account.sendCode(' Camille@exemple.fr');
  await account.deleteWithCode('Camille@exemple.fr', '654321');
  assert.deepEqual(calls, [
    ['recover', 'camille@exemple.fr'],
    ['verify', 'camille@exemple.fr', '654321', 'recovery'],
    ['deleteAccount', 'token:camille@exemple.fr'],
  ]);
});

test('a signed-in deletion needs the address typed again', async () => {
  const { api, calls } = fakeApi();
  const account = createAccount(api, derive);
  const session = { accessToken: 'token:camille@exemple.fr', email: 'camille@exemple.fr' };
  await assert.rejects(account.deleteSignedIn(session, 'autre@exemple.fr'), { code: 'confirmation' });
  assert.deepEqual(calls, []);
  await account.deleteSignedIn(session, ' Camille@Exemple.fr ');
  assert.deepEqual(calls, [['deleteAccount', 'token:camille@exemple.fr']]);
});

test('the overview shows the counts, or none when the server has no summary yet', async () => {
  const { api } = fakeApi();
  const session = { accessToken: 't', email: 'camille@exemple.fr' };
  const overview = await createAccount(api, derive).overview(session);
  assert.equal(overview.email, 'camille@exemple.fr');
  assert.equal(overview.items, 1284);
  assert.equal(overview.bytes, 3250585);
  assert.equal(overview.createdAt.toISOString(), '2026-03-12T10:00:00.000Z');
  assert.equal(overview.lastChange.getTime(), 1795000000000);

  const { api: older } = fakeApi({
    summary: async () => {
      throw new ApiError('Could not find the function', { code: 'PGRST202', status: 404 });
    },
  });
  const partial = await createAccount(older, derive).overview(session);
  assert.equal(partial.items, null);
  assert.equal(partial.email, 'camille@exemple.fr');
});

test('an expired session in the overview is not hidden', async () => {
  const lost = new ApiError('Session expirée : reconnecte-toi.', { status: 401 });
  const { api } = fakeApi({ summary: async () => Promise.reject(lost), user: async () => Promise.reject(lost) });
  await assert.rejects(createAccount(api, derive).overview({ accessToken: 't' }), lost);
});
