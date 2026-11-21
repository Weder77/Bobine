// What the account pages do, on top of the service (supabase.js) and the keys
// (keys.js). Kept free of the page so it is tested (test/account.test.mjs).

import { deriveKeys, normalizeEmail } from './keys.js';
import { ApiError } from './supabase.js';

/** Same rule as the app when an account is created. */
export const MIN_PASSWORD = 8;

function checkNew(password) {
  if (String(password).length < MIN_PASSWORD) {
    throw new ApiError(`Le mot de passe doit faire au moins ${MIN_PASSWORD} caractères.`, { code: 'weak_password' });
  }
}

// What the account held was encrypted with the old password: it is emptied,
// then the first device signed in with the new one sends its data again.
// Emptied first, as in the app (SyncService.resetPassword): if setting the
// password fails, the old password still opens what the old password
// encrypted. Then every session ends, devices included, so none goes on
// sending data encrypted with the old password.
async function replacePassword(api, session, secret) {
  await api.wipe(session.accessToken);
  await api.setPassword(session.accessToken, secret);
  try {
    await api.signOut(session.accessToken, 'global');
  } catch {
    // Changed anyway; the devices are asked for the password at their next
    // refresh of a session.
  }
}

export function createAccount(api, derive = deriveKeys) {
  return {
    async signIn(email, password) {
      const address = normalizeEmail(email);
      const { authSecret } = await derive(address, password);
      return api.signIn(address, authSecret);
    },

    async changePassword(email, current, next) {
      if (current === next) {
        throw new ApiError("Le nouveau mot de passe doit être différent de l'actuel.", { code: 'same_password' });
      }
      checkNew(next);
      const address = normalizeEmail(email);
      let session;
      try {
        session = await api.signIn(address, (await derive(address, current)).authSecret);
      } catch (e) {
        if (e.code === 'invalid_credentials' || e.code === 'invalid_grant') {
          throw new ApiError('Mot de passe actuel incorrect.', { code: e.code, status: e.status });
        }
        throw e;
      }
      await replacePassword(api, session, (await derive(address, next)).authSecret);
    },

    /** Sends the code used for a forgotten password, or to delete without it. */
    async sendCode(email) {
      await api.recover(normalizeEmail(email));
    },

    async resetPassword(email, code, next) {
      checkNew(next);
      const address = normalizeEmail(email);
      const session = await api.verify(address, code, 'recovery');
      await replacePassword(api, session, (await derive(address, next)).authSecret);
    },

    async deleteWithCode(email, code) {
      const session = await api.verify(normalizeEmail(email), code, 'recovery');
      await api.deleteAccount(session.accessToken);
    },

    async deleteSignedIn(session, typedEmail) {
      if (normalizeEmail(typedEmail) !== normalizeEmail(session.email)) {
        throw new ApiError("L'adresse tapée n'est pas celle du compte.", { code: 'confirmation' });
      }
      await api.deleteAccount(session.accessToken);
    },

    /** What the server knows of the account: never its content, which stays encrypted. */
    async overview(session) {
      const [user, summary] = await Promise.all([
        api.user(session.accessToken),
        // A server without the summary yet (migration not applied): the page
        // shows the account without the counts.
        api.summary(session.accessToken).catch((e) => {
          if (e.status === 401) throw e;
          return null;
        }),
      ]);
      return {
        email: user?.email ?? session.email,
        createdAt: user?.created_at ? new Date(user.created_at) : null,
        items: summary ? Number(summary.items) : null,
        bytes: summary ? Number(summary.bytes) : null,
        lastChange: summary?.last_change ? new Date(Number(summary.last_change)) : null,
      };
    },

    async signOut(session, scope = 'local') {
      await api.signOut(session.accessToken, scope);
    },
  };
}
