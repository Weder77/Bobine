# Site de Bobine

Le site vitrine de Bobine et son espace compte : voir l'état de son compte, changer son mot de passe, supprimer son compte
(avec le mot de passe, ou avec un code reçu par e-mail). Un site statique fait avec [Astro](https://astro.build), sans serveur :
le navigateur parle directement au service du compte (Supabase), comme l'appli.

```bash
cd site
npm install
npm run dev       # http://localhost:4321
npm test          # dérivation des clés, client Supabase, parcours du compte
npm run build     # le site dans dist/, à publier tel quel
```

## Ce qu'il faut savoir

- **Les clés du compte** sont calculées dans le navigateur, exactement comme l'appli (`src/lib/keys.js` ↔
  `lib/sync/sync_crypto.dart`) : le mot de passe n'est jamais envoyé. Les deux sont vérifiés contre
  `test/fixtures/sync_key_vectors.json`, écrit par une troisième implémentation (`tool/sync_key_vectors.py`). Changer la
  dérivation d'un côté sans l'autre fait échouer les tests.
- **Changer le mot de passe vide le compte**, comme « Mot de passe oublié » dans l'appli : les données étaient chiffrées
  avec l'ancien. Le compte est vidé, le mot de passe changé, puis toutes les sessions sont fermées ; le premier appareil
  reconnecté renvoie ses données (`src/lib/account.js`).
- **L'état du compte** vient de la fonction `account_summary` (`supabase/migrations/20261121120000_account_summary.sql`) :
  à appliquer sur le projet Supabase. Sans elle, la page montre le compte sans les chiffres.
- **Rien d'extérieur** : polices (`assets/fonts`), captures (`docs/screenshots`), icône et politique de confidentialité
  (`docs/confidentialite.md`) viennent du dépôt. La CSP de chaque page n'autorise que le site et Supabase ; aucun cookie,
  aucune mesure d'audience.
- **Le fil** de la page d'accueil se déroule au défilement (`src/scripts/thread.js`, tracé dans `src/data/thread.js`). Il
  est entier sans JavaScript ou quand l'appareil demande moins de mouvement.

## Avant la mise en ligne

- Remplir les mentions légales (`src/pages/mentions-legales.astro`, parties entre crochets).
- Renseigner `site` dans `astro.config.mjs` avec le domaine.
- Mettre le lien Google Play des boutons Android TV une fois l'appli publiée.
- Dans la Play Console : l'adresse de `/confidentialite/` comme politique de confidentialité, et celle de
  `/compte/suppression/` comme adresse Web de suppression du compte.
