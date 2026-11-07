import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'text.dart';

/// User-Agent used for API / playlist requests when the source does not define one.
const String kDefaultHttpUserAgent = 'Bobine/1.2';

/// Ready-made User-Agent values some IPTV providers expect.
const Map<String, String> kUserAgentPresets = {
  'Par défaut': '',
  'VLC': 'VLC/3.0.21 LibVLC/3.0.21',
  'Kodi': 'Kodi/21.1 (Windows NT 10.0; Win64; x64) App_Bitness/64 Version/21.1',
  'IPTV Smarters': 'IPTVSmartersPro',
  'Navigateur':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Safari/537.36',
};

class NetException implements Exception {
  NetException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

HttpClient createHttpClient() {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 20)
    ..autoUncompress = true
    ..maxConnectionsPerHost = 6;
  // IPTV panels frequently use self-signed / expired certificates.
  client.badCertificateCallback = (cert, host, port) => true;
  return client;
}

Future<HttpClientResponse> openGet(
  HttpClient client,
  Uri uri, {
  String? userAgent,
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      (userAgent == null || userAgent.isEmpty) ? kDefaultHttpUserAgent : userAgent,
    );
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
    request.followRedirects = true;
    request.maxRedirects = 8;
    final response = await request.close().timeout(timeout);
    if (response.statusCode >= 400) {
      // Drain to free the socket.
      unawaited(response.drain<void>().catchError((_) {}));
      throw NetException(_httpError(response.statusCode), statusCode: response.statusCode);
    }
    return response;
  } on NetException {
    rethrow;
  } on TimeoutException {
    throw NetException('Le serveur ne répond pas (délai dépassé).');
  } on SocketException catch (e) {
    throw NetException('Connexion impossible : ${e.osError?.message ?? e.message}');
  } on HandshakeException {
    throw NetException('Erreur de connexion sécurisée (TLS).');
  } on HttpException catch (e) {
    throw NetException('Erreur HTTP : ${redactCredentials(e.message)}');
  } on ArgumentError {
    throw NetException('Adresse invalide : ${redactCredentials(uri.toString())}');
  }
}

String _httpError(int code) {
  switch (code) {
    case 401:
    case 403:
      return 'Accès refusé par le serveur ($code). Vérifie les identifiants ou le User-Agent.';
    case 404:
      return 'Ressource introuvable (404).';
    case 429:
      return 'Trop de requêtes (429). Réessaie plus tard.';
    default:
      return 'Le serveur a répondu avec une erreur $code.';
  }
}

/// Byte stream with automatic gzip detection (XMLTV files are often served as
/// raw .xml.gz without Content-Encoding). Streams, so it is safe for big files.
Stream<List<int>> gunzipIfNeeded(Stream<List<int>> input) {
  late StreamController<List<int>> controller;
  StreamSubscription<List<int>>? sub;
  final head = <int>[];
  var decided = false;
  StreamController<List<int>>? raw;

  controller = StreamController<List<int>>(
    onListen: () {
      sub = input.listen(
        (chunk) {
          if (decided) {
            raw!.add(chunk);
            return;
          }
          head.addAll(chunk);
          if (head.length < 2) return;
          decided = true;
          raw = StreamController<List<int>>(sync: true);
          final isGzip = head[0] == 0x1f && head[1] == 0x8b;
          final Stream<List<int>> decoded = isGzip ? raw!.stream.transform(gzip.decoder) : raw!.stream;
          decoded.listen(controller.add, onError: controller.addError, onDone: controller.close);
          raw!.add(List<int>.of(head));
        },
        onError: controller.addError,
        onDone: () {
          if (!decided) {
            if (head.isNotEmpty) controller.add(head);
            controller.close();
          } else {
            raw!.close();
          }
        },
      );
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () => sub?.cancel(),
  );
  return controller.stream;
}

/// Downloads [uri] as text (UTF-8, tolerant).
Future<String> getText(HttpClient client, Uri uri, {String? userAgent}) async {
  final response = await openGet(client, uri, userAgent: userAgent);
  final bytes = await gunzipIfNeeded(response).fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) => b..add(c));
  return const Utf8Decoder(allowMalformed: true).convert(bytes.takeBytes());
}

/// Downloads and decodes JSON.
Future<Object?> getJson(HttpClient client, Uri uri, {String? userAgent}) async {
  final text = await getText(client, uri, userAgent: userAgent);
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) return null;
  try {
    return jsonDecode(trimmed);
  } on FormatException {
    throw NetException('Réponse inattendue du serveur (JSON invalide).');
  }
}
