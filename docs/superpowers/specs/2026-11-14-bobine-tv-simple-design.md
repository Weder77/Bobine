# Bobine TV : interface simple pour la télé

*Design validé le 14/11/2026 : maquette « Bobine TV » (Claude Design) + propositions acceptées (« B, et fonce avec tes propositions »).*

## Pourquoi

Sur la télé, Bobine affichait la version ordinateur agrandie : trop de réglages et d'écrans, des petits éléments, une navigation à la télécommande difficile (débordements, liens inaccessibles). L'utilisateur veut **un truc vraiment simple : l'essentiel, des gros boutons, et c'est tout**.

## Objectifs

- Sur la télé uniquement (`Device.isTv`), une interface dédiée qui reprend la maquette : 1920 × 1080, marges de 96 px, Big Shoulders / Geist / Geist Mono, fond `#0D0C0B`, vermillon `#FF5A36`, élément sélectionné = blanc (pastilles, boutons, lignes) ou anneau blanc de 4 px + agrandissement (vignettes).
- **Une seule règle de navigation** : les flèches vont à l'élément le plus proche dans la direction (même calcul que la maquette), OK active, Retour remonte.
- Toutes les données sont les vraies (sources, guide, reprises, favoris, profils, réglages) ; lecteur, import, synchro et base de données inchangés.

## Non-objectifs (anti-objectifs)

- Ne pas toucher l'interface ordinateur (Windows, macOS, Linux).
- Pas de multi-écran, cast, enregistrements, catalogue en grille, catégories à gérer, recherche, sauvegarde, diagnostic ni pages de réglages détaillées sur la télé.
- Pas de deuxième lecteur vidéo : le moteur reste `PlayerScreen` / `PlayerService`, seul son habillage change sur la télé.

## Écrans (repris de la maquette)

**Barre du haut** (cachée dans le lecteur) : logo, onglets en pastilles Accueil · Direct · Guide TV · Films · Séries, puis roue Réglages, heure, pastille du profil. Arriver sur un onglet l'affiche tout de suite ; Bas entre dans la page (son premier élément).

**Accueil / Films / Séries** : grande image de fond (900 px de haut, dégradés) ; en haut à gauche, l'élément sélectionné : surtitre vermillon, titre géant, « ★ note · année · genre · durée », résumé sur 2 lignes ; tant qu'on est sur le haut de page, boutons **Lecture** et **Ma liste** (favori) ; sur une reprise ou une chaîne, une barre de progression remplace les boutons. Rangées en dessous (la rangée sélectionnée remonte en haut de la zone) :
- Accueil : *En direct maintenant* (chaînes), *Reprendre*, *Top 10 aujourd'hui*, *Ajoutés récemment*.
- Films : *Nouveautés*, *Ma liste* (si non vide), *Top 10 des films*, quelques catégories du fournisseur, *Les mieux notés*.
- Séries : *Reprendre tes séries*, *Nouveautés*, *Ma liste* (si non vide), *Top 10 des séries*, quelques catégories.
- Vignettes : chaîne / reprise 400 × 225, affiche 200 × 300, Top 10 = grand chiffre détouré + affiche.
- OK : film → lecture (reprise si commencé) ; série → **page série** ; chaîne → direct ; reprise → reprend.

**Page série (choix B)** : même haut de page (image, titre, infos, résumé) ; boutons **Reprendre S02E04** (ou *Lecture S01E01*) et **Ma liste** ; une rangée de pastilles **Saison 1, Saison 2…** ; une rangée d'épisodes en grandes vignettes (image, « E04 · titre », durée, progression, vu). OK sur un épisode → lecture. Retour → page précédente.

**Direct** : titre DIRECT + « N chaînes · date heure » ; pastilles **Toutes, Favoris**, puis les groupes du fournisseur (rangée qui défile) ; mosaïque 4 colonnes (411 × 231) : logo (monogramme si pas de logo), nom, numéro, programme en cours, progression, heure de fin, « Ensuite … » sur la tuile sélectionnée. Pas d'image du flux : fond coloré dérivé de la chaîne. OK → direct.

**Guide TV** : en haut, le programme sélectionné (chaîne, horaire, statut « En cours · reste … » / « Dans … » / « Terminé », titre, description, action OK : *Regarder* / *Voir la chaîne* / *Me le rappeler* / *Retirer le rappel*, rappel actif) et son visuel ; grille : colonne chaînes 300 px, 12 px par minute, repères toutes les 30 min, ligne et heure « maintenant » en vermillon, cases blanches quand sélectionnées. OK : en cours ou passé → direct ; à venir → rappel.

**Réglages** : liste de lignes de 88 px, ← → change la valeur (flèches visibles sur la ligne sélectionnée), OK sur une action ; à droite, l'aide de la ligne et une carte « source » (nom, état, dernière mise à jour, version). Lignes : Profil · Qualité vidéo · Langue audio · Sous-titres · Épisode suivant automatique · Contrôle parental · **Source** (← → change de source ; OK → ajouter une source ou se connecter) · Actualiser les chaînes.

**Lecteur (habillage télé)** : en haut, logo + nom + « Chaîne N » + EN DIRECT (direct) ou surtitre (film/épisode) ; en bas, genre, titre géant, progression (horaires ou temps écoulé / restant), « Ensuite … » ; aides : ▲▼ *Changer de chaîne* (direct) ou ◀▶ *10 secondes*, OK *Pause/Lecture*, Retour *Quitter*. Les contrôles s'effacent après 5 s sans touche ; en pause, rond « pause » au centre. Pas de boutons à sélectionner.

**Bulle d'aide** au démarrage (9 s) : « ← ↑ → ↓ Naviguer · OK · Retour ».

## Retour

Dans une page → onglet en cours de la barre ; sur un onglet → Accueil ; sur l'onglet Accueil → Bobine se ferme (comportement Android normal). Page série → page précédente. Lecteur → quitte la lecture.

## Premier lancement et source

On garde l'écran actuel « Me connecter à mon compte Bobine / Ajouter une playlist sans compte » (déjà en grosses cartes) ; la ligne Source des Réglages y renvoie pour ajouter une source ou se connecter.

## Approches envisagées

1. **Habiller l'interface ordinateur** (masquer, agrandir) : déjà tenté, la navigation reste compliquée. Écarté.
2. **Interface télé dédiée sur les mêmes données et le même lecteur** : retenu. Écrans neufs dans `lib/tv/`, un moteur de navigation propre (même calcul que la maquette), rien de changé côté ordinateur.
3. **Appli télé séparée** : double maintenance de l'import, du lecteur et de la synchro. Écarté.

## Laissé au constructeur

Choix des catégories affichées (les premières non vides, non masquées, non verrouillées), nombre d'éléments par rangée (20), couleurs de fond dérivées d'un identifiant, textes d'état exacts quand une donnée manque (pas de guide, pas d'image).
