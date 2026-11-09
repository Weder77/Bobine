import 'dart:io';

/// How the system is asked to open something (tests replace it).
typedef ProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments);

/// [raw] as a web address that can be handed to the system, or null.
///
/// Only http and https addresses with a host and no "user@" part: no file,
/// network path or other protocol (some start programs). The address is
/// re-encoded, so it holds no space, quote or control character.
Uri? webUri(String raw) {
  final u = Uri.tryParse(raw.trim());
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) return null;
  if (u.host.isEmpty || u.userInfo.isNotEmpty) return null;
  return u;
}

/// Opens the web page [url] in the default browser. Anything that is not a
/// plain http(s) address is refused (see [webUri]).
///
/// The address may come from a provider or a release note: it is never
/// given to a command interpreter. ("cmd /c start" ran whatever followed a
/// "&" in the address as a command.)
Future<bool> openExternal(String url, {ProcessRunner run = Process.run, String? os}) async {
  final uri = webUri(url);
  if (uri == null) return false;
  final target = uri.toString();
  try {
    final ProcessResult r;
    switch (os ?? Platform.operatingSystem) {
      case 'windows':
        r = await run('rundll32', ['url.dll,FileProtocolHandler', target]);
      case 'macos':
        r = await run('open', [target]);
      default:
        r = await run('xdg-open', [target]);
    }
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
