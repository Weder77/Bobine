import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../core/format.dart';
import '../../core/text.dart';
import '../models.dart';
import 'importers.dart';

class ImportStatus {
  const ImportStatus({required this.sourceId, required this.stage, this.count = 0});
  final int sourceId;
  final String stage;
  final int count;

  String get label => count > 0 ? '$stage… ${formatCount(count)}' : '$stage…';
}

/// Runs imports in background isolates, one at a time per source, and exposes
/// live progress to the UI.
class ImportService extends ChangeNotifier {
  ImportService({required this.dbPath, required this.onContentChanged, required this.onEpgChanged});

  final String dbPath;
  final void Function(int sourceId) onContentChanged;
  final void Function(int sourceId) onEpgChanged;

  final Map<int, ImportStatus> _running = {};
  final Map<int, Future<void>> _chains = {};
  String? lastMessage;

  bool isBusy(int sourceId) => _running.containsKey(sourceId);
  ImportStatus? status(int sourceId) => _running[sourceId];
  Iterable<ImportStatus> get running => _running.values;

  /// Refreshes content and/or EPG for [source]. Calls are serialised per source.
  Future<void> refresh(Source source, {bool content = true, bool epg = true, int epgDays = 3}) {
    final previous = _chains[source.id] ?? Future.value();
    final next = previous.then((_) => _run(source, content: content, epg: epg, epgDays: epgDays));
    _chains[source.id] = next.catchError((_) {});
    return next;
  }

  Future<void> _run(Source source, {required bool content, required bool epg, required int epgDays}) async {
    final id = source.id;
    final port = ReceivePort();
    port.listen((msg) {
      if (msg is List && msg.length == 2) {
        _running[id] = ImportStatus(sourceId: id, stage: msg[0] as String, count: msg[1] as int);
        notifyListeners();
      }
    });
    final send = port.sendPort;
    final path = dbPath;
    try {
      if (content) {
        _running[id] = ImportStatus(sourceId: id, stage: 'Préparation');
        notifyListeners();
        final result = await _spawnContent(source.isXtream, path, id, send);
        lastMessage =
            '${source.name} : ${formatCount(result.live)} chaînes, '
            '${formatCount(result.movies)} films, ${formatCount(result.series)} séries';
        onContentChanged(id);
      }
      if (epg) {
        _running[id] = ImportStatus(sourceId: id, stage: 'Guide TV');
        notifyListeners();
        try {
          final n = await _spawnEpg(path, id, epgDays, send);
          if (n > 0) onEpgChanged(id);
        } catch (e) {
          // A broken EPG must not fail the whole refresh.
          debugPrint('EPG import failed: $e');
          if (!content) rethrow;
        }
      }
    } catch (e) {
      // Never store or display credentials contained in URLs.
      final message = redactCredentials(e.toString());
      lastMessage = '${source.name} : $message';
      await _spawnError(path, id, message);
      onContentChanged(id);
      rethrow;
    } finally {
      port.close();
      _running.remove(id);
      notifyListeners();
    }
  }
}

// Isolate entry points live in top-level functions so their closures only
// capture sendable values (a closure created inside a method could capture
// `this` or the ReceivePort, which cannot cross isolates).
Future<ContentImportResult> _spawnContent(bool xtream, String path, int id, SendPort send) =>
    Isolate.run(() => xtream ? importXtream(path, id, send) : importM3u(path, id, send));

Future<int> _spawnEpg(String path, int id, int days, SendPort send) =>
    Isolate.run(() => importEpg(path, id, days, send));

Future<void> _spawnError(String path, int id, String message) =>
    Isolate.run(() => recordSourceError(path, id, message));
