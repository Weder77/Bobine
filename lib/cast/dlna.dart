import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/version.dart';
import '../data/import/xmltv_parser.dart' show decodeEntities;

import 'package:flutter/foundation.dart';

import 'cast_device.dart';
import 'cast_media.dart';
import 'cast_session.dart';

/// Drives a DLNA / UPnP media renderer (SOAP on its AVTransport and
/// RenderingControl services). Polled: renderers rarely send events reliably.
class DlnaSession implements CastSession {
  DlnaSession(this.device, {HttpClient? client})
    : _http =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 6)
            ..idleTimeout = const Duration(seconds: 15));

  @override
  final CastDevice device;
  final HttpClient _http;

  @override
  InternetAddress? localAddress;

  @override
  Stream<RemoteStatus> get updates => const Stream.empty();

  bool _live = false;
  bool _wasPlaying = false;
  bool _stopping = false;
  int _polls = 0;
  double? _volume;
  Duration _lastPosition = Duration.zero;
  Duration? _duration;

  /// Formats the renderer says it accepts ("http-get:*:video/x-mkv:*"…).
  List<String> sink = const [];

  String get _avType => device.avTransportType ?? 'urn:schemas-upnp-org:service:AVTransport:1';

  @override
  Future<void> connect() async {
    if (device.avTransport == null) throw CastException("Cet appareil ne sait pas lire de vidéo.");
    try {
      final s = await Socket.connect(device.host, device.port, timeout: const Duration(seconds: 6));
      localAddress = s.address;
      s.destroy();
    } on SocketException {
      throw CastException("L'appareil ne répond pas. Vérifie qu'il est allumé et sur le même réseau.");
    } on TimeoutException {
      throw CastException("L'appareil ne répond pas. Vérifie qu'il est allumé et sur le même réseau.");
    }
    final cm = device.connectionManager;
    if (cm != null) {
      try {
        final body = await soap(cm, device.connectionManagerType!, 'GetProtocolInfo', const []);
        sink = parseSinkProtocols(soapValue(body, 'Sink') ?? '');
        debugPrint('Cast DLNA : « ${device.name} » accepte ${sink.length} formats');
      } catch (e) {
        debugPrint('Cast DLNA : formats de « ${device.name} » inconnus ($e)');
      }
    }
  }

  @override
  String contentTypeFor(String url, {required bool live}) =>
      rendererMime(castContentType(url, live: live, protocol: CastProtocol.dlna), sink);

  @override
  Future<void> load(CastMedia media, {Duration? start}) async {
    _live = media.live;
    _wasPlaying = false;
    _stopping = false;
    _duration = null;
    _lastPosition = Duration.zero;
    final args = [('InstanceID', '0'), ('CurrentURI', media.url), ('CurrentURIMetaData', didlLite(media))];
    debugPrint('Cast DLNA : « ${device.name} » ← ${media.contentType}${_listed(media.contentType)}');
    try {
      await _av('SetAVTransportURI', args);
    } on CastException {
      // Some renderers refuse a new address while something plays.
      try {
        await _av('Stop', const [('InstanceID', '0')]);
      } catch (_) {}
      await _av('SetAVTransportURI', args);
    }
    try {
      await _av('Play', const [('InstanceID', '0'), ('Speed', '1')]);
    } on CastException {
      // Some start by themselves and answer an error to Play: check below.
    }
    if (start != null && start.inSeconds > 5 && !media.live) unawaited(_seekWhenPlaying(start));
  }

  /// " (listé par la télé)" or the formats of the same family it lists, for the log.
  String _listed(String mime) {
    if (sink.isEmpty) return '';
    final m = mime.toLowerCase();
    if (sink.any((p) => p.toLowerCase().contains(':$m:'))) return ' (listé par la télé)';
    final video = sink.map((p) => p.split(':')).where((p) => p.length >= 3 && p[2].startsWith('video/'));
    final names = {for (final p in video) p[2]}.take(12).join(', ');
    return ' (pas dans sa liste : $names)';
  }

  /// Renderers only accept a seek once the stream has started.
  Future<void> _seekWhenPlaying(Duration to) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        final state = await _transportState();
        if (state == 'PLAYING' || state == 'PAUSED_PLAYBACK') {
          await seek(to);
          return;
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> play() => _av('Play', const [('InstanceID', '0'), ('Speed', '1')]);

  @override
  Future<void> pause() => _av('Pause', const [('InstanceID', '0')]);

  @override
  Future<void> seek(Duration position) =>
      _av('Seek', [('InstanceID', '0'), ('Unit', 'REL_TIME'), ('Target', formatUpnpTime(position))]);

  @override
  Future<void> setVolume(double level) async {
    final control = device.renderingControl;
    if (control == null) throw CastException('Le volume se règle sur la télé.');
    final v = (level.clamp(0, 1) * 100).round();
    await soap(control, device.renderingControlType!, 'SetVolume', [
      ('InstanceID', '0'),
      ('Channel', 'Master'),
      ('DesiredVolume', '$v'),
    ]);
    _volume = v / 100;
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    await _av('Stop', const [('InstanceID', '0')]);
  }

  Future<String> _transportState() async {
    final body = await _av('GetTransportInfo', const [('InstanceID', '0')]);
    return soapValue(body, 'CurrentTransportState') ?? '';
  }

  @override
  Future<RemoteStatus> poll() async {
    final info = await _av('GetTransportInfo', const [('InstanceID', '0')]);
    final state = soapValue(info, 'CurrentTransportState') ?? '';
    final status = soapValue(info, 'CurrentTransportStatus') ?? 'OK';
    final pos = await _av('GetPositionInfo', const [('InstanceID', '0')]);
    final position = parseUpnpTime(soapValue(pos, 'RelTime'));
    final duration = parseUpnpTime(soapValue(pos, 'TrackDuration'));
    if (position != null) _lastPosition = position;
    if (duration != null && duration > Duration.zero) _duration = duration;
    if (device.renderingControl != null && _polls++ % 5 == 0) {
      try {
        final v = await soap(device.renderingControl!, device.renderingControlType!, 'GetVolume', const [
          ('InstanceID', '0'),
          ('Channel', 'Master'),
        ]);
        final n = int.tryParse(soapValue(v, 'CurrentVolume') ?? '');
        if (n != null) _volume = (n / 100).clamp(0, 1).toDouble();
      } catch (_) {}
    }
    RemoteState remote;
    String? error;
    switch (state) {
      case 'PLAYING':
        remote = RemoteState.playing;
        _wasPlaying = true;
      case 'PAUSED_PLAYBACK' || 'PAUSED_RECORDING':
        remote = RemoteState.paused;
      case 'TRANSITIONING':
        remote = _wasPlaying ? RemoteState.buffering : RemoteState.loading;
      case 'STOPPED' || 'NO_MEDIA_PRESENT':
        if (!_wasPlaying && !_stopping) {
          // Not started yet (or refused).
          remote = status == 'ERROR_OCCURRED' ? RemoteState.error : RemoteState.loading;
        } else if (!_live && _duration != null && _lastPosition >= _duration! - const Duration(seconds: 20)) {
          remote = RemoteState.ended;
        } else {
          remote = RemoteState.idle;
        }
      default:
        remote = RemoteState.loading;
    }
    if (status == 'ERROR_OCCURRED' && remote != RemoteState.playing) {
      remote = RemoteState.error;
      error = "La télé n'a pas pu lire ce flux.";
    }
    return RemoteStatus(
      state: remote,
      position: _lastPosition,
      duration: _live ? null : _duration,
      volume: _volume,
      error: error,
    );
  }

  @override
  Future<void> close() async {
    _http.close(force: true);
  }

  Future<String> _av(String action, List<(String, String)> args) => soap(device.avTransport!, _avType, action, args);

  /// Calls [action] of the service [type] at [control]; returns the answer.
  Future<String> soap(Uri control, String type, String action, List<(String, String)> args) async {
    const timeout = Duration(seconds: 8);
    try {
      final req = await _http.postUrl(control).timeout(timeout);
      final body = utf8.encode(soapEnvelope(type, action, args));
      req.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
        ..set('SOAPACTION', '"$type#$action"')
        ..set(HttpHeaders.userAgentHeader, '${Platform.operatingSystem}/1 UPnP/1.1 Bobine/$kAppVersion');
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(timeout);
      final text = await res.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(timeout);
      if (res.statusCode >= 300) {
        final code = soapValue(text, 'errorCode');
        final description = soapValue(text, 'errorDescription');
        throw CastException(upnpErrorMessage(action, int.tryParse(code ?? ''), description, res.statusCode));
      }
      return text;
    } on TimeoutException {
      throw CastException('La télé ne répond plus.');
    } on SocketException {
      throw CastException('Connexion perdue avec la télé.');
    } on HttpException {
      throw CastException('Connexion perdue avec la télé.');
    }
  }
}

