import 'dart:async';
import 'dart:io';

import '../core/text.dart';
import 'cast_device.dart';
import 'cast_media.dart';
import 'cast_session.dart';
import 'dlna.dart';
import 'relay.dart';

/// One way of presenting a video to a DLNA TV.
class CastVariant {
  const CastVariant(this.label, {required this.mime, this.features, this.metadata = true, this.direct = false});

  /// "video/x-matroska, description de Bobine".
  final String label;

  /// Type announced in the description and sent by the relay.
  final String mime;

  /// Fourth field of protocolInfo; null: Bobine's DLNA flags.
  final String? features;

  /// Whether a DIDL-Lite description goes with the address.
  final bool metadata;

  /// The provider's address instead of the relay.
  final bool direct;
}

/// What the TV did with one variant.
class CastVariantResult {
  CastVariantResult(this.variant);
  final CastVariant variant;

  /// SetAVTransportURI accepted.
  bool accepted = false;

  /// Refusal ("714 Illegal MIME-type").
  String? refusal;

  /// Tried in the playing step.
  bool tried = false;

  /// The TV played it (state PLAYING and position moving or data read).
  bool played = false;

  /// Transport states seen, in order ("TRANSITIONING → PLAYING").
  final states = <String>[];
  Duration position = Duration.zero;

  /// Bytes the TV read through the relay.
  int bytes = 0;
  String? playError;
}

/// The variants worth trying for [target] on a TV accepting [sink].
List<CastVariant> castVariants(String target, List<String> sink, {required bool live}) {
  final base = castContentType(target, live: live, protocol: CastProtocol.dlna);
  final out = <CastVariant>[
    CastVariant('$base, description de Bobine', mime: base),
    CastVariant('$base, sans description', mime: base, metadata: false),
  ];
  // The TV's own spellings of the same format, with its own fourth field.
  final family = rendererMimes(base, sink);
  for (final (mime, features) in family) {
    if (mime.toLowerCase() == base.toLowerCase() && features == dlnaFeatures(live: live)) continue;
    out.add(CastVariant('$mime, comme dans la liste de la télé ($features)', mime: mime, features: features));
  }
  out.add(CastVariant('$base, sans drapeaux DLNA (*)', mime: base, features: '*'));
  for (final (mime, _) in family) {
    if (mime.toLowerCase() != base.toLowerCase()) {
      out.add(CastVariant('$mime, sans description', mime: mime, metadata: false));
    }
  }
  if (base != 'video/mp4') out.add(const CastVariant('video/mp4 (type forcé)', mime: 'video/mp4'));
  if (base != 'video/mpeg' && !live) out.add(const CastVariant('video/mpeg (type forcé)', mime: 'video/mpeg'));
  if (target.startsWith('http://') || target.startsWith('https://')) {
    out.add(CastVariant('adresse du fournisseur en direct, $base', mime: base, direct: true));
  }
  // Same variant twice (e.g. no spelling of its own): once is enough.
  final seen = <String>{};
  return [
    for (final v in out)
      if (seen.add('${v.mime.toLowerCase()}|${v.features}|${v.metadata}|${v.direct}')) v,
  ];
}

/// Tries [castVariants] on a DLNA TV: which ones it accepts, then which one
/// it really plays. Used by `tool/cast_test.dart`.
class CastTester {
  CastTester(this.session, this.relay, {this.say = print, this.watch = const Duration(seconds: 15)});

  final DlnaSession session;
  final CastRelay relay;
  final void Function(String line) say;

  /// How long the TV is watched once it was told to play.
  final Duration watch;

  String get _av => session.device.avTransportType ?? 'urn:schemas-upnp-org:service:AVTransport:1';

  Future<String> _soap(String action, List<(String, String)> args) =>
      session.soap(session.device.avTransport!, _av, action, args);

  Future<void> _stop() async {
    try {
      await _soap('Stop', const [('InstanceID', '0')]);
    } catch (_) {}
  }

  Future<String> _address(CastVariant v, String target, String? userAgent) async {
    if (v.direct) return target;
    return relay.publish(target, host: session.localAddress!, userAgent: userAgent, contentType: v.mime);
  }

  Future<void> _set(CastVariant v, String url, bool live) async {
    final media = CastMedia(url: url, contentType: v.mime, live: live, title: 'Test Bobine');
    await _soap('SetAVTransportURI', [
      ('InstanceID', '0'),
      ('CurrentURI', url),
      ('CurrentURIMetaData', v.metadata ? didlLite(media, features: v.features) : ''),
    ]);
  }

