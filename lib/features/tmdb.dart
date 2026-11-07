import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/settings.dart';

/// What TMDB adds to a film or series page.
class TmdbInfo {
  const TmdbInfo({
    required this.id,
    this.title,
    this.overview,
    this.tagline,
    this.backdrop,
    this.poster,
    this.genres = const [],
    this.cast = const [],
    this.director,
    this.trailer,
    this.rating,
    this.year,
    this.runtimeMinutes,
  });

  final int id;
  final String? title;
  final String? overview;
  final String? tagline;

  /// Full image addresses.
  final String? backdrop;
  final String? poster;
  final List<String> genres;
  final List<String> cast;
  final String? director;

  /// YouTube address of the trailer.
  final String? trailer;
  final double? rating;
  final int? year;
  final int? runtimeMinutes;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'overview': overview,
    'tagline': tagline,
    'backdrop': backdrop,
    'poster': poster,
    'genres': genres,
    'cast': cast,
    'director': director,
    'trailer': trailer,
    'rating': rating,
    'year': year,
    'runtime': runtimeMinutes,
  };

  factory TmdbInfo.fromJson(Map<String, Object?> j) => TmdbInfo(
    id: j['id'] as int,
    title: j['title'] as String?,
    overview: j['overview'] as String?,
    tagline: j['tagline'] as String?,
    backdrop: j['backdrop'] as String?,
    poster: j['poster'] as String?,
    genres: (j['genres'] as List? ?? const []).cast<String>(),
    cast: (j['cast'] as List? ?? const []).cast<String>(),
    director: j['director'] as String?,
    trailer: j['trailer'] as String?,
    rating: (j['rating'] as num?)?.toDouble(),
    year: j['year'] as int?,
    runtimeMinutes: j['runtime'] as int?,
  );
}

