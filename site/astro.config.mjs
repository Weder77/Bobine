import { defineConfig } from 'astro/config';

import { SUPABASE_URL } from './src/lib/supabase.js';

export default defineConfig({
  // Le domaine du site, une fois choisi (liens canoniques) :
  // site: 'https://…',
  trailingSlash: 'ignore',
  build: { format: 'directory' },
  // A static site: the CSP goes in a <meta> of every page, with the hashes of
  // what Astro inlines. Nothing outside the site but the account service:
  // no font, script or image from anywhere else.
  security: {
    csp: {
      directives: [
        "default-src 'self'",
        "img-src 'self'",
        "font-src 'self'",
        `connect-src ${SUPABASE_URL}`,
        "base-uri 'none'",
        "form-action 'none'",
        "object-src 'none'",
      ],
      scriptDirective: { resources: ["'self'"] },
      styleDirective: { resources: ["'self'"] },
    },
  },
  vite: {
    // The site uses the repository's fonts (assets/fonts), screenshots and
    // privacy policy (docs/) instead of copies.
    server: { fs: { allow: ['..'] } },
  },
});
