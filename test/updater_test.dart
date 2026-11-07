import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/features/updater.dart';

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
}
