import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cast/cast_log.dart';
import 'cast/cast_service.dart';
import 'core/app_log.dart';
import 'core/legacy.dart';
import 'core/text.dart';
import 'data/db.dart';
import 'data/epg_cache.dart';
import 'data/import/import_service.dart';
import 'data/models.dart';
import 'data/repository.dart';
import 'data/settings.dart';
import 'features/backup.dart';
import 'features/recording_service.dart';
import 'features/reminder_service.dart';
import 'features/tmdb.dart';
import 'features/updater.dart';
import 'player/pip.dart';
import 'player/playback_tracker.dart';
import 'player/player_service.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_service.dart';
import 'ui/widgets/net_image.dart';

/// Bumped whenever library content, EPG or user data change so screens reload.
class LibraryNotifier extends ChangeNotifier {
  int content = 0;
  int epg = 0;
  int user = 0;

  void contentChanged() {
    content++;
    notifyListeners();
  }

  void epgChanged() {
    epg++;
    notifyListeners();
  }

  void userChanged() {
    user++;
    notifyListeners();
  }
}

/// Everything the UI needs, created once at startup.
class AppServices {
  AppServices._({
    required this.dbPath,
    required this.repo,
    required this.settings,
    required this.library,
    required this.imports,
    required this.player,
    required this.epg,
    required this.tracker,
    required this.pip,
    required this.reminders,
    required this.recordings,
    required this.tmdb,
    required this.backup,
    required this.updates,
    required this.sync,
    required this.cast,
    required this.mpvCacheDir,
  });

  final String dbPath;
  final Repository repo;
  final AppSettings settings;
  final LibraryNotifier library;
  final ImportService imports;
  final PlayerService player;
  final EpgCache epg;

  /// Saves "Reprendre" positions wherever the video plays.
  final PlaybackTracker tracker;

  /// Mini-player and floating window.
  final PipController pip;

  /// "Me le rappeler" on future programmes.
  final ReminderService reminders;

  /// Recordings of live channels.
  final RecordingService recordings;

  /// Artwork, synopsis, cast and trailers (with the user's TMDB key).
  final TmdbService tmdb;

  /// Export / restore of the user's data.
  final BackupService backup;

  /// New versions on GitHub (installer on Windows).
  final UpdateService updates;

  /// Account and synchronisation with the user's other devices.
  final SyncService sync;

  /// Playback on a TV of the network (Chromecast, DLNA).
  final CastService cast;

  /// libmpv disk cache folder (diagnostic page).
  final String mpvCacheDir;

  /// Programme the guide should show next (from the search).
  final ValueNotifier<(Channel, Program)?> guideFocus = ValueNotifier(null);

  /// Parental code typed this session (locked categories visible).
  bool parentalUnlocked = false;

  /// "Qui regarde ?" was answered (or not needed) this session.
  bool profileChosen = false;

  static Future<AppServices> create() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    await support.create(recursive: true);
    final mpvCache = Directory(p.join(cache.path, 'mpv'));
    await mpvCache.create(recursive: true);
    ImageFetcher.init(p.join(cache.path, 'images'));

    // Moves Lumen's data here the first time (former name of the app).
    final dbPath = await resolveDatabase(support.path);
    AppLog.install(logPath: p.join(support.path, 'bobine.log'));
    castLog = (line) => debugPrint(line);
    if (!dbPath.startsWith(support.path)) AppLog.add('Données de Lumen ouvertes sur place : $dbPath');
    final repo = Repository(openAppDatabase(dbPath));
    final settings = AppSettings(repo);
    final library = LibraryNotifier();
    final epg = EpgCache(repo);
    final imports = ImportService(
      dbPath: dbPath,
      onContentChanged: (sourceId) {
        repo.autoLockAdult(sourceId);
        epg.clear();
        library.contentChanged();
      },
      onEpgChanged: (_) {
        epg.clear();
        library.epgChanged();
      },
    );
    final player = PlayerService(settings, mpvCache.path)..init();
    late final AppServices services;
    final cast = CastService(describe: (item) => services._castTitles(item));
    final tracker = PlaybackTracker(player, repo, onSaved: library.userChanged, cast: cast);
    final pip = PipController(player, cast);
    final reminders = ReminderService(repo, settings);
    final recordings = RecordingService(repo, settings, onChanged: library.userChanged);
    final sync = SyncService(repo, settings, onChanges: (c) => services._afterSync(c));

    services = AppServices._(
      dbPath: dbPath,
      repo: repo,
      settings: settings,
      library: library,
      imports: imports,
      player: player,
      epg: epg,
      tracker: tracker,
      pip: pip,
      reminders: reminders,
      recordings: recordings,
      tmdb: TmdbService(repo, settings),
      backup: BackupService(repo, settings),
      updates: UpdateService(repo, settings),
      sync: sync,
      cast: cast,
      mpvCacheDir: mpvCache.path,
    );
    // A change the user makes is sent a few seconds later.
    void changed() {
      if (repo.db.select('SELECT 1 FROM sync_log LIMIT 1').isNotEmpty) sync.syncSoon();
    }

