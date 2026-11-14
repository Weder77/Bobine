# Bobine TV simple : plan d'exécution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** remplacer, sur la télé uniquement, l'interface ordinateur par l'interface simple de la maquette « Bobine TV ».

**Architecture :** écrans neufs dans `lib/tv/`, dessinés en unités 1920 × 1080 dans une scène `TvStage` (FittedBox) ; un moteur de navigation propre (`TvFocus`) qui reprend le calcul de la maquette au lieu du parcours de focus de Flutter ; données lues dans `Repository`, `EpgCache`, `LiveCatalog` et `AppSettings` existants ; lecture par `Launch` / `PlayerScreen` existants, avec un habillage télé du lecteur.

**Tech Stack :** Flutter 3.47.9, Dart, polices déjà embarquées (BigShoulders, Geist, GeistMono).

**Spec :** `docs/superpowers/specs/2026-11-14-bobine-tv-simple-design.md`

## Contraintes globales

- Rien ne change sur ordinateur : chaque branchement passe par `Device.isTv` ; les tests existants restent verts.
- Valeurs de la maquette : marges 96, fond `#0D0C0B`, vermillon `#FF5A36`, crème `#F3EEE8`, texte doux `#D9D4CE` / `#B5AFA8` / `#9A948D`, surface `#1A1816`, bordure `#3A3530` ; pastille sélectionnée blanche texte `#0D0C0B` + `scale(1.05)` ; vignette sélectionnée anneau blanc 4 px + ombre + `scale(1.05–1.06)` ; transitions 150–180 ms.
- Textes en français, commentaires en anglais, largeur 120.

## Review Focus

1. **Source vide ou sans guide** : rangées vides masquées, Direct sans chaîne, Guide sans programme → pas d'erreur ni de débordement, un message simple.
2. **Très grosse source** (20 000 chaînes, 300 groupes) : la mosaïque et la grille restent fluides (construction paresseuse), la rangée de groupes défile.
3. **Contrôle parental** : rien de verrouillé n'apparaît dans les rangées ; activer / couper demande le code.
4. **Retour** ne quitte jamais par erreur depuis une page ; seulement depuis l'onglet Accueil.
5. **Ordinateur inchangé** : `AppShell` et `PlayerScreen` identiques hors télé.

---

### Tâche 1 : moteur de navigation `TvFocus`

**Files :** Create `lib/tv/tv_focus.dart`, Test `test/tv_focus_test.dart`

**Interfaces :**
- `enum TvDir { up, down, left, right }`
- `String? tvPick(Rect from, Map<String, Rect> candidates, TvDir dir)` : calcul de la maquette (`prim + orth*4 + tie*0.3`, recouvrement ≥ 30 % pour gauche/droite, ancre x à `min(width/2, 40)`).
- `class TvFocusController extends ChangeNotifier { String? id; void focus(String id); bool move(TvDir dir); void activate(); }` et `TvFocusable({required String id, VoidCallback? onOk, ValueChanged<TvDir>? onSide, required Widget Function(BuildContext, bool focused) builder})` qui s'enregistre (GlobalKey → rect) et appelle `Scrollable.ensureVisible` à la prise de focus.
- `TvFocusScope({controller, onBack, child})` : un seul `Focus` qui reçoit les touches (flèches, OK/Entrée/A, Retour/Échap/Retour arrière) quand sa route est au premier plan.

- [ ] Tests `tvPick` : à droite choisit le plus proche sur la même ligne ; ignore un élément sans recouvrement vertical ; en bas préfère l'élément aligné sous l'ancre ; rien dans la direction → null.
- [ ] Test widget : trois `TvFocusable` en ligne, flèche droite → focus suivant, OK → `onOk`, Retour → `onBack`.
- [ ] Implémenter, tests verts, commit.

### Tâche 2 : scène, thème et barre du haut (`TvShell`)

**Files :** Create `lib/tv/tv_stage.dart`, `lib/tv/tv_theme.dart`, `lib/tv/tv_shell.dart`, Modify `lib/app.dart` (`_RootGate` : `Device.isTv ? const TvShell() : const AppShell()`), Test `test/tv_shell_test.dart`

**Interfaces :** `TvStage(child)` (FittedBox 1920 × 1080) ; `TvColors`, `tvTitle(size)`, `tvBody(size, weight)`, `tvMono(size)` ; `enum TvTab { home, live, guide, films, series, settings }` ; `TvBackRule tvBack({required bool onNav, required TvTab tab})` → `toNav | toHome | exit`.

