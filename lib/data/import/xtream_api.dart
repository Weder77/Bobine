import 'dart:convert';
import 'dart:io';

import '../../core/net.dart';
import '../../core/text.dart';
import '../models.dart';

/// Extra metadata for a movie (from `get_vod_info`).
class VodDetails {
  const VodDetails({
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.durationSec,
    this.backdrop,
    this.poster,
    this.rating,
    this.trailer,
    this.videoCodec,
    this.videoWidth,
    this.videoHeight,
    this.hdr,
    this.audioCodec,
    this.audioChannels,
  });
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final int? durationSec;
  final String? backdrop;
  final String? poster;
  final double? rating;
  final String? trailer;

  // Technical info of the main stream (when the panel provides it).
  final String? videoCodec;
  final int? videoWidth;
  final int? videoHeight;

  /// "HDR10", "HLG" or null.
  final String? hdr;
  final String? audioCodec;
  final int? audioChannels;

  /// Short tags for the detail page: "4K", "HDR", "5.1".
  List<String> get qualityTags => [
    if ((videoHeight ?? 0) >= 2000) '4K' else if ((videoHeight ?? 0) >= 700) 'HD',
    if (hdr != null) 'HDR',
    if (audioChannels == 6) '5.1' else if (audioChannels == 8) '7.1',
  ];
}

/// Series metadata + episodes (from `get_series_info`).
class SeriesDetails {
  const SeriesDetails({
    required this.episodes,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.backdrop,
    this.poster,
    this.rating,
  });
  final List<Episode> episodes;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? backdrop;
  final String? poster;
  final double? rating;
}

/// Credentials parsed from a pasted "get.php?username=..&password=.." link.
class XtreamCredentials {
  const XtreamCredentials(this.server, this.username, this.password);
  final String server;
  final String username;
  final String password;

  static XtreamCredentials? tryParse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasScheme) return null;
    final user = uri.queryParameters['username'];
    final pass = uri.queryParameters['password'];
    if (user == null || pass == null) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return XtreamCredentials('${uri.scheme}://${uri.host}$port', user, pass);
  }
}

/// Minimal Xtream Codes "player_api" client. Usable from any isolate.
class XtreamApi {
  XtreamApi({
    required String baseUrl,
    required this.username,
    required this.password,
    this.userAgent,
    HttpClient? client,
  }) : baseUrl = _normalize(baseUrl),
       _client = client ?? createHttpClient(),
       _ownsClient = client == null;

  final String baseUrl;
  final String username;
  final String password;
  final String? userAgent;
  final HttpClient _client;
  final bool _ownsClient;

  factory XtreamApi.forSource(Source s, {HttpClient? client}) => XtreamApi(
    baseUrl: s.baseUrl,
    username: s.username ?? '',
    password: s.password ?? '',
    userAgent: s.userAgent,
    client: client,
  );

  static String _normalize(String u) {
    var s = u.trim();
    if (!s.contains('://')) s = 'http://$s';
    s = s.replaceAll(RegExp(r'/+$'), '');
    return s.replaceAll(RegExp(r'/(player_api|get|xmltv)\.php.*$'), '');
  }

  void close() {
    if (_ownsClient) _client.close(force: true);
  }

  Uri _api([String? action, Map<String, String> extra = const {}]) {
    final base = Uri.parse('$baseUrl/player_api.php');
    return base.replace(queryParameters: {'username': username, 'password': password, 'action': ?action, ...extra});
  }

  Future<Object?> _get(String? action, [Map<String, String> extra = const {}]) =>
      getJson(_client, _api(action, extra), userAgent: userAgent);

  Future<List<Map<String, Object?>>> _list(String action) async {
    final json = await _get(action);
    return asMapList(json);
  }

