/// Version shown in the app and compared with GitHub releases for updates.
/// Keep in sync with `version:` in pubspec.yaml (a test checks it).
const String kAppVersion = '1.7.0';

/// Repository the updates are published to.
const String kReleaseRepo = 'Weder77/Bobine';

/// Public Ed25519 key (base64, 32 bytes) the installers of the releases are
/// signed with (see `docs/signature-mises-a-jour.md`). Once set, an update
/// is installed only when its signature is valid: an installer put on a
/// release without the key (an asset replaced, a release made by hand) is
/// refused. Signed by the build, it does not protect from the build itself
/// (a workflow changed, a step compromised): only signing outside GitHub
/// would. Empty: the fingerprint given by GitHub alone is checked.
const String kUpdatePublicKey = '';

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
