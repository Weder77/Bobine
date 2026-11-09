import 'cast_device.dart';

/// Whether [url] is an HLS playlist.
bool isHlsUrl(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.endsWith('.m3u8') || path.endsWith('.m3u');
}

/// Whether [url] is a file of this computer (recordings).
bool isLocalMedia(String url) {
  final u = url.toLowerCase();
  return !(u.startsWith('http://') || u.startsWith('https://'));
}

/// Address the device should open for [url].
///
/// Chromecast does not play raw MPEG-TS streams: Xtream live channels are
/// asked in HLS instead (same address, `.m3u8`), which every Xtream server
/// offers.
String castUrl(String url, CastProtocol protocol) {
  if (protocol != CastProtocol.chromecast) return url;
  final xtreamLive = RegExp(r'^(https?://[^?#]+/live/[^/?#]+/[^/?#]+/[^/?#]+)\.ts((?:[?#].*)?)$', caseSensitive: false);
  final m = xtreamLive.firstMatch(url);
  if (m != null) return '${m[1]}.m3u8${m[2]}';
  return url;
}

/// MIME type announced to the device.
String castContentType(String url, {required bool live, required CastProtocol protocol}) {
  final path = isLocalMedia(url) ? url.toLowerCase() : (Uri.tryParse(url)?.path ?? url).toLowerCase();
  final dot = path.lastIndexOf('.');
  final ext = (dot < 0 || dot < path.lastIndexOf('/')) ? '' : path.substring(dot + 1);
  final cc = protocol == CastProtocol.chromecast;
  return switch (ext) {
    'm3u8' || 'm3u' => 'application/x-mpegURL',
    'ts' || 'mts' || 'm2ts' || 'trp' => 'video/mp2t',
    'mp4' || 'm4v' => 'video/mp4',
    'webm' => 'video/webm',
    // Chromecast's player reads Matroska and QuickTime with the usual codecs
    // when told "mp4"; renderers want the real type.
    'mkv' => cc ? 'video/mp4' : 'video/x-matroska',
    'mov' => cc ? 'video/mp4' : 'video/quicktime',
    'avi' => cc ? 'video/mp4' : 'video/x-msvideo',
    'flv' => 'video/x-flv',
    'mpg' || 'mpeg' => 'video/mpeg',
    _ => live ? 'video/mp2t' : 'video/mp4',
  };
}

/// Spellings of the same format: renderers each list their own.
const _mimeFamilies = [
  ['video/x-matroska', 'video/x-mkv', 'video/mkv', 'video/matroska'],
  ['video/mp4', 'video/x-mp4', 'video/mpeg4', 'video/m4v', 'video/x-m4v'],
  [
    'video/mp2t',
    'video/vnd.dlna.mpeg-tts',
    'video/x-mpegts',
    'video/mpegts',
    'video/mpeg',
    'video/x-mpeg',
    'video/mpeg2',
    'video/x-mpeg2',
  ],
  ['video/x-msvideo', 'video/avi', 'video/x-avi', 'video/msvideo', 'video/divx', 'video/x-divx'],
  ['video/quicktime', 'video/x-quicktime', 'video/mp4'],
  ['application/x-mpegurl', 'application/vnd.apple.mpegurl', 'audio/x-mpegurl', 'audio/mpegurl'],
  ['video/webm'],
  ['video/x-flv', 'video/flv'],
];

/// [mime] as a DLNA renderer spells it in its list of accepted formats
/// ([sink], from GetProtocolInfo): some refuse a file announced with
/// another spelling ("video/x-mkv" instead of "video/x-matroska").
/// [mime] itself when the renderer accepts anything or lists no match.
String rendererMime(String mime, List<String> sink) {
  final listed = <String, String>{};
  for (final p in sink) {
    final parts = p.split(':');
    if (parts.length < 4 || parts[0].trim().toLowerCase() != 'http-get') continue;
    final m = parts[2].trim();
    if (m == '*') return mime;
    listed.putIfAbsent(m.toLowerCase(), () => m);
  }
  final key = mime.toLowerCase();
  final same = listed[key];
  if (same != null) return same;
  for (final family in _mimeFamilies) {
    if (!family.contains(key)) continue;
    for (final alias in family) {
      final s = listed[alias];
      if (s != null) return s;
    }
  }
  return mime;
}

/// The renderer's spellings of [mime]'s format with their fourth field, as
/// listed in [sink] (http-get entries), e.g. ("video/x-mkv", "*").
List<(String, String)> rendererMimes(String mime, List<String> sink) {
  final key = mime.toLowerCase();
  final family = _mimeFamilies.firstWhere((f) => f.contains(key), orElse: () => [key]);
  final out = <(String, String)>[];
  for (final p in sink) {
    final parts = p.split(':');
    if (parts.length < 4 || parts[0].trim().toLowerCase() != 'http-get') continue;
    final m = parts[2].trim();
    if (!family.contains(m.toLowerCase())) continue;
    final entry = (m, parts.sublist(3).join(':').trim());
    if (!out.contains(entry)) out.add(entry);
  }
  return out;
}
