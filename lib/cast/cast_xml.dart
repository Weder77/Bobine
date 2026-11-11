import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/import/xmltv_parser.dart' show decodeEntities;

/// Largest description or answer read from a device: a real one is a few
/// kilobytes. Anything a device of the network sends is not trusted.
const int kMaxDeviceAnswer = 256 << 10;

/// The body of [res] as text, at most [max] bytes and within [timeout]
/// (the download is stopped, not just stopped being waited for).
Future<String> readDeviceAnswer(HttpClientResponse res, {required Duration timeout, int max = kMaxDeviceAnswer}) {
  final done = Completer<String>();
  final bytes = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> sub;
  final timer = Timer(timeout, () {
    sub.cancel();
    if (!done.isCompleted) done.completeError(TimeoutException('Réponse trop lente', timeout));
  });
  sub = res.listen(
    (chunk) {
      bytes.add(chunk);
      if (bytes.length > max) {
        timer.cancel();
        sub.cancel();
        if (!done.isCompleted) done.completeError(const HttpException('Réponse trop grande'));
      }
    },
    onError: (Object e) {
      timer.cancel();
      if (!done.isCompleted) done.completeError(e);
    },
    onDone: () {
      timer.cancel();
      if (!done.isCompleted) done.complete(const Utf8Decoder(allowMalformed: true).convert(bytes.takeBytes()));
    },
    cancelOnError: true,
  );
  return done.future;
}

/// The contents of the elements [name] of [xml] (any namespace prefix), in
/// order. Each element is found by its opening tag, then the next closing
/// one: no expression that scans the rest of the text from every opening
/// tag, so a hostile text costs linear time.
Iterable<String> xmlElements(String xml, String name, {bool caseSensitive = false}) sync* {
  final open = RegExp('<(?:[\\w-]{1,32}:)?$name(?:\\s[^>]{0,2048})?>', caseSensitive: caseSensitive);
  final close = RegExp('</(?:[\\w-]{1,32}:)?$name\\s*>', caseSensitive: caseSensitive);
  var from = 0;
  while (from < xml.length) {
    final o = open.allMatches(xml, from).firstOrNull;
    if (o == null) return;
    final c = close.allMatches(xml, o.end).firstOrNull;
    if (c == null) return;
    yield xml.substring(o.end, c.start);
    from = c.end;
  }
}

/// Text of the first element [name] of [xml], entities decoded; null when
/// absent or empty.
String? xmlText(String xml, String name, {bool caseSensitive = false}) {
  final v = xmlElements(xml, name, caseSensitive: caseSensitive).firstOrNull?.trim();
  return (v == null || v.isEmpty) ? null : decodeEntities(v);
}
