import 'dart:convert';

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
        'browser_download_url': 'https://x/setup',
        'size': 20,
        'digest': 'sha256:ABCDEF',
      },
    ],
  };

  test('only a newer final release is offered, with the Windows installer', () {
    final info = UpdateService.parseRelease(release('v1.2.0'), current: '1.1.0', windows: true)!;
    expect(info.version, '1.2.0');
    expect(info.assetUrl, 'https://x/setup');
    expect(info.size, 20);
    expect(info.sha256, 'abcdef');
    expect(info.notes, 'Nouveautés');

    expect(UpdateService.parseRelease(release('v1.1.0'), current: '1.1.0', windows: true), isNull);
    expect(UpdateService.parseRelease(release('v1.0.9'), current: '1.1.0', windows: true), isNull);
    expect(UpdateService.parseRelease(release('v2.0.0', pre: true), current: '1.1.0', windows: true), isNull);

    // Elsewhere: the release page only.
    final other = UpdateService.parseRelease(release('v1.2.0'), current: '1.1.0', windows: false)!;
    expect(other.assetUrl, isNull);
    expect(other.page, contains('v1.2.0'));
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
}
