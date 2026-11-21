# Bobine : politique de confidentialité

*Dernière mise à jour : 14 novembre 2026*

Bobine est un lecteur IPTV. Il ne fournit aucune chaîne, aucun film, aucune série ni aucune playlist : chaque utilisateur y ajoute sa propre source. Cette page décrit les données que Bobine traite, sur ordinateur (Windows, macOS, Linux) comme sur Android TV.

## Ce qui reste sur l'appareil

Par défaut, tout reste sur l'appareil, dans le dossier privé de l'application :

- les sources ajoutées (adresse du serveur, identifiant et mot de passe Xtream Codes, ou adresse de la playlist M3U) ;
- les chaînes, films, séries et le guide TV importés depuis ces sources ;
- les profils, favoris, reprises de lecture, épisodes vus, chaînes récentes, rappels et réglages ;
- le code parental.

Bobine ne contient ni publicité, ni mesure d'audience, ni outil de suivi, ni rapport de plantage envoyé automatiquement.

## Les connexions que fait Bobine

- **Aux sources ajoutées par l'utilisateur** : pour importer les listes et lire les flux, Bobine se connecte aux serveurs que l'utilisateur a lui-même saisis, avec ses identifiants.
- **À The Movie Database (TMDB)**, seulement si l'utilisateur y a saisi sa propre clé : pour afficher résumés, distributions et images, Bobine envoie le titre et l'année du film ou de la série consultés. Voir la [politique de TMDB](https://www.themoviedb.org/privacy-policy).

## Le compte Bobine (facultatif)

Bobine s'utilise sans compte. Le compte sert uniquement à synchroniser ses données entre plusieurs appareils.

- **Données transmises** : l'adresse e-mail (pour se connecter et recevoir les codes de confirmation ou de nouveau mot de passe) et les données synchronisées.
- **Chiffrement de bout en bout** : les données synchronisées (sources et identifiants compris, profils, favoris, reprises, réglages) sont chiffrées sur l'appareil (AES-256-GCM) avec une clé tirée du mot de passe de l'utilisateur. Le serveur ne reçoit ni ce mot de passe en clair, ni les identifiants IPTV, ni la liste de ce qui est regardé : seulement des éléments chiffrés qu'il ne peut pas lire.
- **Hébergement** : le compte et les données chiffrées sont hébergés chez Supabase (supabase.com).
- **Transport** : toutes les connexions au compte passent en HTTPS.

## Supprimer ses données

- **Sans compte** : désinstaller Bobine, ou effacer ses données depuis les paramètres de l'appareil, supprime tout.
- **Avec un compte** : *Paramètres → Compte → Supprimer le compte* supprime le compte et toutes les données synchronisées, immédiatement et définitivement. Les données de l'appareil restent jusqu'à la désinstallation.

## Enfants

Bobine ne s'adresse pas aux enfants. Un profil Enfants et un code parental permettent de limiter ce que les plus jeunes voient sur l'appareil.

## Contact

Pour toute question sur cette politique, ou pour signaler un contenu, ouvrir une demande sur le dépôt du projet : https://github.com/Weder77/Bobine/issues
