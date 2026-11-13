# Bobine sur Android TV : plan jusqu'à la validation Play Store

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** publier Bobine sur le Google Play Store pour Android TV, utilisable entièrement à la télécommande, et passer la revue qualité TV de Google.

**Architecture:** même code Flutter que la version ordinateur. Un seul interrupteur, `Device` (`lib/core/device.dart`), décide de ce qui change sur la télé : fonctions masquées, multi-écran limité, interface rendue sur une toile fixe de 1280×720 puis agrandie. La navigation à la télécommande se règle à trois endroits partagés (`HoverBuilder`, les touches du lecteur, le bouton Retour) plutôt qu'écran par écran.

**Tech Stack:** Flutter 3.47.9, media_kit (libmpv, décodage matériel mediacodec), sqlite3, Android SDK cible API 36, Gradle (Kotlin DSL) produit par `flutter create`.

**Spec :** pas de document séparé. Les décisions viennent de la conversation et sont reprises dans *Contraintes globales*.

## Contraintes globales

- Appli **réservée à la télé** : `android.software.leanback` avec `required="true"`. Pas de version téléphone ou tablette.
- `applicationId` : `io.github.weder77.bobine`. **Définitif une fois publié** : à confirmer avant la tâche 2.
- `targetSdk` 36 (exigé par Google pour les nouvelles applis depuis le 31/08/2026). `minSdk` : la valeur par défaut de Flutter, sans la descendre.
- Le trafic `http://` en clair doit être autorisé (`usesCleartextTraffic="true"`). La plupart des fournisseurs IPTV et de leurs API Xtream sont en http, et `dart:io` respecte la politique Android.
- Aucune playlist, source ou adresse de fournisseur livrée avec l'appli, ni dans les captures (mires du faux serveur `tool/fake_xtream.py` uniquement).
- Aucune mise à jour hors du Play Store sur Android : pas de vérification GitHub, pas de téléchargement.
- Textes de l'interface en français, commentaires du code en anglais, comme dans le reste du dépôt.
- Toute la version ordinateur (Windows, macOS, Linux) reste identique : chaque changement passe par `Device.isTv`.
- Actions GitHub épinglées par commit, comme dans `.github/workflows/build.yml`.

## Review Focus

1. **Flux http en clair** : un compte Xtream en `http://` doit se connecter, importer et lire. Vérification dans la tâche 2, étape 4, avec le faux serveur.
2. **Retour depuis l'accueil avec la recherche ouverte** : Retour ferme la recherche et ne quitte pas l'appli. Testé dans la tâche 7 (`shellBack`).
3. **Appui long sur OK** : il ouvre le menu sans lancer aussi la lecture au relâchement. Testé dans la tâche 6.
4. **Saisie au clavier virtuel** dans le formulaire de source : OK ouvre le clavier, Haut/Bas sortent du champ, et la touche Retour ferme d'abord le clavier sans quitter l'écran. Vérification manuelle dans la tâche 9.
5. **Box peu puissante** : import d'une grosse playlist (20 000 chaînes, guide de 250 000 programmes) sans fermeture forcée faute de mémoire, et décodage matériel réellement actif. Vérification dans la tâche 10.

---

## Partie A : faire tourner l'appli sur la télé

### Tâche 1 : interrupteur `Device`

**Files:**
- Create: `lib/core/device.dart`
- Test: `test/device_test.dart`

**Interfaces:**
- Produces :
  ```dart
  abstract final class Device {
    static bool get isTv;                    // Platform.isAndroid (hors web), forçable en test
    @visibleForTesting static bool? debugTv; // null = valeur réelle
    static bool get canCast;                 // !isTv
    static bool get canRecord;               // !isTv
    static bool get canPickFiles;            // !isTv (pas de sélecteur de documents sur la plupart des TV)
    static bool get canSelfUpdate;           // !isTv
    static bool get seekPreview;             // !isTv (2e décodeur logiciel trop lourd pour une box)
    static int get maxMultiSlots;            // isTv ? 2 : 4
  }
  ```

- [ ] **Step 1 : écrire le test qui échoue**

