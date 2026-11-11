import 'dart:convert';
import 'dart:io';

import 'package:bobine/data/db.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/features/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> release(String tag, {bool pre = false}) => {
    'tag_name': tag,
    'prerelease': pre,
    'html_url': 'https://github.com/o/r/releases/tag/$tag',
    'body': 'Nouveautés',
    'assets': [
      {'name': 'Bobine-windows-x64.zip', 'browser_download_url': 'https://x/zip', 'size': 10},
      {
        'name': 'Bobine-Setup-$tag.exe',
        'browser_download_url': 'https://github.com/Weder77/Bobine/releases/download/$tag/Bobine-Setup-$tag.exe',
        'size': 20,
        'digest': 'sha256:${'AB' * 32}',
      },
    ],
  };

  test('only a newer final release is offered, with the Windows installer', () {
    final info = UpdateService.parseRelease(release('v1.2.0'), current: '1.1.0', windows: true)!;
    expect(info.version, '1.2.0');
    expect(info.assetUrl, 'https://github.com/Weder77/Bobine/releases/download/v1.2.0/Bobine-Setup-v1.2.0.exe');
    expect(info.size, 20);
    expect(info.sha256, 'ab' * 32);
    expect(info.notes, 'Nouveautés');

    expect(UpdateService.parseRelease(release('v1.1.0'), current: '1.1.0', windows: true), isNull);
    expect(UpdateService.parseRelease(release('v1.0.9'), current: '1.1.0', windows: true), isNull);
    expect(UpdateService.parseRelease(release('v2.0.0', pre: true), current: '1.1.0', windows: true), isNull);

    // Elsewhere: the release page only.
    final other = UpdateService.parseRelease(release('v1.2.0'), current: '1.1.0', windows: false)!;
    expect(other.assetUrl, isNull);
    expect(other.page, contains('v1.2.0'));
  });

  test('an installer from elsewhere, or without its fingerprint, is not downloaded', () {
    Map<String, Object?> withAsset(Map<String, Object?> a) => {
      ...release('v1.2.0'),
      'assets': [a],
    };
    final good = {
      'name': 'Bobine-Setup.exe',
      'browser_download_url': 'https://github.com/Weder77/Bobine/releases/download/v1.2.0/Bobine-Setup.exe',
      'digest': 'sha256:${'0' * 64}',
    };
    UpdateInfo? parse(Map<String, Object?> a) =>
        UpdateService.parseRelease(withAsset(a), current: '1.1.0', windows: true);
    expect(parse(good)!.assetUrl, isNotNull);
    expect(parse({...good, 'digest': null})!.assetUrl, isNull);
    expect(parse({...good, 'digest': 'sha256:abc'})!.assetUrl, isNull);
    expect(
      parse({...good, 'browser_download_url': 'http://github.com/Weder77/Bobine/releases/download/x.exe'})!.assetUrl,
      isNull,
    );
    expect(
      parse({...good, 'browser_download_url': 'https://evil.example/Weder77/Bobine/releases/download/x.exe'})!.assetUrl,
      isNull,
    );
    expect(
      parse({...good, 'browser_download_url': 'https://github.com/other/repo/releases/download/x.exe'})!.assetUrl,
      isNull,
    );
  });

  test('once a key is set, only an installer signed with it is taken', () async {
    // Made with OpenSSL, as the release job does (see docs/signature-mises-a-jour.md).
    const publicKey = 'LWthxiq5A0skBoom1M00zvyOKB7g5u+mnFHjtusbtyY=';
    final signature = base64.decode(
      'o6wZe9HeJSTItfToDxfZg82UfTdFO7tCEohWuiX4SURQwVcpan/kthCWKCip2KbcHjTnOQ2cbaC2pjqzfdQJBw==',
    );
    final digest = [
      for (var i = 0; i < 64; i += 2)
        int.parse('24fd14f605109ea98f1a239e4c6bb88a4d8f6a7d2693deb368e258d44da0a0ff'.substring(i, i + 2), radix: 16),
    ];
    expect(await UpdateService.signatureValid(digest, signature, publicKey), isTrue);
    expect(await UpdateService.signatureValid([...digest]..[0] ^= 1, signature, publicKey), isFalse);
    expect(await UpdateService.signatureValid(digest, signature, base64.encode(List.filled(32, 7))), isFalse);

    final before = UpdateService.publicKey;
    addTearDown(() => UpdateService.publicKey = before);
    UpdateService.publicKey = publicKey;
    final installer = {
      'name': 'Bobine-Setup.exe',
      'browser_download_url': 'https://github.com/Weder77/Bobine/releases/download/v1.2.0/Bobine-Setup.exe',
      'digest': 'sha256:24fd14f605109ea98f1a239e4c6bb88a4d8f6a7d2693deb368e258d44da0a0ff',
    };
    Map<String, Object?> rel(List<Map<String, Object?>> assets) => {...release('v1.2.0'), 'assets': assets};
    // Without its signature: the release page only.
    expect(UpdateService.parseRelease(rel([installer]), current: '1.1.0', windows: true)!.assetUrl, isNull);
    final signed = UpdateService.parseRelease(
      rel([
        installer,
        {
          'name': 'Bobine-Setup.exe.sig',
          'browser_download_url': 'https://github.com/Weder77/Bobine/releases/download/v1.2.0/Bobine-Setup.exe.sig',
        },
      ]),
      current: '1.1.0',
      windows: true,
    )!;
    expect(signed.assetUrl, isNotNull);
    expect(signed.signatureUrl, endsWith('.sig'));
  });

  test('the version found by the last check is offered again after a restart', () {
    final repo = Repository(openMemoryDatabase());
    final settings = AppSettings(repo);
    repo.kvSet('update_found', jsonEncode(release('v99.0.0')));
    final u = UpdateService(repo, settings)..restoreFound();
    expect(u.available?.version, '99.0.0');
    expect(u.stage, UpdateStage.available);

    // Skipped by the user: not offered again.
    repo.kvSet('update_skip', '99.0.0');
    final again = UpdateService(repo, settings)..restoreFound();
    expect(again.available, isNull);

    // Older than this version (already installed): nothing.
    repo.kvSet('update_found', jsonEncode(release('v0.1.0')));
    final old = UpdateService(repo, settings)..restoreFound();
    expect(old.available, isNull);
  });

  test('a failed check keeps the version found, and is tried again soon', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      r.response.statusCode = 503;
      await r.response.close();
    });
    final repo = Repository(openMemoryDatabase());
    final settings = AppSettings(repo);
    repo.kvSet('update_found', jsonEncode(release('v99.0.0')));
    final u = UpdateService(repo, settings, apiUrl: 'http://127.0.0.1:${server.port}/latest')..restoreFound();
    expect(await u.check(quiet: true), isNotNull);
    expect(u.available?.version, '99.0.0');
    expect(u.stage, UpdateStage.available);
    expect(repo.kvGet('update_checked_at'), isNull);
  });
}
