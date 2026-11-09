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
