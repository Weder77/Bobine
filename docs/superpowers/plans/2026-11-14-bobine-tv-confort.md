# Bobine TV : options, recherche et confort — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** sur la télé, choisir l'audio et les sous-titres pendant la lecture, rechercher, ouvrir la liste des chaînes depuis le direct, gérer favoris / Ma liste / Reprendre à la télécommande, reprendre une série au bon épisode, nettoyer les noms de catégories, et refaire les captures du Play Store.

**Architecture:** un appui long sur OK (≥ 500 ms) devient un geste du moteur `TvFocus` (`onLongOk`). Une feuille d'options télé (`showTvSheet`, panneau à droite, sa propre `TvFocusScope`) sert aux pistes, aux options de chaîne, à la liste des chaînes et aux actions d'un élément. La recherche est un onglet de plus (`TvTab.search`, loupe à côté de la roue). Tout reste derrière `Device.isTv` ; l'ordinateur ne change pas.

**Tech Stack:** Flutter 3.47.9, media_kit (pistes `AudioTrack` / `SubtitleTrack`), flutter_test.

**Spec:** demandes de l'utilisateur (conversation du 2026-11-14) : « fais 2 3 4, fais les confort aussi » sur la liste : 2 captures Play Store, 3 audio / sous-titres dans le lecteur, 4 recherche, 7 page série → épisode à reprendre, 8 chaînes favorites depuis la télé, 9 retirer de Reprendre, 10 noms de catégories nettoyés, 11 liste des chaînes dans le lecteur du direct.

## Global Constraints

- Textes en français, commentaires en anglais, lignes de 120 caractères, `dart format -l 120`.
- Sur la télé uniquement (`Device.isTv`) ; aucun changement de comportement sur ordinateur.
- Style de la maquette : `TvColors`, `tvText` / `tvTitle` / `tvKicker`, scène 1920 × 1080 (`TvStage`).
- Contrôle parental : ce que `Repository` cache (catégories verrouillées, contenus masqués) n'apparaît nulle part, y compris dans la recherche.
- Captures : uniquement le faux serveur (`tool/fake_xtream.py`) et ses mires, 1920 × 1080.

## Review Focus

- Appui long sur OK sur un élément sans `onLongOk` : OK agit tout de suite à l'appui, comme avant (aucune latence ajoutée) — test dans la tâche 1.
- Liste des chaînes avec des centaines de chaînes et la chaîne en cours loin dans la liste : elle s'ouvre sur la chaîne en cours (déjà construite et sélectionnée) — test dans la tâche 2.
- Flux sans piste audio alternative ni sous-titres : la feuille montre « Audio : piste unique » / « Sous-titres : Désactivés » sans planter — test dans la tâche 3 (`tvTrackOptions` avec listes vides).
- Recherche avec une requête vide ou d'une lettre, ou sans résultat : message clair, pas de requête lourde — test dans la tâche 6.
- Catégorie dont le nom n'est qu'un préfixe (« FR | ») : le nom d'origine reste — test dans la tâche 5.

---

### Tâche 1 : appui long sur OK

**Files:**
- Modify: `lib/tv/tv_focus.dart` (`TvFocusable.onLongOk`, gestion OK dans `_TvFocusScopeState._onKey`)
- Test: `test/tv_focus_test.dart`

**Interfaces:**
- Produces: `TvFocusable({..., VoidCallback? onLongOk})` ; `TvFocusController.activate()` inchangé.

- [ ] Tests : (a) élément avec `onLongOk`, OK enfoncé 600 ms puis relâché → `onLongOk` une fois, `onOk` jamais ; (b) même élément, appui bref (relâché à 100 ms) → `onOk` une fois au relâchement ; (c) élément sans `onLongOk` → `onOk` dès l'appui (avant le relâchement) ; (d) des répétitions de touche pendant l'appui ne déclenchent qu'un seul `onLongOk`.
- [ ] Les voir échouer.
- [ ] Implémenter : à l'appui (KeyDown) d'une touche OK, si l'élément a `onLongOk`, armer un `Timer(500 ms)` qui appelle `onLongOk` ; au relâchement (KeyUp) avant le minuteur, appeler `onOk`. Une répétition (KeyRepeat) ne fait rien. Les relâchements de OK sont gardés (handled) quand un appui était armé.
- [ ] Tests verts, commit « Bobine TV : appui long sur OK ».

### Tâche 2 : feuille d'options télé

**Files:**
- Create: `lib/tv/tv_sheet.dart`
- Test: `test/tv_sheet_test.dart`