/// SOAP request body.
String soapEnvelope(String type, String action, List<(String, String)> args) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="utf-8"?>')
    ..write(
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>',
    )
    ..write('<u:$action xmlns:u="${xmlEscape(type)}">');
  for (final (k, v) in args) {
    b.write('<$k>${xmlEscape(v)}</$k>');
  }
  b.write('</u:$action></s:Body></s:Envelope>');
  return b.toString();
}

/// Text of the element [name] in a SOAP answer (namespace prefix ignored).
String? soapValue(String xml, String name) {
  final m = RegExp('<(?:[\\w-]+:)?$name(?:\\s[^>]*)?>(.*?)</(?:[\\w-]+:)?$name\\s*>', dotAll: true).firstMatch(xml);
  if (m == null) return null;
  return decodeEntities(m.group(1)!.trim());
}

String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Description of [media] that renderers show (title, picture) and use to
/// pick a player (protocolInfo).
String didlLite(CastMedia media) {
  // DLNA flags: streaming transfer, background, stalling, DLNA 1.5.
  // OP=01: seeking by byte range (films); 00 for live streams.
  final op = media.live ? '00' : '01';
  final info =
      'http-get:*:${media.contentType}:DLNA.ORG_OP=$op;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000';
  final b = StringBuffer()
    ..write(
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
      'xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">',
    )
    ..write('<item id="bobine" parentID="-1" restricted="1">')
    ..write('<dc:title>${xmlEscape(media.title)}</dc:title>');
  if (media.subtitle != null && media.subtitle!.isNotEmpty) {
    b.write('<dc:description>${xmlEscape(media.subtitle!)}</dc:description>');
  }
  if (media.image != null && media.image!.startsWith('http')) {
    b.write('<upnp:albumArtURI>${xmlEscape(media.image!)}</upnp:albumArtURI>');
  }
  b
    ..write('<upnp:class>${media.live ? 'object.item.videoItem.videoBroadcast' : 'object.item.videoItem'}</upnp:class>')
    ..write('<res protocolInfo="${xmlEscape(info)}">${xmlEscape(media.url)}</res>')
    ..write('</item></DIDL-Lite>');
  return b.toString();
}

