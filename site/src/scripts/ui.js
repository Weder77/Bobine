// Small helpers shared by the account pages: forms that show their errors in
// place, password fields that can be shown, the header of a signed-in page.

import { createAccount } from '../lib/account.js';
import { createApi } from '../lib/supabase.js';
import { clearSession, currentSession, setFlash, takeFlash } from './session.js';

export const api = createApi();
export const account = createAccount(api);

export const $ = (selector, root = document) => root.querySelector(selector);

export function show(el, visible = true) {
  if (el) el.hidden = !visible;
}

export function say(el, text, kind = 'error') {
  if (!el) return;
  el.textContent = text ?? '';
  el.className = `message message--${kind}`;
}

/** Runs `handler` on submit: button busy, error shown in [data-message]. */
export function onSubmit(form, handler, { busy = 'Patiente…' } = {}) {
  const button = form.querySelector('button[type="submit"]');
  const message = form.querySelector('[data-message]');
  const label = button?.innerHTML;
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    say(message, '');
    if (!form.reportValidity()) return;
    if (button) {
      button.disabled = true;
      button.textContent = busy;
    }
    try {
      await handler(new FormData(form), form);
    } catch (e) {
      say(message, e?.message || 'Une erreur est survenue.');
    } finally {
      if (button) {
        button.disabled = false;
        button.innerHTML = label;
      }
    }
  });
}

export function passwordToggles(root = document) {
  for (const button of root.querySelectorAll('[data-toggle-password]')) {
    const input = button.parentElement.querySelector('input');
    button.addEventListener('click', () => {
      const shown = input.type === 'text';
      input.type = shown ? 'password' : 'text';
      button.setAttribute('aria-label', shown ? 'Afficher le mot de passe' : 'Masquer le mot de passe');
      button.setAttribute('aria-pressed', String(!shown));
    });
  }
}

/** A field's value; passwords as typed, everything else trimmed. */
export function value(form, id) {
  const input = form.querySelector(`#${id}`);
  return input.type === 'password' || input.dataset.raw != null ? input.value : input.value.trim();
}

export function showFlash(el) {
  const flash = takeFlash();
  if (flash) say(el, flash.text, flash.kind);
}

/**
 * A page for a signed-in account: its session, or a trip to the sign-in page.
 * Fills the header (address, sign-out).
 */
export async function signedInPage({ required = true } = {}) {
  let session = null;
  try {
    session = await currentSession(api);
  } catch {
    // Offline: the page says so when it calls the service.
  }
  if (!session && required) {
    location.replace('/compte/');
    return null;
  }
  for (const el of document.querySelectorAll('[data-when="signed-in"]')) show(el, !!session);
  for (const el of document.querySelectorAll('[data-when="signed-out"]')) show(el, !session);
  const email = $('[data-account-email]');
  if (email && session) email.textContent = session.email;
  $('[data-sign-out]')?.addEventListener('click', async () => {
    try {
      await account.signOut(session);
    } catch {
      // Signed out here anyway; the server ends the session when it expires.
    }
    clearSession();
    setFlash('Tu es déconnecté.');
    location.assign('/compte/');
  });
  return session;
}