```dart
test('sur la télé, les fonctions de l\'ordinateur sont coupées', () {
  Device.debugTv = true;
  addTearDown(() => Device.debugTv = null);
  expect(Device.isTv, isTrue);
  expect([Device.canCast, Device.canRecord, Device.canPickFiles, Device.canSelfUpdate, Device.seekPreview],
      everyElement(isFalse));
  expect(Device.maxMultiSlots, 2);
});
test('sur l\'ordinateur, rien ne change', () {
  Device.debugTv = false;
  addTearDown(() => Device.debugTv = null);
  expect(Device.maxMultiSlots, 4);
  expect(Device.canCast && Device.canRecord && Device.canPickFiles && Device.canSelfUpdate, isTrue);
});
```

- [ ] **Step 2 :** `flutter test test/device_test.dart` → ÉCHEC (fichier absent).
- [ ] **Step 3 :** écrire `lib/core/device.dart` selon l'interface.
- [ ] **Step 4 :** `flutter test test/device_test.dart` → OK.
- [ ] **Step 5 :** commit `Android TV : interrupteur Device`.

### Tâche 2 : cible Android et manifeste TV

**Files:**
- Create: `android/` (via `flutter create`)
- Modify: `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `.gitignore`
- Create: `android/app/src/main/res/drawable-xhdpi/banner.png` (320×180)
- Modify: `tool/make_icon.py` (nouvelle fonction `banner(w, h)` : bobine à gauche, « BOBINE » en Big Shoulders à droite, fond `BG`) ; sortie aussi en 1280×720 dans `docs/store/banner-1280x720.png` pour la fiche Play
- Create: `android/key.properties.example`

- [ ] **Step 1 :** `flutter create --platforms=android --org io.github.weder77 --project-name bobine .`, puis supprimer ce qu'il ajoute hors de `android/` (comme `test/widget_test.dart` s'il réapparaît).
- [ ] **Step 2 : manifeste.** Dans `<manifest>` :
  - `<uses-permission android:name="android.permission.INTERNET"/>` : Flutter ne la met que dans les manifestes debug et profile.
  - `<uses-feature android:name="android.software.leanback" android:required="true"/>`
  - `<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>`

  Sur `<application>` : `android:banner="@drawable/banner"`, `android:usesCleartextTraffic="true"`, `android:label="Bobine"`.

  Sur l'activité principale, ajouter l'intent-filter `MAIN` + `android.intent.category.LEANBACK_LAUNCHER` à côté de `LAUNCHER`. Ajouter aussi `android:screenOrientation="landscape"`.
- [ ] **Step 3 : Gradle.**
  - `applicationId = "io.github.weder77.bobine"`, `targetSdk = 36`.
  - Signature release lue dans `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`), avec repli sur la clé debug quand le fichier manque.
  - `key.properties` et `*.jks` ajoutés à `.gitignore`. `key.properties.example` montre les quatre clés sans valeur.
- [ ] **Step 4 : vérifier sur un émulateur Android TV** (image « Television 1080p », API 36) :
  - `flutter build apk --debug` → l'APK est produit.
  - `python3 tool/fake_xtream.py`, puis dans l'appli une source Xtream `http://10.0.2.2:<port>`.
  - Résultat attendu : la bannière apparaît sur l'accueil Android TV, l'import se termine, une chaîne se lit.
  - Si l'import échoue avec « Insecure HTTP is not allowed », le step 2 est incomplet.
- [ ] **Step 5 :** `flutter analyze` puis `flutter test` → OK. Commit `Android TV : cible Android, manifeste leanback, bannière`.

### Tâche 3 : corrections de plateforme

**Files:**
- Modify: `lib/core/open_url.dart`, `test/open_url_test.dart`
- Modify: `lib/data/db.dart:29-34` (`_ownerOnly`)
- Modify: `lib/main.dart:28` (vérification des mises à jour)
- Modify: `lib/player/seek_preview.dart` (aperçu à la recherche)
- Modify: `pubspec.yaml` (ajout de `url_launcher`)

**Interfaces:**
- Consumes : `Device` (tâche 1).
- Produces : `openExternal(String url, {ProcessRunner run, String? os, UrlLauncher launch})`, avec `typedef UrlLauncher = Future<bool> Function(Uri uri);`. Par défaut, `launchUrl(uri, mode: LaunchMode.externalApplication)`.

- [ ] **Step 1 : test qui échoue** dans `test/open_url_test.dart` :