- [ ] Tests `tvBack` : dans une page → onglet en cours ; onglet ≠ Accueil → Accueil ; onglet Accueil → sortie.
- [ ] Barre : logo, 5 pastilles (arriver dessus change l'onglet), roue Réglages, heure, pastille profil ; Bas depuis la barre → élément d'entrée de la page ; Haut vers la barre → onglet en cours ; bulle d'aide 9 s.
- [ ] Brancher dans `_RootGate`, vérifier à l'écran (Linux, `BOBINE_TV=1`), commit.

### Tâche 3 : Accueil, Films, Séries (haut de page + rangées)

**Files :** Create `lib/tv/tv_rows.dart` (modèles + construction des rangées depuis le dépôt), `lib/tv/tv_browse.dart`, `lib/tv/tv_cards.dart`, Test `test/tv_rows_test.dart`

**Interfaces :** `class TvItem { id, title, image, kicker, meta, synopsis, progress?, progressLabel?, kind (live|movie|series|resume), onOk }`, `class TvRow { title, style (live|wide|top|poster), items }`, `List<TvRow> tvRows(AppServices s, TvTab tab)`.

- [ ] Tests (dépôt en mémoire) : Accueil = En direct maintenant / Reprendre / Top 10 / Ajoutés récemment ; rangée vide omise ; contenu verrouillé absent ; Films contient « Ma liste » seulement si un favori existe.
- [ ] Haut de page (image, dégradés, surtitre, titre géant, infos, résumé 2 lignes, Lecture / Ma liste ou progression), rangées avec les 4 styles de vignettes, rangée sélectionnée remontée en haut.
- [ ] OK : film → `Launch.movie`, chaîne → `Launch.channel`, reprise → `Launch.resume`, série → page série (tâche 4).
- [ ] Vérifier à l'écran, commit.

### Tâche 4 : page série (choix B)

**Files :** Create `lib/tv/tv_series.dart`, Test `test/tv_series_test.dart`

**Interfaces :** `TvSeriesScreen(series)` ; `({Episode episode, String label}) tvSeriesPrimary(List<Episode> eps, Map<String, ProgressEntry> progress)` → « Reprendre S02E04 » ou « Lecture S01E01 ».

- [ ] Tests `tvSeriesPrimary` : sans progression → premier épisode ; épisode commencé → « Reprendre » ; dernier vu terminé → épisode suivant.
- [ ] Écran : haut de page, boutons, pastilles de saisons, rangée d'épisodes ; chargement via `loadEpisodes`. Retour → page précédente. Commit.

### Tâche 5 : Direct

**Files :** Create `lib/tv/tv_live.dart`

- [ ] Titre + compteur, pastilles Toutes / Favoris / groupes (via `LiveCatalog`), mosaïque 4 colonnes construite paresseusement, tuile : monogramme / logo, nom, numéro, programme, progression, fin, « Ensuite » si sélectionnée. OK → `Launch.channel` avec la liste du groupe. Vérifier, commit.

### Tâche 6 : Guide TV

**Files :** Create `lib/tv/tv_guide.dart`, Test `test/tv_guide_test.dart`

**Interfaces :** `String tvProgramStatus(Program p, DateTime now)` et `String tvProgramAction(Program p, DateTime now, bool reminded)`.

- [ ] Tests des statuts et actions (en cours, à venir, terminé, rappel).
- [ ] En-tête du programme sélectionné, grille (300 px + 12 px/min, repères 30 min, ligne maintenant), défilement horizontal et vertical suivant la sélection ; OK → direct ou rappel (`repo.toggleReminder`). Vérifier, commit.

### Tâche 7 : Réglages

**Files :** Create `lib/tv/tv_settings.dart`, Test `test/tv_settings_test.dart`

**Interfaces :** `class TvSetting { label, help, values(), index(), change(int delta), action? }`, `List<TvSetting> tvSettings(AppServices s, BuildContext context)`.

- [ ] Tests : Qualité vidéo fait tourner `preferredQuality` ; Épisode suivant bascule `autoNextEpisode` ; Sous-titres et Langue audio écrivent `subtitleLang` / `audioLang`.
- [ ] Écran (lignes 88 px, flèches sur la ligne sélectionnée, aide à droite, carte source) ; Profil → `switchProfile` ; Contrôle parental → demande du code ; Source → ← → `selectSource`, OK → écran de démarrage (ajout / compte) ; Actualiser → `s.refresh`. Commit.

### Tâche 8 : habillage télé du lecteur

**Files :** Create `lib/tv/tv_player_overlay.dart`, Modify `lib/player/player_screen.dart` (sur la télé : barres et panneaux remplacés par l'habillage, OK = pause, Retour = quitter)

- [ ] Habillage direct et film/épisode de la maquette, effacement après 5 s, rond pause ; touches : direct ▲▼ zappe, film ◀▶ ±10 s, OK pause, Retour quitte. Tests existants verts. Vérifier, commit.

### Tâche 9 : vérification d'ensemble

- [ ] Parcours complet à la télécommande sur la version Linux `BOBINE_TV=1` (et l'émulateur de l'utilisateur), captures, suite complète, `flutter analyze`, construction de l'APK.