**Interfaces:**
- Produces:
  - `class TvSheetOption { const TvSheetOption(this.label, {this.detail, this.icon, this.selected = false, this.leading, required this.onPick}); }` (`leading` : un widget à gauche, ex. logo de chaîne)
  - `class TvSheetSection { const TvSheetSection(this.title, this.options); final String? title; final List<TvSheetOption> options; }`
  - `Future<void> showTvSheet(BuildContext context, {required String title, String? subtitle, required List<TvSheetSection> sections})` : route transparente, panneau de 760 de large à droite (hauteur pleine, fond `TvColors.surface`), liste paresseuse à hauteurs fixes (titre de section 72, option 104), la remote sur l'option `selected` (sinon la première) ; OK → ferme puis `onPick` ; Retour ferme.
  - `class TvSheet extends StatefulWidget` (le panneau, pour les tests).

- [ ] Tests : titre et options affichés ; OK sur une option → `onPick` appelé et feuille fermée ; Retour → fermée sans choix ; 300 options avec `selected` à l'index 250 → l'option 250 a la remote (son libellé est à l'écran).
- [ ] Les voir échouer, implémenter, tests verts, commit « Bobine TV : feuille d'options ».

### Tâche 3 : lecteur — audio, sous-titres, options de la chaîne, liste des chaînes

**Files:**
- Modify: `lib/player/player_keys.dart` (`TvPlayerArrow`, `tvPlayerArrow`)
- Modify: `lib/player/player_screen.dart` (branche télé de `_onKey`, ouverture des feuilles)
- Modify: `lib/tv/tv_player_overlay.dart` (touches affichées)
- Create: `lib/tv/tv_player_sheets.dart` (`tvTrackOptions`, feuilles du lecteur)
- Test: `test/tv_player_test.dart`

**Interfaces:**
- Consumes: `showTvSheet`, `TvSheetSection`, `TvSheetOption` (tâche 2).
- Produces:
  - `enum TvPlayerArrow { seekBack, seekForward, zapPrevious, zapNext, channels, options }`
  - `TvPlayerArrow? tvPlayerArrow(LogicalKeyboardKey key, {required bool live})` : direct : ▲ zapPrevious, ▼ zapNext, ◀ channels, ▶ options ; film / épisode : ◀ seekBack, ▶ seekForward, ▼ options, ▲ options.
  - `List<TvSheetOption> tvTrackOptions<T>(List<T> tracks, {required String selectedId, required String Function(T, int) label, required String Function(T) id, required void Function(T) onPick})`

- [ ] Tests : `tvPlayerArrow` pour les 8 cas ci-dessus ; `tvTrackOptions` marque la piste choisie `selected`, garde l'ordre ; listes vides → liste vide.
- [ ] Les voir échouer, implémenter.
- [ ] Lecteur sur la télé : `options` ouvre « Audio et sous-titres » (sections Audio, Sous-titres ; en direct, une section Chaîne d'abord : « Ajouter aux favoris » / « Retirer des favoris ») ; `channels` ouvre « Chaînes » (numéro, nom, programme en cours, chaîne en cours `selected`, choisir → `_playChannel(i)`). Les pistes viennent de `_ps.player.state.tracks` sans `auto` / `no` (Sous-titres commence par « Désactivés ») ; choisir → `_selectAudio` / `_selectSubtitle`.
- [ ] Habillage : film / épisode « ◀ ▶ 10 secondes · ▼ Audio et sous-titres · OK Pause · Retour Quitter » ; direct « ▲ ▼ Chaîne · ◀ Liste · ▶ Options · OK Pause · Retour Quitter ».
- [ ] Tests verts, vérifier sur la version Linux, commit « Bobine TV : audio, sous-titres et liste des chaînes dans le lecteur ».

### Tâche 4 : favoris, Ma liste et Reprendre à l'appui long

**Files:**
- Create: `lib/tv/tv_actions.dart` (`TvItemAction`, `tvItemActions`, `showTvItemActions`)
- Modify: `lib/tv/tv_browse.dart`, `lib/tv/tv_live.dart`, `lib/tv/tv_grid.dart` (`onLongOk` sur les cartes)
- Modify: `lib/tv/tv_shell.dart` (bulle d'aide : « Maintiens OK pour plus d'options »)
- Test: `test/tv_actions_test.dart`

**Interfaces:**
- Consumes: `TvFocusable.onLongOk` (tâche 1), `showTvSheet` (tâche 2).
- Produces:
  - `enum TvItemAction { watch, resume, fromStart, seen, removeResume, addFavorite, removeFavorite, addList, removeList, openSeries }`
  - `List<TvItemAction> tvItemActions(TvItem it, {required bool favorite})` : chaîne → [watch, add/removeFavorite] ; reprise → [resume, seen, removeResume] (+ fromStart si position > 0) ; film → [watch, add/removeList] ; série → [openSeries, add/removeList].

- [ ] Tests de `tvItemActions` pour les quatre sortes d'élément, favori ou non.
- [ ] Les voir échouer, implémenter ; `showTvItemActions(context, item)` exécute avec `AppServices` : `toggleFavorite`, `repo.removeFromResume`, `repo.setWatched` (comme `lib/ui/quick_actions.dart`), puis `library.userChanged()`.
- [ ] Brancher `onLongOk` sur les cartes des rangées, de la grille d'affiches et de la grille Direct.
- [ ] Tests verts, commit « Bobine TV : favoris, Ma liste et Reprendre à l'appui long ».

### Tâche 5 : page série sur l'épisode à reprendre, noms de catégories

**Files:**
- Modify: `lib/tv/tv_series.dart` (Bas depuis les boutons : défiler jusqu'à l'épisode à reprendre puis le sélectionner)
- Modify: `lib/tv/tv_rows.dart` (`tvCategoryLabel`, utilisé par `tvCatalogPills`, les titres de rangées de catégorie et les accroches)
- Modify: `lib/tv/tv_live.dart` (libellés des groupes)
- Test: `test/tv_rows_test.dart`

**Interfaces:**
- Produces: `String tvCategoryLabel(String name)`.

- [ ] Tests : « FR - DRAME » → « Drame » ; « |FR| Films 4K » → « Films 4K » ; « [VOD] Comédie ★ » → « Comédie » ; « Policier · Thriller » inchangé ; « FR | » → « FR | » (rien d'autre : nom d'origine).
- [ ] Les voir échouer, implémenter (préfixe pays comme `cleanChannelName`, symboles décoratifs retirés, majuscules → initiale, mais sans retirer les qualités).
- [ ] Page série : Bas depuis « Lecture / Reprendre » → l'épisode de `tvSeriesPrimary` (la saison affichée est la sienne ; la liste défile à `index × (400 + 24)` avant la sélection). Vérifier sur la version Linux.
- [ ] Tests verts, commit « Bobine TV : reprise au bon épisode, catégories lisibles ».

### Tâche 6 : recherche

**Files:**
- Create: `lib/tv/tv_search.dart` (`tvSearchRows`, `TvSearchPage`)
- Modify: `lib/tv/tv_shell.dart` (`TvTab.search`, loupe `nav-search` à gauche de la roue), `lib/tv/tv_app.dart`
- Test: `test/tv_search_test.dart`, `test/tv_shell_test.dart`

**Interfaces:**
- Consumes: `TvTextField` (`lib/tv/tv_form.dart`), `TvRow`, `tvChannel`, `tvMovie`, `tvSeries`, cartes de `tv_cards.dart`.
- Produces: `List<TvRow> tvSearchRows({required Repository repo, required EpgCache epg, required int sourceId, required String query, required String Function(Channel) name})` : rangées « Chaînes » (live), « Films », « Séries » (affiches), vides omises ; requête de moins de 2 caractères → aucune rangée.

- [ ] Tests : « film » → rangée Films ; moins de 2 caractères → vide ; contenu verrouillé absent ; la loupe est un onglet (`nav-search`) atteignable depuis la barre du haut, Retour de la page Recherche → onglet.
- [ ] Les voir échouer, implémenter. Page : champ « Rechercher » (OK ouvre le clavier ; résultats à la frappe, 300 ms après la dernière lettre), rangées dessous (Haut / Bas d'une rangée à l'autre, Haut de la première → le champ) ; texte d'aide quand c'est vide (« Le nom d'une chaîne, d'un film ou d'une série. ») ou sans résultat (« Rien pour « … ». »).
- [ ] Tests verts, vérifier sur la version Linux, commit « Bobine TV : recherche ».

### Tâche 7 : captures du Play Store

**Files:**
- Modify: `docs/store/screenshots/*.png` (1920 × 1080), `docs/store/fiche.md`

- [ ] Sur la version Linux `BOBINE_TV=1` avec le faux serveur, capturer en taille réelle : 1-accueil, 2-direct, 3-guide, 4-films (pastilles), 5-serie, 6-lecteur (mire visible), 7-recherche, 8-reglages ; remplacer les anciennes (5-fiche disparaît).
- [ ] Mettre à jour la liste des écrans dans `fiche.md`.
- [ ] Commit « Play Store : captures de la nouvelle interface télé ».

### Tâche 8 : vérification d'ensemble

- [ ] Suite complète, `flutter analyze`, `flutter build apk --debug`, parcours à la télécommande des nouveautés, push, relecture finale de la branche.
