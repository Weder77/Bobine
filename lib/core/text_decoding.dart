import 'dart:convert';

/// Turns the bytes of a playlist or a guide into text, in the encoding it
/// is written in. Everything was read as UTF-8: a guide declared
/// `encoding="ISO-8859-1"` or a playlist saved in Windows-1252 showed
/// "Ã©" for "é", or replacement marks.
///
/// The choice is made on the first bytes (up to [sample]): a UTF-8 byte
/// order mark, the encoding an XML declaration names, else UTF-8 when they
/// read as UTF-8, and Latin-1 (which covers Windows-1252 letters) when not.
Stream<String> decodeText(Stream<List<int>> bytes, {int sample = 64 * 1024}) async* {
  final head = <int>[];
  final pending = <String>[];
  Sink<List<int>>? input;
  void start() {
    input = chooseDecoder(head).startChunkedConversion(_Collect(pending));
    input!.add(List<int>.of(head));
    head.clear();
  }

  await for (final chunk in bytes) {
    if (input == null) {
      head.addAll(chunk);
      if (head.length < sample) continue;
      start();
    } else {
      input!.add(chunk);
    }
    if (pending.isNotEmpty) {
      yield pending.join();
      pending.clear();
    }
  }
  if (input == null) start();
  input!.close();
  if (pending.isNotEmpty) yield pending.join();
}

/// The decoder for a text starting with [head] (see [decodeText]).
Converter<List<int>, String> chooseDecoder(List<int> head) {
  const utf8Lenient = Utf8Decoder(allowMalformed: true);
  const latin = Latin1Decoder(allowInvalid: true);
  if (head.length >= 3 && head[0] == 0xEF && head[1] == 0xBB && head[2] == 0xBF) return utf8Lenient;
  final start = latin1.decode(head.length > 512 ? head.sublist(0, 512) : head);
  final declared = RegExp('''<\\?xml[^>]*encoding\\s*=\\s*["']([^"']+)["']''', caseSensitive: false).firstMatch(start);
  if (declared != null) {
    final name = declared.group(1)!.toLowerCase();
    final latinFamily = name.contains('8859') || name.contains('latin') || name.contains('1252');
    return latinFamily ? latin : utf8Lenient;
  }
  // The sample may end in the middle of a character: up to 3 bytes off.
  for (var cut = 0; cut <= 3 && cut <= head.length; cut++) {
    try {
      const Utf8Decoder().convert(head, 0, head.length - cut);
      return utf8Lenient;
    } on FormatException {
      continue;
    }
  }
  return latin;
}

class _Collect implements Sink<String> {
  _Collect(this._out);
  final List<String> _out;

  @override
  void add(String data) {
    if (data.isNotEmpty) _out.add(data);
  }

  @override
  void close() {}
}
