import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../core/text.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/settings.dart';
import '../data/stream_urls.dart';
import '../player/player_service.dart';

/// Records live channels to files, now or at a programme's time.
///
/// Each recording uses its own hidden player (no picture, no sound) whose
/// stream is written as it arrives, so it does not disturb what is being
/// watched. It needs a second connection to the provider: subscriptions
/// limited to one connection cannot record and watch at the same time.
class RecordingService {
  RecordingService(this._repo, this._settings, {required this.onChanged}) {
    // Recordings cut by a crash or by closing the app: what was written
    // can still be watched.
    for (final r in _repo.recordings()) {
      if (r.status == RecordingStatus.recording) {
        final size = _sizeOf(r.path);
        final ok = size != null && size > _minSize;
        _repo.updateRecording(
          r.id,
          status: ok ? RecordingStatus.done : RecordingStatus.failed,
          size: size ?? 0,
          error: ok ? "Partiel : interrompu (l'app a été fermée)" : "Interrompu (l'app a été fermée)",
        );
      }
    }
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    scheduleMicrotask(_tick);
  }

  final Repository _repo;
  final AppSettings _settings;
  final VoidCallback onChanged;
  Timer? _timer;
  final Map<int, Player> _active = {};
  final Map<int, List<StreamSubscription<Object?>>> _watch = {};

  /// Size of each active file at its last growth, and when that was.
  final Map<int, (int, DateTime)> _growth = {};

  /// Times a recording was started again after a cut (by the id of the
  /// latest part).
  final Map<int, int> _restarts = {};

  /// Smallest file taken for a recording (less: nothing was received).
  static const _minSize = 64 * 1024;

  /// A file that has not grown for this long: the stream is gone.
  static const stalled = Duration(seconds: 60);

  /// Parts started again after cuts, at most, for one programme.
  static const maxRestarts = 5;

  /// Recordings being started (their status is still "scheduled" until the
  /// player is ready): a second pass must not start them again.
  final Set<int> _starting = {};

  /// Number of recordings in progress (shown in the top bar).
  final ValueNotifier<int> activeCount = ValueNotifier(0);

  /// Margin added before and after a programme (guides are rarely exact).
  static const _before = Duration(minutes: 1);
  static const _after = Duration(minutes: 3);

  /// Folder where files are written.
  String get folder {
    final custom = _settings.recordingsDir;
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    return p.join(home, Platform.isMacOS ? 'Movies' : 'Videos', 'Bobine');
  }

  bool isActive(int id) => _active.containsKey(id);

  /// Records [p] on [c] (starts right away if it already began).
  int schedule(Channel c, Program prog) {
    final id = _repo.addRecording(
      sourceId: c.sourceId,
      channelExt: c.extId,
      channelName: c.name,
      title: prog.title,
      start: prog.start.subtract(_before),
      stop: prog.stop.add(_after),
    );
    onChanged();
    _tick();
    return id;
  }

  /// Records [c] from now until the end of [current] (or 2 hours).
  int recordNow(Channel c, {Program? current}) {
    final now = DateTime.now();
    final id = _repo.addRecording(
      sourceId: c.sourceId,
      channelExt: c.extId,
      channelName: c.name,
      title: current?.title ?? c.name,
      start: now,
      stop: current != null && current.stop.isAfter(now) ? current.stop.add(_after) : now.add(const Duration(hours: 2)),
    );
    onChanged();
    _tick();
    return id;
  }

  /// Stops a recording in progress now (the file is kept) or cancels a
  /// scheduled one.
  Future<void> stop(int id) async {
    if (_active.containsKey(id)) {
      await _finish(id);
    } else {
      _repo.updateRecording(id, status: RecordingStatus.cancelled);
    }
    onChanged();
  }

