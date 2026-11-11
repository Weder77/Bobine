import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../core/format.dart';
import '../core/net.dart';
import '../core/text.dart';
import '../core/theme.dart';
import '../core/version.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
import '../services.dart';
import 'settings_screen.dart';
import 'widgets/net_image.dart';

/// Réglages → Diagnostic: versions, storage, connection tests and the
/// recent log, with a report to copy when something goes wrong.
class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const DiagnosticScreen());

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _SourceTest {
  _SourceTest(this.ok, this.message);
  final bool ok;
  final String message;
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  late final AppServices _s = AppScope.of(context);
  final Map<String, String> _player = {};
  int? _dbBytes, _imageBytes, _mpvBytes;
  final Map<int, _SourceTest?> _tests = {};
  final Set<int> _testing = {};

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  Future<void> _load() async {
    for (final (key, prop) in [
      ('mpv', 'mpv-version'),
      ('FFmpeg', 'ffmpeg-version'),
      ('Décodeur', 'hwdec-current'),
      ('Sortie vidéo', 'current-vo'),
      ('Sortie audio', 'current-ao'),
    ]) {
      final v = await _s.player.prop(prop);
      _player[key] = v.isEmpty ? (key == 'mpv' || key == 'FFmpeg' ? 'inconnue' : 'aucune lecture en cours') : v;
    }
    final db = File(_s.dbPath);
    _dbBytes = [db, File('${_s.dbPath}-wal')].fold<int>(0, (a, f) => a + (f.existsSync() ? f.lengthSync() : 0));
    _imageBytes = await _dirSize(ImageFetcher.instance.dir);
    _mpvBytes = await _dirSize(_s.mpvCacheDir);
    if (mounted) setState(() {});
  }

  static Future<int> _dirSize(String path) async {
    var total = 0;
    try {
      await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  Future<void> _test(Source src) async {
    setState(() => _testing.add(src.id));
    final sw = Stopwatch()..start();
    final client = createHttpClient(acceptInvalidCertificate: src.acceptInvalidCertificate);
    _SourceTest result;
    try {
      if (src.isXtream) {
        // The account is checked, not only the answer: an expired one
        // still answers 200.
        final info = await XtreamApi.forSource(src, client: client).authenticate().timeout(const Duration(seconds: 30));
        final exp = info['exp_date'] as int?;
        final until = exp == null || exp <= 0
            ? ''
            : ' · expire le ${formatDay(DateTime.fromMillisecondsSinceEpoch(exp * 1000))}';
        result = _SourceTest(true, 'Compte actif · réponse en ${sw.elapsedMilliseconds} ms$until');
      } else if (src.url.startsWith('http')) {
        final res = await openGet(
          client,
          Uri.parse(src.url),
          userAgent: src.userAgent,
          timeout: const Duration(seconds: 15),
        );
        final firstByte = sw.elapsedMilliseconds;
        var bytes = 0;
        await for (final chunk in guardBody(res, stall: const Duration(seconds: 15))) {
          bytes += chunk.length;
          if (bytes > 256 * 1024) break; // enough to measure
        }
        result = _SourceTest(true, 'HTTP ${res.statusCode} · réponse en $firstByte ms · ${formatBytes(bytes)} reçus');
      } else {
        // No return here: the spinner stayed on for ever.
        final exists = File(src.url).existsSync();
        result = _SourceTest(exists, exists ? 'Fichier local trouvé' : 'Fichier introuvable : ${src.url}');
      }
    } on NetException catch (e) {
      result = _SourceTest(false, redactCredentials(e.message));
    } catch (e) {
      result = _SourceTest(false, redactCredentials('$e'));
    } finally {
      client.close(force: true);
    }
    if (mounted) {
      setState(() {
        _testing.remove(src.id);
        _tests[src.id] = result;
      });
    }
  }

  /// Plain text summary without any password or address with credentials.
  String _report() {
    final b = StringBuffer()
      ..writeln('Rapport Bobine $kAppVersion (${DateTime.now().toIso8601String().substring(0, 19)})')
      ..writeln('Système : ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Dart : ${Platform.version.split(' ').first}');
    for (final e in _player.entries) {
      b.writeln('${e.key} : ${e.value}');
    }
    b
      ..writeln('Base : ${formatBytes(_dbBytes ?? 0)} · images ${formatBytes(_imageBytes ?? 0)}')
      ..writeln(
        'Lecture : cache ${_s.settings.cacheMb} Mo, arrière ${_s.settings.backCacheMb} Mo, '
        'disque ${_s.settings.diskCache ? 'oui' : 'non'}, décodage matériel ${_s.settings.hardwareDecoding ? 'oui' : 'non'}',
      );
    for (final src in _s.repo.sources()) {
      b.writeln(
        'Source « ${src.name} » (${src.type.name}) : ${_s.repo.count(src.id, ContentKind.live)} chaînes, '
        '${_s.repo.count(src.id, ContentKind.movie)} films, ${_s.repo.count(src.id, ContentKind.series)} séries'
        '${src.lastError == null ? '' : ' · erreur : ${redactCredentials(src.lastError!)}'}',
      );
      final t = _tests[src.id];
      if (t != null) b.writeln('  test : ${t.message}');
    }
    b
      ..writeln()
      ..writeln('Journal :');
    for (final l in AppLog.lines.reversed.take(150).toList().reversed) {
      b.writeln(l);
    }
    return anonymizeReport(
      b.toString(),
      sources: _s.repo.sources(),
      home: Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'],
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report()));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rapport copié.')));
  }

  Future<void> _save() async {
    final loc = await getSaveLocation(
      suggestedName: 'bobine-rapport.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Texte', extensions: ['txt']),
      ],
    );
    if (loc == null) return;
    await File(loc.path).writeAsString(_report());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Rapport enregistré : ${p.basename(loc.path)}')));
    }
  }

  Future<void> _clearImages() async {
    try {
      final dir = Directory(ImageFetcher.instance.dir);
      await for (final e in dir.list()) {
        if (e is File) await e.delete();
      }
    } catch (_) {}
    imageCache.clear();
    _imageBytes = await _dirSize(ImageFetcher.instance.dir);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sources = _s.repo.sources();
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Text(k, style: TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(autofocus: true, child: _page(row, sources)),
    );
  }

  Widget _page(Widget Function(String, String) row, List<Source> sources) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Diagnostic', style: displayStyle(22)),
        actions: [
          TextButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copier le rapport'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Enregistrer…'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: settingsPadding(context, top: 12, bottom: 48),
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text(
              'Le rapport ne contient ni mot de passe ni adresse avec identifiants : '
              'tu peux le partager pour obtenir de l’aide.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          SettingsSection(
            title: 'Application',
            children: [
              row('Bobine', kAppVersion),
              row('Système', '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}'),
              row('Dart', Platform.version.split(' ').first),
              for (final e in _player.entries) row(e.key, e.value),
              const SizedBox(height: 8),
            ],
          ),
          SettingsSection(
            title: 'Stockage',
            trailing: OutlinedButton(onPressed: _clearImages, child: const Text('Vider le cache des images')),
            children: [
              row('Base de données', '${formatBytes(_dbBytes ?? 0)} · ${_s.dbPath}'),
              row('Cache des images', formatBytes(_imageBytes ?? 0)),
              row(
                'Cache de lecture',
                '${formatBytes(_mpvBytes ?? 0)} sur le disque · ${_s.settings.cacheMb} Mo en avant, '
                    '${_s.settings.backCacheMb} Mo en arrière',
              ),
              const SizedBox(height: 8),
            ],
          ),
          SettingsSection(
            title: 'Sources',
            children: [
              for (final src in sources)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  title: Text(src.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [
                      '${_s.repo.count(src.id, ContentKind.live)} chaînes · '
                          '${_s.repo.count(src.id, ContentKind.movie)} films · '
                          '${_s.repo.count(src.id, ContentKind.series)} séries',
                      if (src.contentUpdatedAt != null) 'mis à jour ${formatRelative(src.contentUpdatedAt)}',
                      if (src.lastError != null) 'dernière erreur : ${redactCredentials(src.lastError!)}',
                      if (_tests[src.id] != null) _tests[src.id]!.message,
                    ].join('\n'),
                    style: TextStyle(
                      height: 1.5,
                      color: _tests[src.id]?.ok == false ? AppColors.live : AppColors.muted,
                    ),
                  ),
                  trailing: _testing.contains(src.id)
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : OutlinedButton(onPressed: () => _test(src), child: const Text('Tester la connexion')),
                ),
              if (sources.isEmpty) row('Sources', 'Aucune source'),
            ],
          ),
          SettingsSection(
            title: 'Journal récent',
            trailing: TextButton(onPressed: () => setState(() {}), child: const Text('Actualiser')),
            children: [
              Container(
                height: 360,
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    AppLog.lines.isEmpty ? 'Rien pour l’instant.' : AppLog.lines.join('\n'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['Consolas', 'Menlo', 'DejaVu Sans Mono'],
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSoft,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A report meant to be shared: the provider's server, the account name
/// and the source names become "serveur-1", "compte-1", "source-1", the
/// same each time in the report, and the user's folder becomes "~"
/// (a path under C:\Users\Prénom Nom names the person).
@visibleForTesting
String anonymizeReport(String text, {required List<Source> sources, String? home}) {
  final swaps = <String, String>{};
  for (final (i, src) in sources.indexed) {
    final n = i + 1;
    final host = Uri.tryParse(src.isXtream ? src.baseUrl : src.url)?.host;
    if (host != null && host.isNotEmpty) swaps[host] = 'serveur-$n';
    final user = src.username?.trim();
    if (user != null && user.length >= 3) swaps[user] = 'compte-$n';
    if (src.name.trim().length >= 3) swaps.putIfAbsent(src.name.trim(), () => 'source-$n');
  }
  var out = text;
  if (home != null && home.length > 3) out = out.replaceAll(home, '~');
  // Longest first: a host inside a name, a name inside another.
  for (final e in swaps.entries.toList()..sort((a, b) => b.key.length.compareTo(a.key.length))) {
    out = out.replaceAll(
      RegExp('(?<![A-Za-z0-9])${RegExp.escape(e.key)}(?![A-Za-z0-9])', caseSensitive: false),
      e.value,
    );
  }
  return out;
}
