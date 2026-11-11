/// Streaming, tolerant M3U / M3U8 (extended IPTV) playlist parser.
library;

class M3uEntry {
  M3uEntry({required this.name, required this.url, this.attrs = const {}, this.group});
  final String name;
  final String url;
  final Map<String, String> attrs;
  final String? group;

  String? attr(String key) {
    final v = attrs[key];
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  String? get tvgId => attr('tvg-id');
  String? get logo => attr('tvg-logo') ?? attr('logo');
  String get groupTitle => attr('group-title') ?? group ?? 'Sans catégorie';
}

enum M3uKind { live, movie, episode }

class EpisodeInfo {
  const EpisodeInfo(this.seriesName, this.season, this.episode);
  final String seriesName;
  final int season;
  final int episode;
}

// The look-behind makes a name start where a run of name characters
// starts: tried from inside the run as well, a long line without "=" took
// a time growing with the square of its length (seconds, then minutes).
final RegExp _attrRe = RegExp(r'''(?<![A-Za-z0-9_\-:])([A-Za-z0-9_\-:]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,"']+))''');
final RegExp _episodeRe = RegExp(r'\b[Ss](\d{1,2})[\s\-_.]*[EeXx](\d{1,4})\b');

/// Longest display name kept: real ones are far shorter, and every name
/// goes through several expressions.
const int kMaxEntryName = 500;
const Set<String> _vodExtensions = {
  'mp4',
  'mkv',
  'avi',
  'mov',
  'wmv',
  'm4v',
  'webm',
  'flv',
  'mpg',
  'mpeg',
  'ogv',
  '3gp',
  'divx',
};

/// Incremental parser: feed it lines with [addLine], read [entries] / callbacks.
class M3uParser {
  M3uParser(this.onEntry);

  final void Function(M3uEntry entry) onEntry;

  /// EPG url advertised in the header (`url-tvg` / `x-tvg-url`).
  String? epgUrl;

  String? _pendingName;
  Map<String, String> _pendingAttrs = const {};
  String? _pendingGroup;
  bool _first = true;
  bool _started = false;

  /// The document is a web page or an error message (HTML, XML, JSON), not
  /// a playlist: known from its first line. Importing it would replace the
  /// real channels by one "channel" per line.
  bool notAPlaylist = false;

  void addLine(String raw) {
    var line = raw.trim();
    if (_first) {
      // Strip UTF-8 BOM.
      if (line.startsWith('﻿')) line = line.substring(1);
      _first = false;
    }
    if (line.isEmpty) return;
    if (!_started) {
      _started = true;
      notAPlaylist = line.startsWith('<') || line.startsWith('{') || line.startsWith('[');
    }
    if (notAPlaylist) return;

    if (line.startsWith('#')) {
      final upper = line.length >= 8 ? line.substring(0, 8).toUpperCase() : line.toUpperCase();
      if (upper.startsWith('#EXTM3U')) {
        final attrs = parseAttributes(line.substring(7));
        epgUrl ??= _firstUrl(attrs['url-tvg'] ?? attrs['x-tvg-url'] ?? attrs['tvg-url']);
      } else if (upper.startsWith('#EXTINF')) {
        _parseExtInf(line);
      } else if (upper.startsWith('#EXTGRP')) {
        final i = line.indexOf(':');
        if (i > 0) _pendingGroup = line.substring(i + 1).trim();
      }
      // Other directives (#EXTVLCOPT, #KODIPROP, ...) are ignored.
      return;
    }

    // URL line.
    var name = _pendingName ?? _nameFromUrl(line);
    if (name.length > kMaxEntryName) name = name.substring(0, kMaxEntryName);
    onEntry(M3uEntry(name: name, url: line, attrs: _pendingAttrs, group: _pendingGroup));
    _pendingName = null;
    _pendingAttrs = const {};
    _pendingGroup = null;
  }

  void _parseExtInf(String line) {
    final colon = line.indexOf(':');
    final body = colon < 0 ? '' : line.substring(colon + 1);
    // The display name follows the first comma that is not inside quotes.
    var inQuotes = false;
    var comma = -1;
    for (var i = 0; i < body.length; i++) {
      final c = body.codeUnitAt(i);
      if (c == 0x22) {
        inQuotes = !inQuotes;
      } else if (c == 0x2C && !inQuotes) {
        comma = i;
        break;
      }
    }
    final attrPart = comma < 0 ? body : body.substring(0, comma);
    var name = comma < 0 ? '' : body.substring(comma + 1).trim();
    final attrs = parseAttributes(attrPart);
    if (name.isEmpty) name = attrs['tvg-name'] ?? '';
    if (name.length > kMaxEntryName) name = name.substring(0, kMaxEntryName).trim();
    _pendingName = name.isEmpty ? null : name;
    _pendingAttrs = attrs;
  }

  static Map<String, String> parseAttributes(String s) {
    final out = <String, String>{};
    for (final m in _attrRe.allMatches(s)) {
      final key = m.group(1)!.toLowerCase();
      out[key] = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
    }
    return out;
  }

  /// First address of a `url-tvg` list, when it is a web address. A local
  /// or network path is refused: the playlist comes from the provider, and
  /// the guide import would open whatever file it names (a `\\server\share`
  /// path makes Windows log in to that server).
  static String? _firstUrl(String? v) {
    if (v == null) return null;
    final first = v.split(',').first.trim();
    return RegExp(r'^https?://[^\s/]', caseSensitive: false).hasMatch(first) ? first : null;
  }

  static String _nameFromUrl(String url) {
    final path = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList();
    if (path == null || path.isEmpty) return url;
    return path.last; // pathSegments are already percent-decoded
  }
}

String? urlExtension(String url) {
  var path = url;
  final q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot <= slash || dot == path.length - 1) return null;
  return path.substring(dot + 1).toLowerCase();
}

/// Decides whether an M3U entry is a live channel, a movie or a series episode.
M3uKind classifyEntry(M3uEntry e) {
  final lower = e.url.toLowerCase();
  final ext = urlExtension(lower);
  final isVodFile = ext != null && _vodExtensions.contains(ext);
  if (lower.contains('/series/')) {
    return parseEpisode(e.name) != null ? M3uKind.episode : M3uKind.movie;
  }
  if (lower.contains('/movie/') || lower.contains('/movies/')) return M3uKind.movie;
  if (isVodFile) {
    return parseEpisode(e.name) != null ? M3uKind.episode : M3uKind.movie;
  }
  return M3uKind.live;
}

EpisodeInfo? parseEpisode(String name) {
  final m = _episodeRe.firstMatch(name);
  if (m == null) return null;
  // The series name: what comes before, without the separators that end it
  // (trimmed by hand: an expression anchored at the end is slow on a long
  // run of them).
  var end = m.start;
  while (end > 0 && _seriesEnd.contains(name.codeUnitAt(end - 1))) {
    end--;
  }
  final series = name.substring(0, end).trim();
  if (series.isEmpty) return null;
  return EpisodeInfo(series, int.parse(m.group(1)!), int.parse(m.group(2)!));
}

/// Spaces and " -_.:|([" before "S01E02".
final Set<int> _seriesEnd = {...' \t-_.:|(['.codeUnits, 0xA0};
