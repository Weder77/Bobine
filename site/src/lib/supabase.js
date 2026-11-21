// The account service (Supabase), called with plain fetch like the app does
// (lib/sync/supabase_api.dart). The publishable key is meant to be public:
// row level security decides what each account may read or delete.

export const SUPABASE_URL = 'https://rjgsyscvvoawfenmcnvu.supabase.co';
export const SUPABASE_KEY = 'sb_publishable_cTBVl8rFbV2vphxxzRrLcQ_EFnjzvyn';

/** An error whose message can be shown as it is (in French). */
export class ApiError extends Error {
  constructor(message, { code, status, network = false } = {}) {
    super(message);
    this.code = code;
    this.status = status;
    this.network = network;
  }
}

const MESSAGES = {
  invalid_credentials: 'E-mail ou mot de passe incorrect.',
  invalid_grant: 'E-mail ou mot de passe incorrect.',
  email_not_confirmed: "Adresse pas encore confirmée : termine l'inscription dans l'appli Bobine.",
  otp_expired: 'Code incorrect ou expiré.',
  over_email_send_rate_limit: "Trop d'e-mails envoyés : réessaie dans quelques minutes.",
  over_request_rate_limit: 'Trop de tentatives : réessaie dans quelques minutes.',
  email_address_invalid: 'Adresse e-mail invalide.',
  validation_failed: 'Adresse e-mail invalide.',
  same_password: "Le nouveau mot de passe doit être différent de l'actuel.",
  reauthentication_needed: 'Reconnecte-toi, puis réessaie.',
  refresh_token_not_found: 'Session expirée : reconnecte-toi.',
  session_not_found: 'Session expirée : reconnecte-toi.',
  user_not_found: 'Compte introuvable.',
};

export function apiError(status, json) {
  const j = json && typeof json === 'object' ? json : {};
  const code = j.error_code ?? j.error ?? j.code;
  const detail = j.msg ?? j.message ?? j.error_description;
  const known = MESSAGES[code];
  if (known) return new ApiError(known, { code, status });
  if (status === 401) return new ApiError('Session expirée : reconnecte-toi.', { code, status });
  if (status >= 500) return new ApiError('Le service du compte est indisponible pour le moment.', { code, status, network: true });
  return new ApiError(detail ? String(detail) : `Erreur du service du compte (${status}).`, { code, status });
}

function toSession(j) {
  if (!j || typeof j.access_token !== 'string') throw new ApiError('Réponse inattendue du service du compte.');
  return {
    accessToken: j.access_token,
    refreshToken: j.refresh_token,
    expiresAt: Date.now() + (j.expires_in ?? 3600) * 1000,
    email: j.user?.email ?? '',
  };
}

export function createApi({ url = SUPABASE_URL, key = SUPABASE_KEY, fetch: send = (...a) => globalThis.fetch(...a) } = {}) {
  async function call(method, path, { body, token, query } = {}) {
    const target = new URL(url + path);
    for (const [k, v] of Object.entries(query ?? {})) target.searchParams.set(k, v);
    const headers = { apikey: key, Accept: 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    let response;
    try {
      response = await send(target.href, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    } catch {
      throw new ApiError('Pas de connexion au service du compte.', { network: true });
    }
    const text = await response.text();
    let json = null;
    if (text) {
      try {
        json = JSON.parse(text);
      } catch {
        json = text;
      }
    }
    if (response.status >= 400) throw apiError(response.status, json);
    return json;
  }

  return {
    signIn: async (email, secret) =>
      toSession(await call('POST', '/auth/v1/token', { query: { grant_type: 'password' }, body: { email, password: secret } })),
    refresh: async (refreshToken) =>
      toSession(await call('POST', '/auth/v1/token', { query: { grant_type: 'refresh_token' }, body: { refresh_token: refreshToken } })),
    /** `local`: this session only; `global`: every session of the account, devices included. */
    signOut: (token, scope = 'local') => call('POST', '/auth/v1/logout', { token, query: { scope } }),
    /** Sends a code by e-mail (the "forgotten password" one). */
    recover: (email) => call('POST', '/auth/v1/recover', { body: { email } }),
    verify: async (email, code, type) => toSession(await call('POST', '/auth/v1/verify', { body: { type, email, token: String(code).trim() } })),
    user: (token) => call('GET', '/auth/v1/user', { token }),
    setPassword: (token, secret) => call('PUT', '/auth/v1/user', { token, body: { password: secret } }),
    /** Removes everything synchronised; the account stays. */
    wipe: (token) => call('DELETE', '/rest/v1/sync_items', { token, query: { rev: 'gte.0' } }),
    /** Counts only (supabase/migrations/…_account_summary.sql): the content stays encrypted. */
    summary: (token) => call('POST', '/rest/v1/rpc/account_summary', { token, body: {} }),
    deleteAccount: (token) => call('POST', '/rest/v1/rpc/delete_my_account', { token, body: {} }),
  };
}
