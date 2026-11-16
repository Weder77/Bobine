# Signature des mises à jour

Bobine installe ses mises à jour en silence. Pour qu'un installateur déposé
sur une release sans la clé (fichier remplacé, release faite à la main) ne
puisse pas être installé, l'installateur est signé avec une clé Ed25519
dont la moitié publique est intégrée à l'application.

**État : en place depuis la 1.7.0.** La clé publique est dans
`kUpdatePublicKey` (`lib/core/version.dart`), le secret
`BOBINE_UPDATE_SIGNING_KEY` est dans l'environnement `PRD`, et chaque release
publie `Bobine-Setup-x.y.z.exe.sig` à côté de l'installateur (1.7.0, 1.7.1).
Une version 1.7 ou plus récente refuse un installateur sans signature valide.

Limite : la signature est faite par le build GitHub. Elle ne protège pas d'un
build lui-même compromis (workflow modifié par un accès volé, étape tierce
piégée) : le job signe ce que le build a produit. Pour s'en protéger aussi, il
faut signer hors de GitHub, sur ton ordinateur, l'installateur téléchargé
depuis l'artefact du build (mêmes commandes que dans le workflow), puis
déposer le `.sig` sur la release.

Une version sans clé publique (`kUpdatePublicKey` vide) vérifie seulement
que l'installateur vient des releases du dépôt sur github.com, en https, avec
l'empreinte SHA-256 donnée par GitHub.

## Mise en place (déjà faite, gardée pour référence)

1. Créer la paire de clés, sur ton ordinateur, hors du dépôt :

   ```bash
   openssl genpkey -algorithm ed25519 -out bobine-update.pem
   ```

2. Récupérer la clé publique :

   ```bash
   openssl pkey -in bobine-update.pem -pubout -outform DER | tail -c 32 | base64
   ```

   La coller dans `kUpdatePublicKey` (`lib/core/version.dart`).

3. Ajouter la clé privée comme secret de l'environnement `PRD` (Settings →
   Environments → PRD → Add environment secret), sous le nom
   `BOBINE_UPDATE_SIGNING_KEY`, avec tout le contenu de `bobine-update.pem`
   (lignes `BEGIN` et `END` comprises). Seul le job de publication déclare
   cet environnement : les autres jobs ne voient pas la clé. Dans les
   réglages de l'environnement, limiter « Deployment branches and tags » à
   `main` et aux tags `v*` empêche une autre branche de s'en servir.

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
