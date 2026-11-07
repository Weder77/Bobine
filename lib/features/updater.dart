import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/version.dart';
import '../data/repository.dart';
import '../data/settings.dart';

/// A newer version published on GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.page,
    this.notes,
    this.assetUrl,
    this.assetName,
    this.size,
    this.sha256,
  });
  final String version;
  final String? notes;

  /// Release page (always available).
  final String page;

  /// Installer of this platform, when the release has one.
  final String? assetUrl;
  final String? assetName;
  final int? size;
  final String? sha256;
}

enum UpdateStage { idle, checking, upToDate, available, downloading, ready, error }

/// Checks GitHub releases for a newer Bobine, downloads the Windows installer
/// (checking its SHA-256 when GitHub gives it) and runs it silently; the
/// installer starts Bobine again when done.
class UpdateService extends ChangeNotifier {
  UpdateService(this._repo, this._settings, {String? apiUrl})
    : _api =
          apiUrl ??
          Platform.environment['BOBINE_UPDATE_URL'] ??
          'https://api.github.com/repos/$kReleaseRepo/releases/latest';

  final Repository _repo;
  final AppSettings _settings;
  final String _api;

  UpdateStage stage = UpdateStage.idle;
  UpdateInfo? available;
  String? error;

  /// 0..1 while downloading.
  double progress = 0;
  String? _installer;

  /// The installer can be run for the user (Windows).
  bool get canInstall => Platform.isWindows && available?.assetUrl != null;

  void _set(UpdateStage s) {
    stage = s;
    notifyListeners();
  }

  /// At startup: at most once a day, quietly.
  Future<void> checkInBackground() async {
    if (!_settings.checkUpdates) return;
    final last = int.tryParse(_repo.kvGet('update_checked_at') ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now - last < 20 * 3600) return;
    await check(quiet: true);
  }

  /// Asks GitHub for the latest release. With [quiet], failures are not shown
  /// and a version the user chose to skip is not offered again.
  Future<UpdateInfo?> check({bool quiet = false}) async {
    if (stage == UpdateStage.checking || stage == UpdateStage.downloading) return available;
    _set(UpdateStage.checking);
    error = null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_api)).timeout(const Duration(seconds: 15));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Bobine/$kAppVersion');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      _repo.kvSet('update_checked_at', '${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
      if (res.statusCode == 404) {
        throw const _UpdateError(
          'Aucune version publiée trouvée. Si le dépôt GitHub est privé, '
          'la vérification automatique ne peut pas y accéder.',
        );
      }
      if (res.statusCode >= 400) throw _UpdateError('GitHub a répondu ${res.statusCode}.');
      final info = parseRelease((jsonDecode(body) as Map).cast<String, Object?>());
      final skipped = _repo.kvGet('update_skip');
      if (info == null || (quiet && skipped == info.version)) {
        available = null;
        _set(UpdateStage.upToDate);
        return null;
      }
      available = info;
      _set(UpdateStage.available);
      return info;
    } catch (e) {
      available = null;
      error = e is _UpdateError
          ? e.message
          : (e is TimeoutException ? 'GitHub ne répond pas.' : 'Vérification impossible : $e');
      debugPrint('Mise à jour : $error');
      _set(quiet ? UpdateStage.idle : UpdateStage.error);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Newer version described by a GitHub release, or null.
  @visibleForTesting
  static UpdateInfo? parseRelease(Map<String, Object?> r, {String current = kAppVersion, bool? windows}) {
    final tag = '${r['tag_name'] ?? ''}';
    if (tag.isEmpty || r['draft'] == true || r['prerelease'] == true) return null;
    if (compareVersions(tag, current) <= 0) return null;
    final assets = (r['assets'] as List? ?? const []).cast<Map>();
    final win = windows ?? Platform.isWindows;
    final asset = win
        ? assets.where((a) => RegExp(r'setup.*\.exe$', caseSensitive: false).hasMatch('${a['name']}')).firstOrNull
        : null;
    final digest = '${asset?['digest'] ?? ''}';
    return UpdateInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: (r['body'] as String?)?.trim(),
      page: '${r['html_url'] ?? 'https://github.com/$kReleaseRepo/releases'}',
      assetUrl: asset?['browser_download_url'] as String?,
      assetName: asset?['name'] as String?,
      size: asset?['size'] as int?,
      sha256: digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
    );
  }

  void skip() {
    final v = available?.version;
    if (v != null) _repo.kvSet('update_skip', v);
    available = null;
    _set(UpdateStage.idle);
  }

  Future<void> download() async {
    final info = available;
    if (info?.assetUrl == null || stage == UpdateStage.downloading) return;
    _set(UpdateStage.downloading);
    progress = 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'bobine-update'));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final file = File(p.join(dir.path, p.basename(info!.assetName ?? 'Bobine-Setup.exe')));
      final req = await client.getUrl(Uri.parse(info.assetUrl!));
      req.headers.set(HttpHeaders.userAgentHeader, 'Bobine/$kAppVersion');
      final res = await req.close();
      if (res.statusCode >= 400) throw _UpdateError('Téléchargement refusé (${res.statusCode}).');
      final total = res.contentLength > 0 ? res.contentLength : (info.size ?? 0);
      final sink = file.openWrite();
      final hashOut = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashOut);
      var received = 0;
      var lastNotify = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0 && received - lastNotify > 256 * 1024) {
          lastNotify = received;
          progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
      hasher.close();
      if (info.size != null && received != info.size) {
        throw const _UpdateError('Téléchargement incomplet, réessaie.');
      }
      if (info.sha256 != null && hashOut.value.toString() != info.sha256) {
        file.deleteSync();
        throw const _UpdateError("L'installateur téléchargé est altéré (empreinte SHA-256 différente).");
      }
      _installer = file.path;
      progress = 1;
      _set(UpdateStage.ready);
    } catch (e) {
      error = e is _UpdateError ? e.message : 'Téléchargement impossible : $e';
      _set(UpdateStage.error);
    } finally {
      client.close(force: true);
    }
  }

  /// Runs the installer silently (it closes Bobine and starts it again).
  Future<void> installAndRestart({Future<void> Function()? beforeExit}) async {
    final path = _installer;
    if (path == null || !Platform.isWindows) return;
    await beforeExit?.call();
    await Process.start(path, const [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/relaunch=1',
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
}

class _UpdateError implements Exception {
  const _UpdateError(this.message);
  final String message;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
