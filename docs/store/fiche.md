# Fiche Google Play (Android TV)

Textes et réponses à reprendre dans la Play Console. Limites de Google entre parenthèses.

## Fiche principale

**Nom de l'application** (30) : `Bobine - lecteur IPTV`

**Description courte** (80) :

> Lecteur IPTV pour la télé : direct, guide TV, films et séries de ta source.

**Description complète** (4 000) :

> Bobine est uniquement un lecteur. Il ne fournit aucune chaîne, aucun film, aucune série ni aucune playlist : vous y ajoutez votre propre source, fournie par votre fournisseur.
>
> Ajoutez un abonnement (serveur, identifiant et mot de passe) ou l'adresse d'une playlist M3U : les chaînes, les films, les séries et le guide TV sont importés automatiquement.
>
> **Direct**
> - Mosaïque des chaînes avec le programme en cours et la suite
> - Guide TV en grille, fluide même avec des milliers de chaînes
> - Zapping à la télécommande, numéro de chaîne, chaînes récentes et favorites
> - Pause et retour en arrière sur le direct
> - Multi-écran : deux chaînes côte à côte
>
> **Films et séries**
> - Reprise de lecture et « Continuer à regarder »
> - Saisons, épisodes vus, épisode suivant automatique
> - Fiches détaillées (résumé, distribution) avec votre propre clé TMDB
>
> **Lecteur**
> - Moteur vidéo libmpv : lit presque tous les flux, décodage matériel
> - Pistes audio et sous-titres, format d'image, statistiques
>
> **Compte Bobine (facultatif)**
> - Retrouvez vos sources, profils, favoris et reprises sur tous vos appareils
> - Chiffré de bout en bout : le serveur ne peut lire ni vos identifiants ni ce que vous regardez
> - Sans compte, tout reste sur la télé
>
> **Famille**
> - Profils, profil Enfants et code parental
>
> Bobine ne contient ni publicité ni outil de suivi.

**Mots à éviter** dans le nom, la description et les mots-clés : « Xtream Codes », noms de chaînes, de fournisseurs, de films ou d'événements sportifs, « gratuit », « toutes les chaînes ».

**Catégorie** : Lecteurs et éditeurs vidéo.

**Coordonnées** : une adresse e-mail de contact (obligatoire) et le site du projet.

**Règles de confidentialité** (URL) : https://github.com/Weder77/Bobine/blob/main/docs/confidentialite.md

## Éléments graphiques

| Élément | Fichier | Taille |
|---|---|---|
| Icône | `docs/store/icon-512.png` | 512 × 512 |
| Bannière Android TV | `docs/store/banner-1280x720.png` | 1280 × 720 |
| Captures Android TV | `docs/store/screenshots/` (6 faites, sur mires) | 1920 × 1080, 6 à 8 |

Les captures se font avec le faux serveur (`tool/fake_xtream.py`, médias de `tool/generate_test_media.sh`) : uniquement des mires et des titres inventés, aucun logo ni contenu réel. Écrans conseillés : accueil, Direct, Guide TV, Films, fiche d'un film, lecteur avec contrôles, multi-écran, paramètres.

## Sécurité des données (formulaire)

| Question | Réponse |
|---|---|
| L'appli collecte-t-elle ou partage-t-elle des données ? | Oui (compte facultatif) |
| Les données sont-elles chiffrées en transit ? | Oui (HTTPS) |
| L'utilisateur peut-il demander la suppression ? | Oui : dans l'appli (*Paramètres → Compte → Supprimer le compte*) |
| **Infos personnelles → Adresse e-mail** | Collectée, non partagée. Facultative. Finalité : gestion du compte |
| **Fichiers et documents / Autres contenus** (données synchronisées) | Collectées, non partagées, chiffrées de bout en bout. Facultatives. Finalité : fonctionnalité de l'appli |
| Données de localisation, contacts, identifiants publicitaires, historique Web… | Non |
| Données envoyées à TMDB | Titre et année du contenu consulté, seulement avec la clé TMDB de l'utilisateur. Ce ne sont pas des données personnelles : à ne pas déclarer, mais à mentionner dans la politique (fait) |

Google demande aussi une **adresse Web de suppression du compte**. Les instructions sont dans la politique de confidentialité, section « Supprimer ses données ».

## Autres déclarations

- **Classification du contenu (IARC)** : appli de lecture multimédia, aucun contenu fourni. Pas de violence, de contenu sexuel, de jeux d'argent, d'achats, ni d'échanges entre utilisateurs.
- **Public cible** : 18 ans et plus (n'attire pas les enfants).
- **Publicités** : non.
- **Accès à l'appli** : aucune connexion n'est exigée. Pour les testeurs de Google, fournir une playlist M3U de démonstration libre de droits (par exemple des flux de test publics), sans contenu protégé.
- **Applis d'actualités, santé, finance** : non concernée.
- **Appli gouvernementale** : non.

## Réclamations de droits d'auteur

Bobine ne fournit aucun contenu. Une réclamation concerne la source ajoutée par l'utilisateur, pas l'appli. Si le Play Store refuse l'appli au titre de la propriété intellectuelle, l'appel s'appuie sur ces points :

- aucune source, playlist ou adresse de fournisseur livrée avec l'appli ;
- aucune promotion de contenus protégés dans la fiche ;
- captures faites uniquement sur des mires de test ;
- l'avertissement « Bobine est un lecteur : il ne fournit aucun contenu » est affiché dès le premier écran.
