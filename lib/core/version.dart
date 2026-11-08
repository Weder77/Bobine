/// Version shown in the app and compared with GitHub releases for updates.
/// Keep in sync with `version:` in pubspec.yaml (a test checks it).
const String kAppVersion = '1.4.0';

/// Repository the updates are published to.
const String kReleaseRepo = 'Weder77/Bobine';

/// Compares two "1.2.3" versions (a leading "v" and a "+build" are ignored).
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('-')
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}
