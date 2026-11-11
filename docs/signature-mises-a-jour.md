# Signature des mises à jour

Bobine installe ses mises à jour en silence. Pour qu'une release publiée par
quelqu'un d'autre (accès GitHub volé, étape de build compromise) ne puisse pas
être installée, l'installateur peut être signé avec une clé Ed25519 dont la
moitié publique est intégrée à l'application.

Tant que la clé n'est pas configurée, l'application vérifie seulement que
l'installateur vient des releases du dépôt sur github.com, en https, avec
l'empreinte SHA-256 donnée par GitHub.

## Mise en place (une seule fois)

1. Créer la paire de clés, sur ton ordinateur, hors du dépôt :

   ```bash
   openssl genpkey -algorithm ed25519 -out bobine-update.pem
   ```

2. Récupérer la clé publique :

   ```bash
   openssl pkey -in bobine-update.pem -pubout -outform DER | tail -c 32 | base64
   ```

   La coller dans `kUpdatePublicKey` (`lib/core/version.dart`).

3. Ajouter la clé privée aux secrets du dépôt GitHub (Settings → Secrets and
   variables → Actions), sous le nom `BOBINE_UPDATE_SIGNING_KEY`, avec tout le
   contenu de `bobine-update.pem` (lignes `BEGIN` et `END` comprises).

4. Garder `bobine-update.pem` en lieu sûr (gestionnaire de mots de passe) et
   ne jamais le committer.

## Ordre de déploiement

Publie d'abord une release **signée** (le secret est en place) avant celle
qui contient la clé publique. Une version qui connaît la clé refuse tout
installateur sans signature valide : si la release suivante n'était pas
signée, les utilisateurs de cette version ne recevraient plus de mise à jour
automatique (la page de la release reste proposée).

## Ce que fait le build

Le job « Publication de la Release » calcule le SHA-256 de chaque
`Bobine-Setup-*.exe`, le signe avec la clé privée, et publie
`Bobine-Setup-*.exe.sig` à côté de l'installateur. L'application télécharge
les deux, vérifie l'empreinte puis la signature, et n'installe rien si l'une
des deux ne correspond pas.

## Changer de clé

Une version ne connaît qu'une clé. Pour en changer : publier une version
signée avec l'ancienne clé qui contient la nouvelle clé publique, puis
signer les suivantes avec la nouvelle.