```dart
test('sur Android, l\'adresse part vers une autre appli, sans processus', () async {
  final launched = <Uri>[];
  Future<bool> launch(Uri u) async { launched.add(u); return true; }
  expect(await openExternal('https://youtu.be/x', run: run, os: 'android', launch: launch), isTrue);
  expect(launched.single.toString(), 'https://youtu.be/x');
  expect(calls, isEmpty);
  expect(await openExternal('file:///etc/passwd', run: run, os: 'android', launch: launch), isFalse);
  expect(launched, hasLength(1));
});
```

- [ ] **Step 2 :** `flutter test test/open_url_test.dart` → ÉCHEC.
- [ ] **Step 3 :** ajouter le cas `'android'` dans `openExternal`. Il appelle `launch(uri)` après le même filtrage par `webUri`. Les bandes-annonces YouTube ouvrent ainsi l'appli YouTube de la télé.
- [ ] **Step 4 :** `flutter test test/open_url_test.dart` → OK.
- [ ] **Step 5 : les trois coupures.**
  - `_ownerOnly` ne fait rien sur Android : le dossier de l'appli est déjà privé.
  - `checkInBackground` n'est pas planifié quand `!Device.canSelfUpdate`, et la section « Mises à jour » de `settings_maintenance.dart` est masquée.
  - L'aperçu de `seek_preview.dart` n'ouvre pas son lecteur quand `!Device.seekPreview`. La barre de lecture reste, sans vignette.

  Puis `flutter analyze` et `flutter test` → OK. Commit `Android TV : liens, base, mises à jour et aperçu adaptés`.

### Tâche 4 : masquer ce qui n'a pas de sens sur la télé