  /// Checks credentials and returns account information.
  Future<Map<String, Object?>> authenticate() async {
    final json = await _get(null);
    if (json is! Map) {
      throw NetException("Ce serveur ne ressemble pas à un serveur Xtream Codes.");
    }
    final user = json['user_info'];
    if (user is! Map || asInt(user['auth']) != 1) {
      throw NetException('Identifiant ou mot de passe incorrect.');
    }
    final status = asString(user['status']);
    if (status != null && status.toLowerCase() != 'active') {
      throw NetException('Compte inactif (statut : $status).');
    }
    final exp = asInt(user['exp_date']);
    return {
      'status': status,
      'exp_date': exp,
      'max_connections': asInt(user['max_connections']),
      'active_cons': asInt(user['active_cons']),
      'is_trial': asInt(user['is_trial']) == 1,
      'formats': (user['allowed_output_formats'] is List)
          ? (user['allowed_output_formats'] as List).map((e) => e.toString()).toList()
          : null,
    };
  }

  Future<List<Map<String, Object?>>> liveCategories() => _list('get_live_categories');
  Future<List<Map<String, Object?>>> vodCategories() => _list('get_vod_categories');
  Future<List<Map<String, Object?>>> seriesCategories() => _list('get_series_categories');
  Future<List<Map<String, Object?>>> liveStreams() => _list('get_live_streams');
  Future<List<Map<String, Object?>>> vodStreams() => _list('get_vod_streams');
  Future<List<Map<String, Object?>>> seriesList() => _list('get_series');

  Future<VodDetails> vodInfo(String vodId) async => parseVodInfo(await _get('get_vod_info', {'vod_id': vodId}));

  Future<SeriesDetails> seriesInfo(int sourceId, String seriesId) async =>
      parseSeriesInfo(await _get('get_series_info', {'series_id': seriesId}), sourceId, seriesId);

