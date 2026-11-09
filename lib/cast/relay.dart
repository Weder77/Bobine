import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/text.dart';
import 'cast_device.dart';
import 'cast_media.dart';

/// Small HTTP server that hands streams to the TV through this computer.
///
/// The TV then gets what the local player gets: the source's User-Agent,
/// redirects already followed, plain HTTP instead of HTTPS with a doubtful
/// certificate, CORS headers (Chromecast needs them for HLS), DLNA headers
/// (some Samsung / LG sets want them) and files of this computer
/// (recordings). HLS playlists are rewritten so that segments go through
/// the relay as well.
///
/// Only addresses published with [publish] are served, under a random token.
class CastRelay {
  CastRelay({HttpClient? client})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 15)
            ..idleTimeout = const Duration(seconds: 20)
            ..autoUncompress = false
            ..maxConnectionsPerHost = 8
            ..badCertificateCallback = (_, _, _) => true);

  final HttpClient _client;
  HttpServer? _server;
  final _routes = <String, _Route>{};
  final _random = Random.secure();

  int? get port => _server?.port;

  /// Address the device at the other end of [host] (this computer's address
  /// on the TV's network) can open to get [target]: an http(s) address,
  /// fetched with [userAgent], or a local file.
  Future<String> publish(String target, {required InternetAddress host, String? userAgent}) async {
    final server = _server ??= await _start();
    final token = List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final origin = 'http://${host.address}:${server.port}';
    final file = isLocalMedia(target);
    _routes[token] = _Route(
      target: target,
      file: file,
      origin: origin,
      userAgent: (userAgent == null || userAgent.isEmpty) ? 'libmpv' : userAgent,
    );
    return '$origin/c/$token/m/${linkName(target)}';
  }

  /// Forgets every published address (requests already running finish).
  void clear() => _routes.clear();

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.idleTimeout = const Duration(seconds: 30);
    server.listen((req) {
      _handle(req).catchError((Object e) {
        debugPrint('Relais cast : ${redactCredentials('$e')}');
        try {
          req.response.statusCode = HttpStatus.badGateway;
          req.response.close();
        } catch (_) {}
      });
    });
    return server;
  }

  Future<void> close() async {
    _routes.clear();
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    _cors(res.headers);
    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      return res.close();
    }
    final seg = req.uri.pathSegments;
    final route = seg.length >= 3 && seg[0] == 'c' ? _routes[seg[1]] : null;
    String? target;
    if (route != null && seg[2] == 'm') {
      target = route.target;
    } else if (route != null && seg[2] == 'u' && seg.length >= 4 && !route.file) {
      try {
        target = utf8.decode(base64Url.decode(base64Url.normalize(seg[3])));
      } on FormatException {
        target = null;
      }
    }
    if (route == null || target == null || (req.method != 'GET' && req.method != 'HEAD')) {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    if (route.file && seg[2] == 'm') return _serveFile(req, target);
    final uri = Uri.tryParse(target);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    return _proxy(req, route, uri, token: seg[1]);
  }

  Future<void> _proxy(HttpRequest req, _Route route, Uri uri, {required String token}) async {
    final res = req.response;
    final head = req.method == 'HEAD';
    final up = await _client.openUrl(head ? 'HEAD' : 'GET', uri).timeout(const Duration(seconds: 20));
    up.followRedirects = true;
    up.maxRedirects = 8;
    up.headers
      ..set(HttpHeaders.userAgentHeader, route.userAgent)
      ..set(HttpHeaders.acceptEncodingHeader, 'identity')
      ..set(HttpHeaders.acceptHeader, '*/*');
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) up.headers.set(HttpHeaders.rangeHeader, range);
    final upRes = await up.close().timeout(const Duration(seconds: 25));
    var finalUri = uri;
    for (final r in upRes.redirects) {
      finalUri = finalUri.resolveUri(r.location);
    }
    final type = upRes.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (upRes.statusCode >= 400) {
      res.statusCode = upRes.statusCode;
      unawaited(upRes.drain<void>().catchError((_) {}));
      return res.close();
    }
    final playlist = type.contains('mpegurl') || isHlsUrl(finalUri.toString());
    if (playlist && !head) {
      final text = await _readText(upRes);
      if (text.trimLeft().startsWith('#EXTM3U')) {
        final body = utf8.encode(
          rewritePlaylist(
            text,
            finalUri,
            (abs) => '${route.origin}/c/$token/u/${encodeLink(abs)}/${linkName(abs.toString())}',
          ),
        );
        res.statusCode = HttpStatus.ok;
        res.headers
          ..set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl')
          ..set(HttpHeaders.cacheControlHeader, 'no-cache');
        res.contentLength = body.length;
        res.add(body);
        return res.close();
      }
      // Not a playlist after all: send it as it came.
      final bytes = utf8.encode(text);
      res.statusCode = upRes.statusCode;
      res.contentLength = bytes.length;
      res.add(bytes);
      return res.close();
    }
    res.statusCode = upRes.statusCode;
    final mime = (type.isEmpty || type == 'application/octet-stream' || type == 'text/plain')
        ? castContentType(finalUri.toString(), live: upRes.contentLength < 0, protocol: _relayProtocol)
        : upRes.headers.value(HttpHeaders.contentTypeHeader)!;
    res.headers.set(HttpHeaders.contentTypeHeader, mime);
    for (final h in const [
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.lastModifiedHeader,
    ]) {
      final v = upRes.headers.value(h);
      if (v != null) res.headers.set(h, v);
    }
    final encoding = upRes.headers.value(HttpHeaders.contentEncodingHeader);
    if (encoding != null) res.headers.set(HttpHeaders.contentEncodingHeader, encoding);
    _dlna(res.headers, seekable: upRes.contentLength >= 0);
    if (upRes.contentLength >= 0) res.contentLength = upRes.contentLength;
    if (head) {
      unawaited(upRes.drain<void>().catchError((_) {}));
      return res.close();
    }
    await _pipe(upRes, res);
  }

  /// Sends the headers set on [res], then copies [from] to the TV at the
  /// pace the TV reads it. The provider is let go as soon as the TV hangs up
  /// (zapping, stop): the raw socket tells it, the HTTP response does not.
  static Future<void> _pipe(Stream<List<int>> from, HttpResponse res) async {
    final sub = from.listen(null)..pause();
    res.headers
      ..chunkedTransferEncoding = false
      ..persistentConnection = false;
    final Socket socket;
    try {
      socket = await res.detachSocket();
    } catch (_) {
      await sub.cancel();
      return;
    }
    final finished = Completer<void>();
    var gone = false;
    void end() {
      if (!finished.isCompleted) finished.complete();
    }

    void hangUp() {
      gone = true;
      unawaited(sub.cancel().catchError((_) {}));
      end();
    }

    socket.listen((_) {}, onDone: hangUp, onError: (Object _) => hangUp(), cancelOnError: true);
    sub
      ..onData((chunk) {
        if (gone) return;
        socket.add(chunk);
        // Waits until the TV took it: no memory build-up on fast providers.
        sub.pause(socket.flush().then((_) {}, onError: (_) => hangUp()));
      })
      ..onError((Object _) => hangUp())
      ..onDone(end)
      ..resume();
    await finished.future;
    if (gone) {
      socket.destroy();
      return;
    }
    try {
      await socket.close().timeout(const Duration(seconds: 10));
    } catch (_) {}
    socket.destroy();
  }

  Future<void> _serveFile(HttpRequest req, String path) async {
    final res = req.response;
    final file = File(path);
    if (!await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    final length = await file.length();
    res.headers
      ..set(HttpHeaders.contentTypeHeader, castContentType(path, live: false, protocol: _relayProtocol))
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    _dlna(res.headers, seekable: true);
    final range = parseByteRange(req.headers.value(HttpHeaders.rangeHeader), length);
    var start = 0, end = length - 1;
    if (range == badRange) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      return res.close();
    }
    if (range != null) {
      (start, end) = range;
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    }
    res.contentLength = length == 0 ? 0 : end - start + 1;
    if (req.method == 'HEAD' || length == 0) return res.close();
    await _pipe(file.openRead(start, end + 1), res);
  }

  static Future<String> _readText(Stream<List<int>> s) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in s) {
      b.add(chunk);
      if (b.length > 8 << 20) throw const HttpException('Playlist trop grande');
    }
    return const Utf8Decoder(allowMalformed: true).convert(b.takeBytes());
  }

  static void _cors(HttpHeaders h) {
    h
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*')
      ..set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges, Content-Type');
  }

  static void _dlna(HttpHeaders h, {required bool seekable}) {
    h
      ..set('transferMode.dlna.org', 'Streaming')
      ..set(
        'contentFeatures.dlna.org',
        'DLNA.ORG_OP=${seekable ? '01' : '00'};DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000',
      );
  }
}