    library.addListener(changed);
    settings.addListener(changed);
    services._ensureActiveSource();
    services._applyProfile();
    // "Qui regarde ?" is asked once, at start.
    services.profileChosen = !(settings.askProfileAtStart && repo.profiles().length > 1);
    return services;
  }

  /// The source currently browsed, or null when none is configured.
  Source? get activeSource {
    final id = settings.activeSourceId;
    if (id == null) return null;
    return repo.source(id);
  }

  void _ensureActiveSource() {
    final all = repo.sources();
    if (all.isEmpty) {
      if (settings.activeSourceId != null) settings.update((s) => s.activeSourceId = null);
      return;
    }
    if (!all.any((s) => s.id == settings.activeSourceId)) {
      settings.update((s) => s.activeSourceId = all.first.id);
    }
  }

  void selectSource(int id) {
    if (settings.activeSourceId == id) return;
    epg.clear();
    settings.update((s) => s.activeSourceId = id);
    library.contentChanged();
  }

  void deleteSource(int id) {
    repo.deleteSource(id);
    _ensureActiveSource();
    epg.clear();
    library.contentChanged();
  }

  Future<void> refresh(Source s, {bool content = true, bool epg = true}) =>
      imports.refresh(s, content: content, epg: epg, epgDays: settings.epgDays);

  /// Refreshes stale content / EPG in the background at startup.
  void refreshStaleSources() {
    final now = DateTime.now();
    for (final s in repo.sources()) {
      final contentStale =
          s.contentUpdatedAt == null || now.difference(s.contentUpdatedAt!).inHours >= settings.contentRefreshHours;
      final epgStale =
          s.effectiveEpgUrl != null &&
          settings.epgRefreshHours > 0 &&
          (s.epgUpdatedAt == null || now.difference(s.epgUpdatedAt!).inHours >= settings.epgRefreshHours);
      // Content of non-active sources is refreshed lazily when selected.
      final isActive = s.id == settings.activeSourceId;
      if ((contentStale && isActive) || epgStale) {
        unawaited(refresh(s, content: contentStale && isActive, epg: epgStale).catchError((Object _) {}));
      }
    }
  }

  // ------------------------------------------------------------- profiles

  Profile get profile => repo.profile(settings.activeProfileId) ?? repo.profiles().first;

  void _applyProfile() {
    if (repo.profile(settings.activeProfileId) == null) settings.activeProfileId = repo.profiles().first.id;
    repo.profileId = settings.activeProfileId;
    _applyVisibility();
  }

  /// Locked categories are hidden while the parental code was not typed,
  /// and always in a kids profile.
  void _applyVisibility() {
    repo.hideLocked = settings.parentalEnabled && (!parentalUnlocked || profile.kids);
  }

  void switchProfile(int id) {
    if (repo.profile(id) == null) return;
    // What plays belongs to the profile being left: its position is saved
    // there, then playback stops (here and on the TV) so that nothing goes
    // on, or is remembered, in the other profile.
    tracker.flushAndForget();
    unawaited(player.stop());
    unawaited(pip.close());
    settings.update((s) => s.activeProfileId = id);
    parentalUnlocked = false;
    _applyProfile();
    epg.clear();
    library.contentChanged();
    library.userChanged();
  }

  /// Checks the parental code and shows locked categories until [lockParental].
  bool unlockParental(String pin) {
    if (!settings.parentalEnabled || pin != settings.parentalPin) return false;
    parentalUnlocked = true;
    _applyVisibility();
    library.contentChanged();
    return true;
  }

  void lockParental() {
    parentalUnlocked = false;
    _applyVisibility();
    _stopLockedPlayback();
    library.contentChanged();
  }

  /// Stops what plays (here or on the TV) when it is locked again.
  void _stopLockedPlayback() {
    final item = cast.item.value ?? player.current.value;
    if (item != null && repo.isLocked(item.sourceId, item.kind, item.extId, seriesExt: item.seriesExt)) {
      unawaited(pip.close());
    }
  }

  /// Sets (or with null removes) the parental code.
  void setParentalPin(String? pin) {
    settings.update((s) => s.parentalPin = pin);
    parentalUnlocked = false;
    for (final src in repo.sources()) {
      repo.autoLockAdult(src.id);
    }
    _applyVisibility();
    library.contentChanged();
  }

  /// Re-reads hidden / locked state after the user changed category settings.
  void visibilityChanged() {
    _applyVisibility();
    epg.clear();
    library.contentChanged();
  }

  /// Reloads everything after a backup was restored; new sources are imported.
  void afterRestore(RestoreReport report) {
    _ensureActiveSource();
    _applyProfile();
    epg.clear();
    library.contentChanged();
    library.userChanged();
    if (report.sourcesCreated > 0) {
      for (final src in repo.sources().where((s) => s.contentUpdatedAt == null)) {
        unawaited(refresh(src).catchError((Object _) {}));
      }
    }
  }

  /// Shows what came from the account: other sources, profiles, favourites,
  /// preferences. New sources are imported.
  void _afterSync(SyncChanges c) {
    if (c.sources || c.profiles || c.settings) {
      _ensureActiveSource();
      _applyProfile();
    }
    epg.clear();
    library.contentChanged();
    library.userChanged();
    if (c.sources) refreshStaleSources();
  }

  /// Name of [c] as shown in the app (cleaned unless turned off).
  String channelName(Channel c) => settings.cleanNames ? cleanChannelName(c.name) : c.name;

  /// What the TV shows while casting: channel and current programme, or the
  /// title of the film / episode.
  (String, String?) _castTitles(PlayItem item) {
    if (!item.isLive) return (item.title, item.subtitle);
    final c = repo.channelByExt(item.sourceId, item.extId);
    if (c == null) return (item.title, null);
    return (channelName(c), epg.now(c)?.title);
  }

  void toggleFavorite(ContentKind kind, String extId, int sourceId) {
    repo.toggleFavorite(sourceId, kind, extId);
    library.userChanged();
  }
}

/// Gives widgets access to [AppServices].
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
