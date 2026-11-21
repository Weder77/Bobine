// The account session, kept in this tab only (sessionStorage): it ends when
// the tab closes. The password and the keys are never kept.

const KEY = 'bobine.compte.session';
const FLASH = 'bobine.compte.message';

function read(key) {
  try {
    return JSON.parse(sessionStorage.getItem(key));
  } catch {
    return null;
  }
}

function write(key, value) {
  try {
    if (value == null) sessionStorage.removeItem(key);
    else sessionStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Storage refused (private mode…): the session lasts as long as the page.
  }
}

let memory = null;

export function saveSession(session) {
  memory = session;
  write(KEY, session);
}

export function clearSession() {
  memory = null;
  write(KEY, null);
}

/** The session, refreshed when it is about to expire; null when signed out. */
export async function currentSession(api) {
  let session = memory ?? read(KEY);
  if (!session?.accessToken) return null;
  if (session.expiresAt - Date.now() < 2 * 60 * 1000) {
    try {
      session = await api.refresh(session.refreshToken);
    } catch (e) {
      if (e.network) throw e;
      clearSession();
      return null;
    }
  }
  saveSession(session);
  return session;
}

/** A message for the next page (after a sign-out, a password change…). */
export function setFlash(text, kind = 'ok') {
  write(FLASH, { text, kind });
}

export function takeFlash() {
  const flash = read(FLASH);
  write(FLASH, null);
  return flash;
}