  /// Runs every variant; stops at the first one the TV plays unless [all].
  Future<List<CastVariantResult>> run(String target, {required bool live, String? userAgent, bool all = false}) async {
    final variants = castVariants(target, session.sink, live: live);
    final results = [for (final v in variants) CastVariantResult(v)];
    say('Étape 1 : ce que la télé accepte (${variants.length} façons de présenter la vidéo)');
    for (final (i, r) in results.indexed) {
      await _stop();
      try {
        await _set(r.variant, await _address(r.variant, target, userAgent), live);
        r.accepted = true;
        say('  [${i + 1}] ${r.variant.label} : acceptée');
      } on CastException catch (e) {
        r.refusal = e.code == null ? e.message : '${e.code} ${e.detail ?? e.message}';
        say('  [${i + 1}] ${r.variant.label} : refusée (${r.refusal})');
      }
    }
    await _stop();
    final accepted = results.where((r) => r.accepted).toList();
    if (accepted.isEmpty) {
      say('La télé a refusé toutes les façons de présenter la vidéo.');
      return results;
    }
    say('');
    say('Étape 2 : ce que la télé arrive à lire (${watch.inSeconds} s par essai, regarde la télé)');
    for (final r in accepted) {
      final i = results.indexOf(r) + 1;
      say('  [$i] ${r.variant.label}…');
      await _play(r, target, live, userAgent);
      say(
        r.played
            ? '      ✔ la télé lit la vidéo (${r.states.join(' → ')}, position ${formatUpnpTime(r.position)}'
                  '${r.variant.direct ? '' : ', ${_mb(r.bytes)} lus'})'
            : '      ✘ pas de lecture (${r.states.isEmpty ? 'aucun état' : r.states.join(' → ')}'
                  '${r.variant.direct ? '' : ', ${_mb(r.bytes)} lus'}${r.playError == null ? '' : ', ${r.playError}'})',
      );
      await _stop();
      if (r.played && !all) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return results;
  }

  Future<void> _play(CastVariantResult r, String target, bool live, String? userAgent) async {
    r.tried = true;
    final sentBefore = relay.sent;
    try {
      await _set(r.variant, await _address(r.variant, target, userAgent), live);
    } on CastException catch (e) {
      r.playError = 'refusée cette fois (${e.code ?? e.message})';
      return;
    }
    try {
      await _soap('Play', const [('InstanceID', '0'), ('Speed', '1')]);
    } on CastException catch (e) {
      r.playError = 'Play refusé (${e.code ?? ''} ${e.detail ?? e.message})'.trim();
    }
    final end = DateTime.now().add(watch);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final info = await _soap('GetTransportInfo', const [('InstanceID', '0')]);
        final state = soapValue(info, 'CurrentTransportState') ?? '?';
        final status = soapValue(info, 'CurrentTransportStatus') ?? '';
        final label = status.isEmpty || status == 'OK' ? state : '$state/$status';
        if (r.states.isEmpty || r.states.last != label) r.states.add(label);
        final pos = await _soap('GetPositionInfo', const [('InstanceID', '0')]);
        r.position = parseUpnpTime(soapValue(pos, 'RelTime')) ?? r.position;
      } on CastException catch (e) {
        r.playError = e.message;
      }
      r.bytes = relay.sent - sentBefore;
      final reading = r.position > Duration.zero || (!r.variant.direct && r.bytes > 1 << 20);
      if (r.states.isNotEmpty && r.states.last.startsWith('PLAYING') && reading) {
        r.played = true;
        // A few more seconds to be sure it keeps going.
        if (DateTime.now().isAfter(end.subtract(watch ~/ 2))) break;
      }
    }
  }

  static String _mb(int bytes) => '${(bytes / (1 << 20)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

/// The report written next to the tool: everything, without passwords.
String castTestReport({
  required DlnaSession session,
  required String target,
  required List<CastVariantResult> results,
  required List<RelayRequest> requests,
  required List<String> log,
}) {
  final d = session.device;
  final b = StringBuffer()
    ..writeln('Bobine — test du cast DLNA, ${DateTime.now()}')
    ..writeln('Système : ${Platform.operatingSystemVersion}')
    ..writeln()
    ..writeln('Télé : ${d.name} (${d.manufacturer ?? '?'} ${d.model ?? ''}) en ${d.host}:${d.port}')
    ..writeln('Cet ordinateur vu de la télé : ${session.localAddress?.address}')
    ..writeln('Vidéo : ${redactCredentials(target)}')
    ..writeln()
    ..writeln('Résultats :');
  for (final (i, r) in results.indexed) {
    b.write('  [${i + 1}] ${r.variant.label} : ');
    if (!r.accepted) {
      b.writeln('refusée (${r.refusal})');
    } else if (!r.tried) {
      b.writeln('acceptée (lecture non essayée)');
    } else {
      b.writeln(
        '${r.played ? 'LUE' : 'acceptée'}'
        '${r.states.isEmpty ? '' : ', états ${r.states.join(' → ')}'}'
        ', position ${formatUpnpTime(r.position)}, ${r.bytes} octets lus'
        '${r.playError == null ? '' : ', ${r.playError}'}',
      );
    }
  }
  b
    ..writeln()
    ..writeln('Requêtes de la télé au relais :');
  for (final q in requests) {
    b.writeln('  ${q.method} ${q.name} → ${q.result}');
    for (final MapEntry(:key, :value) in q.headers.entries) {
      b.writeln('      $key: $value');
    }
  }
  b
    ..writeln()
    ..writeln('Formats vidéo annoncés par la télé (${session.sink.length} au total) :');
  for (final p in session.sink.where((p) => p.contains(':video/') || p.contains('mpegurl'))) {
    b.writeln('  $p');
  }
  b
    ..writeln()
    ..writeln('Journal :');
  for (final l in log) {
    b.writeln('  ${redactCredentials(l)}');
  }
  return b.toString();
}
