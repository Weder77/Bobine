# Bobine : politique de confidentialité

*Dernière mise à jour : 21 novembre 2026*

Bobine est un lecteur IPTV. Il ne fournit aucun contenu : chaque utilisateur y ajoute sa propre source. Cette page décrit les données que Bobine traite, sur ordinateur (Windows, macOS, Linux) comme sur Android TV, ainsi que sur son site.

## Ce qui reste sur l'appareil

Par défaut, tout reste sur l'appareil, dans le dossier privé de l'application :

- les sources ajoutées (adresse du serveur avec son identifiant et son mot de passe, ou adresse de la liste de chaînes) ;
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
- **Chiffrement de bout en bout** : les données synchronisées (sources et identifiants compris, profils, favoris, reprises, réglages) sont chiffrées sur l'appareil (AES-256-GCM) avec une clé tirée du mot de passe de l'utilisateur. Le serveur ne reçoit ni ce mot de passe en clair, ni les identifiants des sources, ni la liste de ce qui est regardé : seulement des éléments chiffrés qu'il ne peut pas lire.
- **Hébergement** : le compte et les données chiffrées sont hébergés chez Supabase (supabase.com).
- **Transport** : toutes les connexions au compte passent en HTTPS.

## Le site de Bobine

Le site de Bobine est [getbobine.app](https://getbobine.app).

- **Ni cookie, ni suivi** : le site ne dépose aucun cookie et n'utilise ni mesure d'audience, ni outil de suivi, ni ressource d'un autre site (ses polices et ses images viennent du site lui-même).
- **Espace compte** : pour voir l'état de son compte, changer son mot de passe ou supprimer son compte, on s'y connecte avec l'adresse et le mot de passe du compte Bobine. Comme dans l'appli, les clés sont calculées dans le navigateur : le mot de passe n'est pas envoyé. La session reste dans l'onglet et s'efface quand il se ferme.
- **Ce qui s'affiche** : seulement ce que le serveur connaît (l'adresse e-mail, la date de création du compte, le nombre d'éléments synchronisés, la place qu'ils prennent et la date du dernier changement). Le contenu, chiffré, n'est pas lisible sur le site.

## Supprimer ses données

- **Sans compte** : désinstaller Bobine, ou effacer ses données depuis les paramètres de l'appareil, supprime tout.
- **Avec un compte, dans l'appli** : *Paramètres → Compte → Supprimer le compte* supprime le compte et toutes les données synchronisées, immédiatement et définitivement. Les données de l'appareil restent jusqu'à la désinstallation.
- **Avec un compte, sans l'appli** : la page [Supprimer mon compte](https://getbobine.app/compte/suppression/) du site fait de même, avec le mot de passe du compte ou, s'il est oublié, avec un code reçu par e-mail.

## Enfants

Bobine ne s'adresse pas aux enfants. Un profil Enfants et un code parental permettent de limiter ce que les plus jeunes voient sur l'appareil.

## Contact

Pour toute question sur cette politique, ou pour signaler un contenu, ouvrir une demande sur le dépôt du projet : https://github.com/Weder77/Bobine/issues
