import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/db.dart';
import 'data/epg_cache.dart';
import 'data/import/import_service.dart';
import 'data/models.dart';
import 'data/repository.dart';
import 'data/settings.dart';
import 'player/player_service.dart';
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
  });

  final String dbPath;
  final Repository repo;
  final AppSettings settings;
  final LibraryNotifier library;
  final ImportService imports;
  final PlayerService player;
  final EpgCache epg;

  static Future<AppServices> create() async {
    final support = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    await support.create(recursive: true);
    final mpvCache = Directory(p.join(cache.path, 'mpv'));
    await mpvCache.create(recursive: true);
    ImageFetcher.init(p.join(cache.path, 'images'));

    final dbPath = p.join(support.path, 'lumen.db');
    final repo = Repository(openAppDatabase(dbPath));
    final settings = AppSettings(repo);
    final library = LibraryNotifier();
    final epg = EpgCache(repo);
    final imports = ImportService(
      dbPath: dbPath,
      onContentChanged: (_) {
        epg.clear();
        library.contentChanged();
      },
      onEpgChanged: (_) {
        epg.clear();
        library.epgChanged();
      },
    );
    final player = PlayerService(settings, mpvCache.path)..init();

    final services = AppServices._(
      dbPath: dbPath,
      repo: repo,
      settings: settings,
      library: library,
      imports: imports,
      player: player,
      epg: epg,
    );
    services._ensureActiveSource();
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
      final contentStale = s.contentUpdatedAt == null ||
          now.difference(s.contentUpdatedAt!).inHours >= settings.contentRefreshHours;
      final epgStale = s.effectiveEpgUrl != null &&
          settings.epgRefreshHours > 0 &&
          (s.epgUpdatedAt == null ||
              now.difference(s.epgUpdatedAt!).inHours >= settings.epgRefreshHours);
      // Content of non-active sources is refreshed lazily when selected.
      final isActive = s.id == settings.activeSourceId;
      if ((contentStale && isActive) || epgStale) {
        unawaited(refresh(s, content: contentStale && isActive, epg: epgStale)
            .catchError((Object _) {}));
      }
    }
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

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