/// "01:02:03" (UPnP time).
String formatUpnpTime(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
}

/// Reads "1:02:03", "01:02:03.500"; null for "NOT_IMPLEMENTED" or empty.
Duration? parseUpnpTime(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+))?').firstMatch(v.trim());
  if (m == null) return null;
  final fraction = m.group(4);
  final ms = fraction == null ? 0 : (double.parse('0.$fraction') * 1000).round();
  return Duration(
    hours: int.parse(m.group(1)!),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    milliseconds: ms,
  );
}

/// French message for a failed UPnP action.
String upnpErrorMessage(String action, int? code, String? description, int status) {
  switch (code) {
    case 701 || 710:
      return action == 'Seek' ? "La télé ne permet pas d'avancer dans ce flux." : "La télé a refusé l'action.";
    case 711 || 714 || 716:
      return "La télé ne lit pas ce type de flux.";
    case 715:
      return "La télé n'a pas pu ouvrir le flux.";
  }
  final detail = (description == null || description.isEmpty) ? 'erreur ${code ?? status}' : description;
  return "La télé a refusé l'action ($detail).";
}

/// Entries of a GetProtocolInfo "Sink" list (comma separated, commas inside
/// the fourth field are not separators).
List<String> parseSinkProtocols(String csv) {
  final out = <String>[];
  for (final raw in csv.split(',')) {
    final v = raw.trim();
    if (v.isEmpty) continue;
    if (v.split(':').length < 4 && out.isNotEmpty) {
      out[out.length - 1] = '${out.last},$v';
    } else {
      out.add(v);
    }
  }
  return out;
}