// Content types the relay announces are those of DLNA renderers (the real
// types); a Chromecast gets its own in the LOAD message anyway.
const _relayProtocol = CastProtocol.dlna;

class _Route {
  _Route({required this.target, required this.file, required this.origin, required this.userAgent});
  final String target;
  final bool file;
  final String origin;
  final String userAgent;
}

/// Rewrites the addresses of an HLS playlist with [link] (absolute address
/// → relayed address): variants, segments, keys, maps and renditions.
String rewritePlaylist(String text, Uri base, String Function(Uri absolute) link) {
  String one(String ref) {
    try {
      return link(base.resolve(ref.trim()));
    } on FormatException {
      return ref;
    }
  }

  final out = StringBuffer();
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) {
      out.write('\n');
    } else if (line.startsWith('#')) {
      out
        ..write(line.replaceAllMapped(RegExp(r'URI="([^"]*)"'), (m) => 'URI="${one(m[1]!)}"'))
        ..write('\n');
    } else {
      out
        ..write(one(line))
        ..write('\n');
    }
  }
  return out.toString();
}

/// URL-safe form of an address, for the relay path.
String encodeLink(Uri u) => base64Url.encode(utf8.encode(u.toString())).replaceAll('=', '');

/// Last part of the address ("1234.ts"), kept so devices see the extension.
String linkName(String target) {
  final path = isLocalMedia(target) ? target.replaceAll('\\', '/') : (Uri.tryParse(target)?.path ?? '');
  var name = path.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => 'media');
  name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (name.length > 60) name = name.substring(name.length - 60);
  return name.isEmpty ? 'media' : name;
}

/// Marker returned by [parseByteRange] for a range outside the file.
const badRange = (-1, -1);

/// Reads a "Range: bytes=…" header for a file of [length] bytes: the first
/// and last byte, null when absent (whole file), [badRange] when outside.
(int, int)? parseByteRange(String? header, int length) {
  if (header == null) return null;
  final m = RegExp(r'^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*(?:,.*)?$').firstMatch(header);
  if (m == null) return null;
  final a = m.group(1)!, b = m.group(2)!;
  if (a.isEmpty && b.isEmpty) return null;
  if (a.isEmpty) {
    final suffix = int.parse(b);
    if (suffix == 0) return badRange;
    return (max(0, length - suffix), length - 1);
  }
  final start = int.parse(a);
  if (start >= length) return badRange;
  final end = b.isEmpty ? length - 1 : min(int.parse(b), length - 1);
  if (end < start) return badRange;
  return (start, end);
}