  /// Short EPG for one channel (fallback when no XMLTV data exists).
  Future<List<Program>> shortEpg(String streamId, {int limit = 12, Duration offset = Duration.zero}) async {
    final json = await _get('get_short_epg', {'stream_id': streamId, 'limit': '$limit'});
    final list = json is Map ? asMapList(json['epg_listings']) : const <Map<String, Object?>>[];
    final out = <Program>[];
    for (final e in list) {
      final start = asInt(e['start_timestamp']);
      final stop = asInt(e['stop_timestamp']);
      if (start == null || stop == null) continue;
      out.add(
        Program(
          start: DateTime.fromMillisecondsSinceEpoch(start * 1000).add(offset),
          stop: DateTime.fromMillisecondsSinceEpoch(stop * 1000).add(offset),
          title: _b64(asString(e['title'])) ?? '',
          description: _b64(asString(e['description'])),
        ),
      );
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  static String? _b64(String? v) {
    if (v == null) return null;
    try {
      return utf8.decode(base64.decode(base64.normalize(v)), allowMalformed: true);
    } catch (_) {
      return v;
    }
  }
}

List<Map<String, Object?>> asMapList(Object? json) {
  if (json is List) {
    return json.whereType<Map>().map((m) => m.cast<String, Object?>()).toList();
  }
  if (json is Map) {
    // Some panels return objects keyed by index instead of arrays.
    return json.values.whereType<Map>().map((m) => m.cast<String, Object?>()).toList();
  }
  return const [];
}

String? _firstImage(Object? v) {
  if (v is List) {
    for (final e in v) {
      final s = asString(e);
      if (s != null && s.startsWith('http')) return s;
    }
    return null;
  }
  final s = asString(v);
  return (s != null && s.startsWith('http')) ? s : null;
}

double? parseRating(Map<String, Object?> m) {
  final r = asDouble(m['rating']);
  if (r != null && r > 0) return r > 10 ? r / 10 : r;
  final r5 = asDouble(m['rating_5based']);
  if (r5 != null && r5 > 0) return r5 * 2;
  return null;
}

int? parseDurationSec(Map<String, Object?> info) {
  final secs = asInt(info['duration_secs']);
  if (secs != null && secs > 0) return secs;
  final d = asString(info['duration']);
  if (d == null) return null;
  final parts = d.split(':').map(int.tryParse).toList();
  if (parts.length == 3 && !parts.contains(null)) {
    return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
  }
  final minutes = asInt(d);
  return minutes == null ? null : minutes * 60;
}

VodDetails parseVodInfo(Object? json) {
  if (json is! Map) return const VodDetails();
  final info = json['info'] is Map ? (json['info'] as Map).cast<String, Object?>() : <String, Object?>{};
  Map<String, Object?> sub(String k) =>
      info[k] is Map ? (info[k] as Map).cast<String, Object?>() : const <String, Object?>{};
  final video = sub('video');
  final audio = sub('audio');
  return VodDetails(
    plot: asString(info['plot']) ?? asString(info['description']),
    cast: asString(info['cast']) ?? asString(info['actors']),
    director: asString(info['director']),
    genre: asString(info['genre']),
    releaseDate: asString(info['releasedate']) ?? asString(info['release_date']),
    durationSec: parseDurationSec(info),
    backdrop: _firstImage(info['backdrop_path']),
    poster: _firstImage(info['movie_image']) ?? _firstImage(info['cover_big']),
    rating: parseRating(info),
    trailer: asString(info['youtube_trailer']),
    videoCodec: _codecName(video['codec_name']),
    videoWidth: asInt(video['width']),
    videoHeight: asInt(video['height']),
    hdr: switch (asString(video['color_transfer'])) {
      'smpte2084' => 'HDR10',
      'arib-std-b67' => 'HLG',
      _ => null,
    },
    audioCodec: _codecName(audio['codec_name']),
    audioChannels: asInt(audio['channels']),
  );
}

String? _codecName(Object? v) => switch (asString(v)?.toLowerCase()) {
  null => null,
  'hevc' || 'h265' => 'HEVC',
  'h264' || 'avc' => 'H.264',
  'eac3' => 'E-AC3',
  'ac3' => 'AC3',
  'aac' => 'AAC',
  'dts' => 'DTS',
  'truehd' => 'TrueHD',
  final other => other.toUpperCase(),
};

SeriesDetails parseSeriesInfo(Object? json, int sourceId, String seriesId) {
  if (json is! Map) return const SeriesDetails(episodes: []);
  final info = json['info'] is Map ? (json['info'] as Map).cast<String, Object?>() : <String, Object?>{};
  final episodes = <Episode>[];
  final raw = json['episodes'];
  final groups = <MapEntry<int?, Object?>>[];
  if (raw is Map) {
    raw.forEach((k, v) => groups.add(MapEntry(asInt(k), v)));
  } else if (raw is List) {
    for (final v in raw) {
      groups.add(MapEntry(null, v));
    }
  }
  for (final g in groups) {
    final list = g.value is List
        ? asMapList(g.value)
        : (g.value is Map ? [(g.value as Map).cast<String, Object?>()] : <Map<String, Object?>>[]);
    var index = 0;
    for (final e in list) {
      index++;
      final id = asString(e['id']);
      if (id == null) continue;
      final epInfo = e['info'] is Map ? (e['info'] as Map).cast<String, Object?>() : <String, Object?>{};
      episodes.add(
        Episode(
          sourceId: sourceId,
          seriesExt: seriesId,
          extId: id,
          season: asInt(e['season']) ?? g.key ?? 1,
          episode: asInt(e['episode_num']) ?? index,
          title: asString(e['title']),
          plot: asString(epInfo['plot']),
          image: _firstImage(epInfo['movie_image']) ?? _firstImage(epInfo['cover_big']),
          durationSec: parseDurationSec(epInfo),
          container: asString(e['container_extension']),
        ),
      );
    }
  }
  episodes.sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.episode.compareTo(b.episode));
  return SeriesDetails(
    episodes: episodes,
    plot: asString(info['plot']),
    cast: asString(info['cast']),
    director: asString(info['director']),
    genre: asString(info['genre']),
    releaseDate: asString(info['releaseDate']) ?? asString(info['release_date']),
    backdrop: _firstImage(info['backdrop_path']),
    poster: _firstImage(info['cover']),
    rating: parseRating(info),
  );
}
