import 'dart:io';

import 'package:bobine/core/open_url.dart';
import 'package:bobine/features/tmdb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calls = <(String, List<String>)>[];
  Future<ProcessResult> run(String exe, List<String> args) async {
    calls.add((exe, args));
    return ProcessResult(1, 0, '', '');
  }

  setUp(calls.clear);

  test('a web address is opened without any command interpreter, as one argument', () async {
    // "&" used to end the "start" command of cmd and run what followed.
    expect(await openExternal('https://x.example/watch?v=1&calc.exe', run: run, os: 'windows'), isTrue);
    expect(calls.single.$1, 'rundll32');
    expect(calls.single.$2, ['url.dll,FileProtocolHandler', 'https://x.example/watch?v=1&calc.exe']);
    calls.clear();
    expect(await openExternal('https://x.example/a', run: run, os: 'macos'), isTrue);
    expect(await openExternal('https://x.example/a', run: run, os: 'linux'), isTrue);
    expect(calls.map((c) => c.$1), ['open', 'xdg-open']);
    expect(calls.every((c) => c.$2.length == 1), isTrue);
  });

  test('quotes, spaces, carets and line breaks never reach the system as they are', () async {
    for (final hostile in [
      'https://a.example/" & calc & "',
      'https://a.example/^|<>b',
      'https://a.example/%COMSPEC%',
      'https://a.example/\r\nstart calc',
      '  HTTPS://A.example/a b  ',
    ]) {
      calls.clear();
      expect(
        await openExternal(hostile, run: run, os: 'windows'),
        isTrue,
        reason: hostile,
      );
      final sent = calls.single.$2.last;
      expect(sent, startsWith('https://a.example/'), reason: hostile);
      expect(RegExp(r'[\s"^|<>]').hasMatch(sent), isFalse, reason: sent);
      expect(RegExp(r'%(?![0-9A-Fa-f]{2})').hasMatch(sent), isFalse, reason: sent);
    }
  });

  test('anything that is not a plain web address is refused and nothing is run', () async {
    for (final bad in [
      'file:///C:/Windows/System32/calc.exe',
      r'\\evil.example\share\x',
      r'C:\Windows\System32\calc.exe',
      'ms-msdt:/id PCWDiagnostic',
      'javascript:alert(1)',
      'https:///nohost',
      'https://youtube.com@evil.example/x',
      'calc.exe',
      '',
    ]) {
      expect(
        await openExternal(bad, run: run, os: 'windows'),
        isFalse,
        reason: bad,
      );
      expect(webUri(bad), isNull, reason: bad);
    }
    expect(calls, isEmpty);
  });

  test("sur Android, l'adresse part vers une autre appli, sans processus", () async {
    final launched = <Uri>[];
    Future<bool> launch(Uri u) async {
      launched.add(u);
      return true;
    }

    expect(await openExternal('https://youtu.be/x', run: run, os: 'android', launch: launch), isTrue);
    expect(launched.single.toString(), 'https://youtu.be/x');
    expect(calls, isEmpty);
    expect(await openExternal('file:///etc/passwd', run: run, os: 'android', launch: launch), isFalse);
    expect(launched, hasLength(1));
  });

  test('trailers: a YouTube id or a YouTube address, nothing else from the provider', () {
    expect(trailerUrl('dQw4w9WgXcQ'), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(
      trailerUrl(' https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10 '),
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10',
    );
    expect(trailerUrl('https://youtu.be/dQw4w9WgXcQ'), 'https://youtu.be/dQw4w9WgXcQ');
    expect(trailerUrl('https://x.example/&calc.exe'), isNull);
    expect(trailerUrl('https://www.youtube.com.evil.example/watch?v=1'), isNull);
    expect(trailerUrl('file:///C:/a.exe'), isNull);
    expect(trailerUrl('a&b'), isNull);
    expect(trailerUrl(null), isNull);
    expect(trailerUrl('  '), isNull);
  });
}
