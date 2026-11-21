// Keys of a Bobine account, derived in the browser from the e-mail and the
// password, exactly as the app does (lib/sync/sync_crypto.dart):
//   master     = PBKDF2-HMAC-SHA256(password, "bobine-sync|" + email, 600 000, 32 bytes)
//   authSecret = base64url(HMAC(master, "bobine-auth")), without padding
//   encKey     = HMAC(master, "bobine-enc")
//   idKey      = HMAC(master, "bobine-id")
// The password never leaves the page: Supabase receives authSecret as the
// account's password. The site never decrypts anything, but encKey and idKey
// are derived too, so test/fixtures/sync_key_vectors.json checks all of it.

export const DEFAULT_ITERATIONS = 600000;

export function normalizeEmail(email) {
  return String(email).trim().toLowerCase();
}

const utf8 = (s) => new TextEncoder().encode(s);

function base64Url(bytes) {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

export async function deriveKeys(email, password, iterations = DEFAULT_ITERATIONS) {
  const { subtle } = globalThis.crypto;
  const pass = await subtle.importKey('raw', utf8(password), 'PBKDF2', false, ['deriveBits']);
  const salt = utf8(`bobine-sync|${normalizeEmail(email)}`);
  const master = await subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, pass, 256);
  const hmac = await subtle.importKey('raw', master, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sub = async (label) => new Uint8Array(await subtle.sign('HMAC', hmac, utf8(label)));
  return {
    authSecret: base64Url(await sub('bobine-auth')),
    encKey: await sub('bobine-enc'),
    idKey: await sub('bobine-id'),
  };
}