**Files:**
- Modify: `lib/player/player_screen.dart` (bouton *Caster*, touche T, touche O déjà protégée), `lib/player/mini_player.dart`, `lib/player/cast_view.dart`
- Modify: `lib/ui/settings_screen.dart` (entrée Enregistrements), `lib/ui/epg_grid.dart` / `lib/ui/guide_screen.dart` (action « Enregistrer »), `lib/services.dart` (pas de démarrage de `RecordingService` ni de la découverte cast quand c'est coupé)
- Modify: `lib/ui/source_form.dart:97`, `lib/ui/profiles.dart:346`, `lib/ui/settings_maintenance.dart:92`, `lib/ui/diagnostic_screen.dart`, `lib/ui/settings_recordings.dart:38` (sélecteurs de fichiers)
- Modify: `lib/player/multi_view.dart:283`, `lib/ui/multi_view_screen.dart:129`
- Test: `test/multi_view_test.dart`

**Interfaces:**
- Consumes : `Device.canCast`, `Device.canRecord`, `Device.canPickFiles`, `Device.maxMultiSlots`.
- Produces : `MultiViewController.maxSlots` devient `static int get maxSlots => Device.maxMultiSlots;`, et `MultiLayout.available` vaut `values.where((l) => l.slots <= MultiViewController.maxSlots)`.

- [ ] **Step 1 : test qui échoue** dans `test/multi_view_test.dart` :

```dart
test('sur la télé, seul le côte à côte est proposé et 2 chaînes au plus', () {
  Device.debugTv = true;
  addTearDown(() => Device.debugTv = null);
  expect(MultiLayout.available, [MultiLayout.duo]);
  expect(MultiViewController.maxSlots, 2);
});
```

  Ajouter aussi un cas : un multi-écran enregistré avec 4 chaînes se recharge avec seulement les 2 premières.
- [ ] **Step 2 :** `flutter test test/multi_view_test.dart` → ÉCHEC.
- [ ] **Step 3 :** implémenter `maxSlots` et `MultiLayout.available`, puis utiliser `available` dans le choix de disposition de `multi_view_screen.dart`. Le chargement passe déjà par `take(maxSlots)`. `slots` reste une liste de taille `maxSlots`.
- [ ] **Step 4 :** `flutter test test/multi_view_test.dart` → OK.
- [ ] **Step 5 :** masquer les entrées listées dans *Files* derrière le drapeau correspondant. Une entrée masquée disparaît entièrement : pas de bouton grisé. La source M3U ne garde que l'URL sur la télé. Puis `flutter analyze` et `flutter test` → OK. Commit `Android TV : cast, enregistrements, fichiers masqués ; multi-écran à 2`.

## Partie B : la télécommande

### Tâche 5 : toile 1280×720 et marges de sécurité

Une télé 1080p se présente à Flutter en 960×540 points logiques, alors que les écrans ont été dessinés pour 1280 et plus. Sur la télé, toute l'appli est donc rendue sur une toile de 1280×720 points, agrandie pour remplir l'écran.

**Files:**
- Create: `lib/ui/widgets/tv_canvas.dart`
- Modify: `lib/app.dart:117` (`builder:`)
- Modify: `lib/ui/shell.dart` (marges)
- Test: `test/tv_canvas_test.dart`

**Interfaces:**
- Produces : `class TvCanvas extends StatelessWidget { const TvCanvas({super.key, required this.child}); static const Size size = Size(1280, 720); static const EdgeInsets safe = EdgeInsets.symmetric(horizontal: 64, vertical: 36); }`

- [ ] **Step 1 : tests qui échouent.**
  - Avec une vue de 1920×1080 pixels physiques et `devicePixelRatio` 2, l'enfant lit `MediaQuery.sizeOf == Size(1280, 720)`.
  - Un `tester.tapAt` au centre de l'écran atteint le bouton placé au centre de la toile.
  - Avec une vue en 16:10, la toile reste en 16:9 et centrée, avec des bandes noires.
- [ ] **Step 2 :** `flutter test test/tv_canvas_test.dart` → ÉCHEC.
- [ ] **Step 3 :** `TvCanvas` = fond noir, puis `FittedBox(fit: BoxFit.contain)` autour d'un `SizedBox.fromSize(size)`. Il remplace le `MediaQuery` par la taille de la toile, une marge à zéro et le même `textScaler`. Dans `app.dart`, entourer `PipLayer` par `TvCanvas` quand `Device.isTv`.
- [ ] **Step 4 :** `flutter test test/tv_canvas_test.dart` → OK.
- [ ] **Step 5 :** dans `shell.dart`, le contenu (barre du haut et écrans) reçoit `TvCanvas.safe` en marge intérieure sur la télé. Le lecteur reste plein cadre, et seuls ses contrôles respectent la marge (`player_chrome.dart`). Commit `Android TV : toile 1280×720 et marges de sécurité`.

### Tâche 6 : appui long sur OK = menu contextuel

La plupart des télécommandes n'ont pas de touche Menu. Tous les menus contextuels (favori, fiche, multi-écran, masquer…) doivent donc s'ouvrir par un appui long sur OK.

**Files:**
- Modify: `lib/ui/widgets/common.dart:50-120` (`_HoverBuilderState`)
- Modify : chaque site `onSecondaryTapUp` dont le `HoverBuilder` n'a pas encore son `onContextMenu` : `lib/ui/live_screen.dart:347`, `lib/ui/search_screen.dart:370,456`, `lib/ui/catalog_screen.dart:991`, `lib/ui/widgets/rows.dart:340,564,671,858`, `lib/ui/widgets/cards.dart:86`, `lib/ui/widgets/common.dart:367`, `lib/ui/epg_grid.dart:545`
- Test: `test/hover_builder_test.dart`

**Interfaces:**
- Produces : `HoverBuilder.longPressDelay` (`static const Duration`, 500 ms).

- [ ] **Step 1 : tests qui échouent** (un `HoverBuilder` avec compteurs `activated` et `menus`, focus demandé) :

```dart
testWidgets('appui court sur OK : lecture, pas de menu', (t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.select);
  await t.sendKeyUpEvent(LogicalKeyboardKey.select);
  expect((activated, menus), (1, 0));
});
testWidgets('appui long sur OK : menu seulement, rien au relâchement', (t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.select);
  await t.pump(HoverBuilder.longPressDelay);
  await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
  await t.sendKeyUpEvent(LogicalKeyboardKey.select);
  expect((activated, menus), (0, 1));
});
testWidgets('sans menu, Entrée garde le comportement actuel', (t) async { /* onContextMenu: null → activé dès l'appui */ });
```

  Mêmes cas pour `enter` et `gameButtonA`.
- [ ] **Step 2 :** `flutter test test/hover_builder_test.dart` → ÉCHEC.
- [ ] **Step 3 : implémentation.** Quand `onContextMenu != null`, entourer le `FocusableActionDetector` d'un `Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: …)` qui traite `select`, `enter`, `numpadEnter` et `gameButtonA` :
  - à l'appui : noter l'heure et répondre *handled*, pour que l'`ActivateIntent` par défaut de l'appli ne parte pas ;
  - à la répétition, au-delà de `longPressDelay` et une seule fois : `onContextMenu(centre)` ;
  - au relâchement : `onActivate` seulement si le menu n'est pas parti.
- [ ] **Step 4 :** `flutter test test/hover_builder_test.dart` → OK.
- [ ] **Step 5 :** relier chaque site listé à `onContextMenu` (même fonction que le clic droit, positionnée au centre de l'élément). Puis `flutter analyze` et `flutter test` → OK. Commit `Télécommande : appui long sur OK ouvre le menu`.

### Tâche 7 : bouton Retour

Sur Android, Retour passe par la navigation système. Sans traitement, il quitte l'appli depuis l'accueil, même si la recherche est ouverte.

**Files:**
- Create: `lib/ui/back_rules.dart`
- Modify: `lib/ui/shell.dart:146-157` (`_onKey`, branche Échap), `lib/player/player_screen.dart:757-768` (branche Échap)
- Modify : écrans plein écran qui gèrent Échap eux-mêmes (`lib/ui/multi_view_screen.dart:209`, `lib/ui/widgets/detail_layout.dart:62`)
- Test: `test/back_rules_test.dart`

**Interfaces:**
- Produces :
  ```dart
  enum ShellBack { closeSearch, goHome, exit }
  ShellBack shellBack({required bool searchOpen, required ShellTab tab});
  ```

- [ ] **Step 1 : test qui échoue.** `shellBack(searchOpen: true, tab: ShellTab.home) == closeSearch`, `(false, ShellTab.movies) == goHome`, `(false, ShellTab.home) == exit`.
- [ ] **Step 2 :** `flutter test test/back_rules_test.dart` → ÉCHEC.
- [ ] **Step 3 :** écrire `shellBack`. Dans `shell.dart`, la branche Échap l'utilise, et un `PopScope(canPop: false, onPopInvokedWithResult: …)` applique la même règle. `exit` → `SystemNavigator.pop()`. Dans `player_screen.dart`, extraire la branche Échap en `void _back()` (panneau, puis stats, puis plein écran, puis sortie) et l'appeler aussi depuis un `PopScope`. Faire de même pour le multi-écran et les fiches.
- [ ] **Step 4 :** `flutter test` → OK.
- [ ] **Step 5 :** vérifier sur l'émulateur TV, Retour pressé dans chaque situation de la règle. Commit `Télécommande : bouton Retour`.

### Tâche 8 : le lecteur à la télécommande

Aujourd'hui, les flèches du lecteur avancent, reculent ou zappent toujours. Les boutons ne sont donc atteignables qu'à la souris.

**Files:**
- Create: `lib/player/player_keys.dart`
- Modify: `lib/player/player_screen.dart:729-800` (`_onKey`), `:423` (`_showControls`)
- Modify: `lib/player/player_chrome.dart` (le bouton lecture/pause expose un `FocusNode` fourni par l'écran)
- Test: `test/player_keys_test.dart`

**Interfaces:**
- Produces :
  ```dart
  enum PlayerKeyRoute { handle, toFocusedButton, revealControls }
  PlayerKeyRoute playerKeyRoute(LogicalKeyboardKey key, {required bool controlsVisible, required bool buttonFocused});
  ```

- [ ] **Step 1 : test qui échoue.** Les cas :
  - Contrôles cachés : `select` → `revealControls` ; `arrowLeft` → `handle` (recul) ; `arrowUp` en direct → `handle` (zapping).
  - Contrôles visibles avec un bouton sélectionné : `arrowLeft`, `arrowRight`, `arrowUp`, `arrowDown`, `select` → `toFocusedButton`.
  - Contrôles visibles sans bouton sélectionné : `select` → `handle` (pause).
  - `mediaPlayPause`, `channelUp` et les chiffres → `handle` dans tous les cas.
- [ ] **Step 2 :** `flutter test test/player_keys_test.dart` → ÉCHEC.
- [ ] **Step 3 : brancher dans `_onKey`.**
  - `toFocusedButton` → `KeyEventResult.ignored` : la navigation par flèches de Flutter prend le relais.
  - `revealControls` → `_showControls(sticky: true)`, puis focus sur le bouton lecture/pause.
  - Quand les contrôles se cachent, le focus revient à `_focus`. `buttonFocused` vaut `FocusManager.instance.primaryFocus != _focus` quand les contrôles sont visibles.
  - Les panneaux (Chaînes, Mini-guide, Audio et sous-titres, Épisodes) donnent le focus à leur premier élément à l'ouverture.
- [ ] **Step 4 :** `flutter test` → OK.
- [ ] **Step 5 :** vérifier sur l'émulateur, uniquement aux flèches, à OK et à Retour :
  - zapper ;
  - ouvrir le panneau Chaînes et choisir une chaîne ;
  - changer la piste audio ;
  - mettre en pause, reculer, revenir au direct ;
  - lancer l'épisode suivant.

  Commit `Télécommande : lecteur`.

### Tâche 9 : passe écran par écran

**Files :** ceux que la vérification désigne. Les causes habituelles sont un `autofocus` absent, un élément cliquable fait d'un simple `GestureDetector` hors `HoverBuilder`, ou une action visible seulement au survol (`catalog_screen.dart:933`, `widgets/rows.dart:181,499`, `widgets/billboard.dart:225`, `widgets/chips.dart:113`, `multi_view_screen.dart:580,789`, `series_detail_screen.dart:249`, `settings_family.dart:366`).

- [ ] **Step 1 :** sur l'émulateur avec le faux serveur, souris débranchée, parcourir chaque écran.

  | Écran | Ce qui doit marcher aux flèches, à OK et à Retour |
  |---|---|
  | Lancement et profils | Choisir un profil, saisir le code parental |
  | Accueil | Atteindre l'image à la une, chaque rangée, « Continuer à regarder » |
  | Direct | Atteindre groupes, favoris, filtre et tuiles ; appui long → *Ajouter au multi-écran* |
  | Guide TV | Parcourir la grille en largeur et en hauteur avec défilement qui suit ; OK sur un programme |
  | Films / Séries | Parcourir, puis « Tout le catalogue » : catégories, tri, filtre, déverrouillage |
  | Fiches film / série | Lecture, favori, saisons, épisodes, bande-annonce |
  | Recherche | L'ouvrir depuis la barre du haut, saisir, atteindre les résultats |
  | Multi-écran | Choisir 2 chaînes, passer le son, agrandir, quitter |
  | Paramètres | Chaque section, dont Compte (connexion avec le clavier virtuel) et Sources (ajout Xtream) |

  Critères pour chaque écran :
  - un élément a le focus dès l'arrivée ;
  - le focus est toujours visible ;
  - aucune action n'est inaccessible ;
  - Retour remonte d'un niveau.
- [ ] **Step 2 :** corriger chaque écart. Pour chaque correction de logique (pas de pure mise en forme), ajouter un test de widget dans le fichier de test existant le plus proche. Point 4 du *Review Focus* : formulaire de source au clavier virtuel.
- [ ] **Step 3 :** `flutter analyze` et `flutter test` → OK. Un commit par écran corrigé, par exemple `Télécommande : Guide TV`.

### Tâche 10 : essai sur une vraie box

- [ ] **Step 1 :** installer l'APK release (`flutter build apk --release --split-per-abi`, variante `arm64-v8a` ou `armeabi-v7a` selon la box) sur un Chromecast avec Google TV ou un appareil équivalent.
- [ ] **Step 2 : mesurer et noter dans la PR.**
  - Durée de l'import du faux serveur réglé sur 20 000 chaînes.
  - Fluidité du Guide TV.
  - Temps de zapping.
  - Valeur « Décodeur » dans *Diagnostic* : `mediacodec` ou `mediacodec-copy` attendu, pas `no`.
  - Lecture d'un flux 1080i (désentrelacement).
  - Multi-écran à 2.
  - Mémoire après 30 min (`adb shell dumpsys meminfo io.github.weder77.bobine`).
- [ ] **Step 3 :** pour chaque problème mesuré, ouvrir une tâche de correction : réduire le cache, désactiver le désentrelacement logiciel, garder une seule case du multi-écran… Ne pas publier tant que le zapping et le Guide TV ne sont pas utilisables.

### Tâche 11 : construction Android dans la CI

**Files:**
- Modify: `.github/workflows/build.yml`

- [ ] **Step 1 :** nouveau job `android` sur `ubuntu-latest`. Il utilise `actions/setup-java` (Temurin 17) et `subosito/flutter-action` épinglés par commit, Flutter 3.47.9. Il enchaîne `flutter pub get`, `flutter analyze`, puis `flutter build appbundle --release`, et dépose l'AAB comme artefact.
- [ ] **Step 2 : signature.** Sur un tag `v*`, la clé d'envoi vient des secrets du dépôt :
  - `ANDROID_KEYSTORE_B64`, décodée dans `android/upload.jks` ;
  - `ANDROID_KEY_ALIAS` ;
  - `ANDROID_KEY_PASSWORD` et `ANDROID_STORE_PASSWORD`, écrits dans `android/key.properties`.

  Sur les autres branches, l'AAB est signé avec la clé debug et n'est pas publiable. Ce job n'envoie rien au Play Store : l'envoi reste manuel au début.
- [ ] **Step 3 :** pousser et vérifier que le job passe au vert. Commit `CI : construction Android`.

## Partie C : la validation Google

Ces tâches ne touchent pas, ou presque pas, au code. Elles se font dans la Play Console.

### Tâche 12 : fiche, politique de confidentialité et déclarations

**Files:**
- Create: `docs/confidentialite.md`. Elle couvre :
  - les données stockées sur l'appareil ;
  - le compte Bobine facultatif (e-mail, données chiffrées de bout en bout par AES-256-GCM, hébergées chez Supabase) ;
  - les requêtes à TMDB avec la clé de l'utilisateur ;
  - l'absence de publicité et de mesure d'audience ;
  - la suppression du compte.

  Publiée par l'adresse GitHub du fichier ou par GitHub Pages.
- Create: `docs/store/fiche.md` (titre, description courte et longue)
- Create: `docs/store/screenshots/` (captures TV en 1920×1080)

- [ ] **Step 1 :** rédiger la fiche.
  - Titre : « Bobine - lecteur IPTV » ; pas de « Xtream Codes » dans le titre.
  - La description commence par : « Bobine est uniquement un lecteur. Il ne fournit aucune chaîne, aucun film, aucune série ni aucune playlist : vous y ajoutez votre propre source. »
  - Pas de logos de chaînes, ni de noms de chaînes ou de fournisseurs.
- [ ] **Step 2 :** faire 6 à 8 captures sur l'émulateur avec le faux serveur (`adb exec-out screencap -p`) : accueil, Direct, Guide TV, Films, fiche, lecteur, paramètres.
- [ ] **Step 3 : préparer les réponses aux formulaires** dans `docs/store/fiche.md` :
  - *Sécurité des données* : à vérifier dans `lib/sync/` et `lib/features/tmdb.dart`. Adresse e-mail collectée pour le compte, facultative, chiffrée en transit et supprimable. Rien d'autre n'est lisible par le serveur.
  - *Classification du contenu* : appli de lecture multimédia sans contenu propre.
  - *Public cible* : 18 ans et plus.
  - *Publicités* : non.
  - Une adresse de contact pour les réclamations de droits d'auteur.
- [ ] **Step 4 :** commit `Play Store : fiche et politique de confidentialité`.

### Tâche 13 : Play Console, test fermé, production

- [ ] **Step 1 :** créer le compte développeur (25 $, vérification d'identité), puis créer l'appli « Bobine ».
- [ ] **Step 2 :** activer Play App Signing. Générer la clé d'envoi (`keytool -genkey -v -keystore upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`), la sauvegarder hors du dépôt et la mettre dans les secrets de la tâche 11.
- [ ] **Step 3 :** dans *Paramètres avancés → Formats*, ajouter **Android TV**. Remplir la fiche (bannière 1280×720, captures TV), puis la politique de confidentialité et les formulaires de la tâche 12.
- [ ] **Step 4 :** **test fermé** avec 12 testeurs au moins pendant 14 jours d'affilée, obligatoire pour un nouveau compte personnel. Envoyer l'AAB signé du tag. Corriger ce que les testeurs remontent.
- [ ] **Step 5 :** demander l'accès à la production. L'appli passe alors la revue générale et la **revue qualité TV**. En cas de refus TV, le motif cite une règle précise de la grille de qualité (navigation, bannière, marges…) : la corriger puis renvoyer.
- [ ] **Step 6 :** en cas de refus au titre de la propriété intellectuelle, répondre par le formulaire d'appel. L'argument : uniquement un lecteur, aucune source livrée, captures sur mires de test. En parallèle, préparer la publication sur l'Amazon Appstore (Fire TV) avec le même APK.