/// Title and year as TMDB knows them, from a provider name such as
/// "FR - Odyssée (2018) [4K]" or "|FR| Les Veilleurs S01".
(String, int?) cleanTitle(String raw, {int? year}) {
  var t = raw;
  int? y = year;
  final yearMatch = RegExp(r'[\(\[]\s*((?:19|20)\d{2})\s*[\)\]]|[-–]\s*((?:19|20)\d{2})\s*$').firstMatch(t);
  if (yearMatch != null) {
    y ??= int.tryParse(yearMatch.group(1) ?? yearMatch.group(2)!);
    t = t.replaceRange(yearMatch.start, yearMatch.end, ' ');
  }
  t = t
      // Language / country tags at the start: "FR - ", "|FR| ", "[VF] ", "EN: ".
      .replaceAll(RegExp(r'^\s*(?:\|[A-Z]{2,4}\||\[[A-Z]{2,6}\]|[A-Z]{2,3}\s*[-:|])\s*'), '')
      // Quality and version markers anywhere.
      .replaceAll(
        RegExp(
          r'[\[\(]?\b(?:4K|UHD|FHD|HD|SD|HEVC|H\.?26[45]|1080p|720p|2160p|VOSTFR|VOST|VF|VFF|VFQ|MULTI|TRUEFRENCH|FRENCH|HDR|DV)\b[\]\)]?',
          caseSensitive: false,
        ),
        ' ',
      )
      // Season markers for series names.
      .replaceAll(RegExp(r'\bS\d{1,2}(E\d{1,3})?\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'[\[\]\(\)|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  t = t.replaceAll(RegExp(r'[-–:]+$'), '').trim();
  return (t, y);
}

/// Name to show for a provider title: without year, language or quality
/// markers ("FR - Odyssée (2018) [4K]" → "Odyssée").
String displayTitle(String raw) {
  final t = cleanTitle(raw).$1;
  return t.isEmpty ? raw : t;
}

/// Fetches artwork, synopsis, cast and trailer from The Movie Database,
/// with the user's own key. Results are kept 30 days (7 for "no match").
class TmdbService {
  TmdbService(this._repo, this._settings, {String? apiBase, String? imageBase})
    : _api = apiBase ?? Platform.environment['BOBINE_TMDB_BASE'] ?? 'https://api.themoviedb.org/3',
      _img = imageBase ?? Platform.environment['BOBINE_TMDB_IMG'] ?? 'https://image.tmdb.org/t/p';

  final Repository _repo;
  final AppSettings _settings;
  final String _api;
  final String _img;
  final Map<String, Future<TmdbInfo?>> _inflight = {};

  bool get enabled => (_settings.tmdbKey ?? '').trim().isNotEmpty;

  TmdbInfo? cachedMovie(Movie m) => _cached(m.sourceId, ContentKind.movie, m.extId);
  TmdbInfo? cachedSeries(Series s) => _cached(s.sourceId, ContentKind.series, s.extId);

  TmdbInfo? _cached(int sourceId, ContentKind kind, String extId) {
    final c = _repo.tmdbCached(sourceId, kind, extId);
    if (c == null || c.$1 == null) return null;
    try {
      return TmdbInfo.fromJson((jsonDecode(c.$1!) as Map).cast<String, Object?>());
    } catch (e, st) {
      debugPrint('TMDB cache: $e $st');
      return null;
    }
  }

  Future<TmdbInfo?> movie(Movie m) => _lookup(m.sourceId, ContentKind.movie, m.extId, m.name, m.year);
  Future<TmdbInfo?> series(Series s) => _lookup(s.sourceId, ContentKind.series, s.extId, s.name, s.year);

  Future<TmdbInfo?> _lookup(int sourceId, ContentKind kind, String extId, String name, int? year) {
    if (!enabled) return Future.value(null);
    final cached = _repo.tmdbCached(sourceId, kind, extId);
    if (cached != null) {
      final age = DateTime.now().difference(cached.$2);
      if (cached.$1 != null && age.inDays < 30) return Future.value(_cached(sourceId, kind, extId));
      if (cached.$1 == null && age.inDays < 7) return Future.value(null);
    }
    final key = '${kind.db}:$sourceId:$extId';
    return _inflight[key] ??= _fetch(kind, name, year)
        .then((info) {
          _repo.tmdbStore(sourceId, kind, extId, info == null ? null : jsonEncode(info.toJson()));
          return info;
        })
        .catchError((Object e) {
          debugPrint('TMDB: $e');
          return cached?.$1 == null ? null : _cached(sourceId, kind, extId);
        })
        .whenComplete(() {
          // A block body: returning the removed future would make this one wait for itself.
          _inflight.remove(key);
        });
  }

  Future<TmdbInfo?> _fetch(ContentKind kind, String name, int? year) async {
    final (title, y) = cleanTitle(name, year: year);
    if (title.isEmpty) return null;
    final tv = kind == ContentKind.series;
    final search = await _get('/search/${tv ? 'tv' : 'movie'}', {
      'query': title,
      'language': 'fr-FR',
      'include_adult': 'false',
      if (y != null) (tv ? 'first_air_date_year' : 'year'): '$y',
    });
    var results = (search['results'] as List? ?? const []).cast<Map>();
    if (results.isEmpty && y != null) {
      // Providers often get the year wrong: retry without it.
      final again = await _get('/search/${tv ? 'tv' : 'movie'}', {'query': title, 'language': 'fr-FR'});
      results = (again['results'] as List? ?? const []).cast<Map>();
    }
    if (results.isEmpty) return null;
    final norm = title.toLowerCase();
    final best = results.firstWhere(
      (r) =>
          '${r[tv ? 'name' : 'title']}'.toLowerCase() == norm ||
          '${r[tv ? 'original_name' : 'original_title']}'.toLowerCase() == norm,
      orElse: () => results.first,
    );
    final id = best['id'] as int;
    final d = await _get('/${tv ? 'tv' : 'movie'}/$id', {
      'language': 'fr-FR',
      'append_to_response': 'credits,videos',
      'include_video_language': 'fr,en,null',
    });
    String? img(Object? path, String size) => path is String && path.isNotEmpty ? '$_img/$size$path' : null;
    final credits = (d['credits'] as Map?) ?? const {};
    final cast = [for (final c in (credits['cast'] as List? ?? const []).cast<Map>().take(8)) '${c['name']}'];
    final crew = (credits['crew'] as List? ?? const []).cast<Map>();
    final director =
        crew.where((c) => c['job'] == 'Director').map((c) => '${c['name']}').firstOrNull ??
        (d['created_by'] as List? ?? const []).cast<Map>().map((c) => '${c['name']}').firstOrNull;
    final videos = ((d['videos'] as Map?)?['results'] as List? ?? const []).cast<Map>();
    final trailer =
        (videos.where((v) => v['site'] == 'YouTube' && v['type'] == 'Trailer').toList()
              ..sort((a, b) => (a['iso_639_1'] == 'fr' ? 0 : 1).compareTo(b['iso_639_1'] == 'fr' ? 0 : 1)))
            .firstOrNull;
    final date = '${d[tv ? 'first_air_date' : 'release_date'] ?? ''}';
    final runtime = tv
        ? ((d['episode_run_time'] as List?)?.cast<num>().firstOrNull?.toInt())
        : (d['runtime'] as num?)?.toInt();
    return TmdbInfo(
      id: id,
      title: d[tv ? 'name' : 'title'] as String?,
      overview: (d['overview'] as String?)?.trim().isEmpty ?? true ? null : (d['overview'] as String).trim(),
      tagline: (d['tagline'] as String?)?.trim().isEmpty ?? true ? null : d['tagline'] as String,
      backdrop: img(d['backdrop_path'], 'w1280'),
      poster: img(d['poster_path'], 'w500'),
      genres: [for (final g in (d['genres'] as List? ?? const []).cast<Map>()) '${g['name']}'],
      cast: cast,
      director: director,
      trailer: trailer == null ? null : 'https://www.youtube.com/watch?v=${trailer['key']}',
      rating: (d['vote_average'] as num?)?.toDouble(),
      year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      runtimeMinutes: runtime == null || runtime <= 0 ? null : runtime,
    );
  }

  /// Checks the key; returns null when it works, else a message.
  Future<String?> testKey(String key) async {
    try {
      await _get('/configuration', const {}, key: key);
      return null;
    } on TmdbException catch (e) {
      return e.message;
    } catch (e) {
      return 'Connexion impossible : $e';
    }
  }

  Future<Map<String, Object?>> _get(String path, Map<String, String> query, {String? key}) async {
    final k = (key ?? _settings.tmdbKey ?? '').trim();
    // A long "read access token" goes in a header, a short API key in the address.
    final bearer = k.length > 40;
    final uri = Uri.parse('$_api$path').replace(queryParameters: {...query, if (!bearer) 'api_key': k});
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $k');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401) throw TmdbException('Clé TMDB refusée (401).');
      if (res.statusCode >= 400) throw TmdbException('TMDB a répondu ${res.statusCode}.');
      return (jsonDecode(body) as Map).cast<String, Object?>();
    } on TimeoutException {
      throw TmdbException('TMDB ne répond pas.');
    } finally {
      client.close(force: true);
    }
  }
}

class TmdbException implements Exception {
  TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Web address of a trailer given as a full address or a bare YouTube id
/// (Xtream panels send the id only).
String? trailerUrl(String? raw) {
  final t = raw?.trim() ?? '';
  if (t.isEmpty) return null;
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  return RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(t) ? 'https://www.youtube.com/watch?v=$t' : null;
}