  /// Removes a recording from the list, and its file when [deleteFile].
  Future<void> delete(int id, {bool deleteFile = true}) async {
    final r = _repo.recording(id);
    if (_active.containsKey(id)) await _finish(id);
    if (deleteFile && r?.path != null) {
      try {
        final f = File(r!.path!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _repo.deleteRecording(id);
    onChanged();
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    var changed = false;
    for (final r in _repo.recordings()) {
      if (r.status == RecordingStatus.scheduled) {
        if (!now.isBefore(r.stop)) {
          _repo.updateRecording(r.id, status: RecordingStatus.failed, error: "Manqué : l'app était fermée");
          changed = true;
        } else if (!now.isBefore(r.start) && !_starting.contains(r.id) && !_active.containsKey(r.id)) {
          _starting.add(r.id);
          try {
            await _start(r);
          } finally {
            _starting.remove(r.id);
          }
          changed = true;
        }
      } else if (r.status == RecordingStatus.recording && _active.containsKey(r.id)) {
        if (!now.isBefore(r.stop)) {
          await _finish(r.id);
          changed = true;
        } else if (_repo.source(r.sourceId) == null) {
          // Source deleted (here or on another device): stopped, kept.
          await _finish(r.id, note: 'Partiel : source supprimée');
          changed = true;
        } else if (_stalled(r, now)) {
          await _cut(r.id);
          changed = true;
        }
      }
    }
    if (changed) onChanged();
  }

  bool _stalled(Recording r, DateTime now) {
    final size = _sizeOf(r.path) ?? 0;
    final last = _growth[r.id];
    if (last == null || size > last.$1) {
      _growth[r.id] = (size, now);
      return false;
    }
    return now.difference(last.$2) >= stalled;
  }

  /// The stream of [id] stopped before the end: what was written is kept,
  /// and the rest is recorded in a new part.
  Future<void> _cut(int id) async {
    if (!_active.containsKey(id)) return;
    final r = _repo.recording(id);
    await _finish(id, note: 'Partiel : flux coupé à ${_clock(DateTime.now())}');
    if (r == null) return;
    final now = DateTime.now();
    final tries = _restarts.remove(id) ?? 0;
    if (tries >= maxRestarts || !now.add(const Duration(minutes: 1)).isBefore(r.stop)) return;
    final next = _repo.addRecording(
      sourceId: r.sourceId,
      channelExt: r.channelExt,
      channelName: r.channelName,
      title: r.title.endsWith(' (suite)') ? r.title : '${r.title} (suite)',
      start: now.add(const Duration(seconds: 10)),
      stop: r.stop,
    );
    _restarts[next] = tries + 1;
    onChanged();
  }

  /// Stops every recording of [sourceId] (the source is being deleted).
  Future<void> stopSource(int sourceId) async {
    for (final r in _repo.recordings()) {
      if (r.sourceId == sourceId && _active.containsKey(r.id)) {
        await _finish(r.id, note: 'Partiel : source supprimée');
      }
    }
    onChanged();
  }

  /// Recordings in progress of [sourceId].
  int activeFor(int sourceId) =>
      _repo.recordings().where((r) => r.sourceId == sourceId && _active.containsKey(r.id)).length;

  Future<void> _start(Recording r) async {
    final source = _repo.source(r.sourceId);
    final channel = _repo.channelByExt(r.sourceId, r.channelExt);
    if (source == null || channel == null) {
      _repo.updateRecording(r.id, status: RecordingStatus.failed, error: 'Chaîne introuvable');
      return;
    }
    try {
      final dir = Directory(folder);
      await dir.create(recursive: true);
      final stamp =
          '${r.start.year}-${_two(r.start.month)}-${_two(r.start.day)} ${_two(r.start.hour)}h${_two(r.start.minute)}';
      final name = safeFileName('${r.channelName} - ${r.title} - $stamp');
      final path = freeFilePath(dir.path, name, 'ts');
      // A folder that cannot be written to is said now, not at the end.
      File(path).writeAsBytesSync(const []);
      final player = Player(
        configuration: const PlayerConfiguration(
          title: 'Bobine (enregistrement)',
          muted: true,
          logLevel: MPVLogLevel.warn,
        ),
      );
      final native = player.platform as NativePlayer;
      for (final e in {
        'ao': 'null',
        // media_kit turns the video track off on players without a picture;
        // the recording needs it.
        'vid': 'auto',
        'aid': 'auto',
        // Packets are written before decoding: no need to decode pictures.
        'vd-lavc-skipframe': 'all',
        'vd-lavc-skipidct': 'all',
        'cache': 'yes',
        'network-timeout': '20',
        'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
        'user-agent': (source.userAgent == null || source.userAgent!.isEmpty) ? 'libmpv' : source.userAgent!,
        'stream-record': path,
      }.entries) {
        await native.setProperty(e.key, e.value);
      }
      final url = StreamUrls.live(source, channel);
      if (!isStreamUrl(url)) throw StateError("Cette chaîne n'a pas d'adresse de flux réseau.");
      _active[r.id] = player;
      activeCount.value = _active.length;
      _repo.updateRecording(r.id, status: RecordingStatus.recording, path: path);
      // The end of the stream or a loading error: the stream is gone.
      _watch[r.id] = [
        player.stream.completed.listen((done) {
          if (done) unawaited(_cut(r.id).then((_) => onChanged()));
        }),
        player.stream.error.listen((e) {
          if (PlayerService.isFatalError(e)) unawaited(_cut(r.id).then((_) => onChanged()));
        }),
      ];
      await player.open(Media(url), play: true);
    } catch (e) {
      debugPrint('Recording failed: ${redactCredentials('$e')}');
      _active.remove(r.id)?.dispose();
      activeCount.value = _active.length;
      _repo.updateRecording(r.id, status: RecordingStatus.failed, error: redactCredentials('$e'));
    }
  }

  Future<void> _finish(int id, {String? note}) async {
    final player = _active.remove(id);
    activeCount.value = _active.length;
    _growth.remove(id);
    for (final s in _watch.remove(id) ?? const <StreamSubscription<Object?>>[]) {
      await s.cancel();
    }
    if (player != null) {
      try {
        await (player.platform as NativePlayer).setProperty('stream-record', '');
        await player.stop();
      } catch (_) {}
      await player.dispose();
    }
    final r = _repo.recording(id);
    if (r == null) return;
    final size = _sizeOf(r.path);
    final ok = size != null && size > _minSize;
    _repo.updateRecording(
      id,
      status: ok ? RecordingStatus.done : RecordingStatus.failed,
      size: size ?? 0,
      stop: DateTime.now().isBefore(r.stop) ? DateTime.now() : null,
      error: ok ? note : 'Aucune vidéo reçue (abonnement limité à une connexion ?)',
    );
  }

  static int? _sizeOf(String? path) {
    if (path == null) return null;
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  Future<void> dispose() async {
    _timer?.cancel();
    for (final id in _active.keys.toList()) {
      await _finish(id, note: "Partiel : arrêté à la fermeture de l'app");
    }
  }
}

/// "[dir]/[name].[extension]", or "[name] (2)", "(3)"… when a file of that
/// name is already there: two recordings of the same programme started in
/// the same minute must not write over each other.
String freeFilePath(String dir, String name, String extension, {bool Function(String path)? exists}) {
  final taken = exists ?? (String path) => File(path).existsSync();
  var path = p.join(dir, '$name.$extension');
  for (var n = 2; taken(path) && n < 1000; n++) {
    path = p.join(dir, '$name ($n).$extension');
  }
  return path;
}
