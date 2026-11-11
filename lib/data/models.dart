import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../core/secrets.dart';

enum SourceType { m3u, xtream }

/// Content kinds as stored in the database.
enum ContentKind {
  live('live'),
  movie('movie'),
  series('series'),
  episode('episode');

  const ContentKind(this.db);
  final String db;

  static ContentKind fromDb(String v) =>
      ContentKind.values.firstWhere((k) => k.db == v, orElse: () => ContentKind.live);
}

DateTime? _date(Object? seconds) =>
    seconds == null ? null : DateTime.fromMillisecondsSinceEpoch((seconds as int) * 1000);

class Source {
  const Source({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.username,
    this.password,
    this.epgUrl,
    this.userAgent,
    this.liveFormat = 'ts',
    this.contentUpdatedAt,
    this.epgUpdatedAt,
    this.accountInfo,
    this.lastError,
    this.epgOffsetMinutes = 0,
  });

  final int id;
  final String name;
  final SourceType type;

  /// M3U: playlist URL or local file path. Xtream: server base URL.
  final String url;
  final String? username;
  final String? password;
  final String? epgUrl;
  final String? userAgent;

  /// Xtream live container: 'ts' (MPEG-TS, most robust) or 'm3u8' (HLS).
  final String liveFormat;
  final DateTime? contentUpdatedAt;
  final DateTime? epgUpdatedAt;
  final Map<String, Object?>? accountInfo;
  final String? lastError;

  /// Shift applied to guide times (some providers publish a wrong timezone).
  final int epgOffsetMinutes;

  bool get isXtream => type == SourceType.xtream;

  /// Normalised Xtream base, e.g. "http://host:8080".
  String get baseUrl {
    var u = url.trim();
    if (!u.contains('://')) u = 'http://$u';
    u = u.replaceAll(RegExp(r'/+$'), '');
    u = u.replaceAll(RegExp(r'/(player_api|get|xmltv)\.php.*$'), '');
    return u;
  }

  /// Effective EPG URL (Xtream provides one automatically).
  String? get effectiveEpgUrl {
    if (epgUrl != null && epgUrl!.trim().isNotEmpty) return epgUrl!.trim();
    if (isXtream) {
      return '$baseUrl/xmltv.php?username=${Uri.encodeQueryComponent(username ?? '')}'
          '&password=${Uri.encodeQueryComponent(password ?? '')}';
    }
    return null;
  }

  factory Source.fromRow(Row r) => Source(
    id: r['id'] as int,
    name: r['name'] as String,
    type: r['type'] == 'xtream' ? SourceType.xtream : SourceType.m3u,
    // Credentials are encrypted at rest (see Secrets).
    url: Secrets.reveal(r['url'] as String) ?? '',
    username: r['username'] as String?,
    password: Secrets.reveal(r['password'] as String?),
    epgUrl: Secrets.reveal(r['epg_url'] as String?),
    userAgent: r['user_agent'] as String?,
    liveFormat: (r['live_format'] as String?) ?? 'ts',
    contentUpdatedAt: _date(r['content_updated_at']),
    epgUpdatedAt: _date(r['epg_updated_at']),
    accountInfo: r['account_info'] == null
        ? null
        : (jsonDecode(r['account_info'] as String) as Map).cast<String, Object?>(),
    lastError: r['last_error'] as String?,
    epgOffsetMinutes: (r['epg_offset'] as int?) ?? 0,
  );
}

class ContentCategory {
  const ContentCategory({
    required this.id,
    required this.kind,
    required this.extId,
    required this.name,
    this.count = 0,
    this.hidden = false,
    this.locked = false,
  });
  final int id;
  final ContentKind kind;
  final String extId;
  final String name;
  final int count;

  /// Hidden by the user (Réglages → Catégories).
  final bool hidden;

  /// Behind the parental code.
  final bool locked;

  factory ContentCategory.fromRow(Row r) => ContentCategory(
    id: r['id'] as int,
    kind: ContentKind.fromDb(r['kind'] as String),
    extId: r['ext_id'] as String,
    name: r['name'] as String,
    count: (r['cnt'] as int?) ?? 0,
    hidden: (r['p_hidden'] as int?) == 1,
    locked: (r['p_locked'] as int?) == 1,
  );
}

class Channel {
  const Channel({
    required this.id,
    required this.sourceId,
    required this.extId,
    required this.name,
    this.search = '',
    this.categoryId,
    this.logo,
    this.url,
    this.epgId,
    this.number,
    this.catchupDays = 0,
    this.catchupType,
    this.catchupSource,
  });
  final int id;
  final int sourceId;
  final String extId;
  final String name;

  /// Lower-cased, accent-free name (stored at import, used for filtering).
  final String search;
  final int? categoryId;
  final String? logo;
  final String? url;
  final String? epgId;
  final int? number;
  final int catchupDays;

  /// M3U replay mode ("default", "append", "shift", "flussonic", "xc"…).
  final String? catchupType;

  /// M3U replay address template (`catchup-source`).
  final String? catchupSource;

  bool get hasReplay => catchupDays > 0;

  factory Channel.fromRow(Row r) => Channel(
    id: r['id'] as int,
    sourceId: r['source_id'] as int,
    extId: r['ext_id'] as String,
    name: r['name'] as String,
    search: (r['search'] as String?) ?? '',
    categoryId: r['category_id'] as int?,
    logo: r['logo'] as String?,
    url: r['url'] as String?,
    epgId: r['epg_id'] as String?,
    number: r['number'] as int?,
    catchupDays: (r['catchup_days'] as int?) ?? 0,
    catchupType: r['catchup_type'] as String?,
    catchupSource: r['catchup_source'] as String?,
  );
}

class Movie {
  const Movie({
    required this.id,
    required this.sourceId,
    required this.extId,
    required this.name,
    this.search = '',
    this.categoryId,
    this.poster,
    this.rating,
    this.year,
    this.added,
    this.container,
    this.url,
  });
  final int id;
  final int sourceId;
  final String extId;
  final String name;

  /// Lower-cased, accent-free name (stored at import, used for filtering).
  final String search;
  final int? categoryId;
  final String? poster;
  final double? rating;
  final int? year;
  final DateTime? added;
  final String? container;
  final String? url;

  factory Movie.fromRow(Row r) => Movie(
    id: r['id'] as int,
    sourceId: r['source_id'] as int,
    extId: r['ext_id'] as String,
    name: r['name'] as String,
    search: (r['search'] as String?) ?? '',
    categoryId: r['category_id'] as int?,
    poster: r['poster'] as String?,
    rating: (r['rating'] as num?)?.toDouble(),
    year: r['year'] as int?,
    added: _date(r['added']),
    container: r['container'] as String?,
    url: r['url'] as String?,
  );
}

class Series {
  const Series({
    required this.id,
    required this.sourceId,
    required this.extId,
    required this.name,
    this.search = '',
    this.categoryId,
    this.poster,
    this.backdrop,
    this.plot,
    this.genre,
    this.rating,
    this.year,
    this.added,
  });
  final int id;
  final int sourceId;
  final String extId;
  final String name;

  /// Lower-cased, accent-free name (stored at import, used for filtering).
  final String search;
  final int? categoryId;
  final String? poster;
  final String? backdrop;
  final String? plot;
  final String? genre;
  final double? rating;
  final int? year;
  final DateTime? added;

  factory Series.fromRow(Row r) => Series(
    id: r['id'] as int,
    sourceId: r['source_id'] as int,
    extId: r['ext_id'] as String,
    name: r['name'] as String,
    search: (r['search'] as String?) ?? '',
    categoryId: r['category_id'] as int?,
    poster: r['poster'] as String?,
    backdrop: r['backdrop'] as String?,
    plot: r['plot'] as String?,
    genre: r['genre'] as String?,
    rating: (r['rating'] as num?)?.toDouble(),
    year: r['year'] as int?,
    added: _date(r['added']),
  );
}

class Episode {
  const Episode({
    required this.sourceId,
    required this.seriesExt,
    required this.extId,
    required this.season,
    required this.episode,
    this.title,
    this.plot,
    this.image,
    this.durationSec,
    this.container,
    this.url,
  });
  final int sourceId;
  final String seriesExt;
  final String extId;
  final int season;
  final int episode;
  final String? title;
  final String? plot;
  final String? image;
  final int? durationSec;
  final String? container;
  final String? url;

  String get code => 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

  String get displayTitle {
    final t = title?.trim();
    if (t == null || t.isEmpty) return 'Épisode $episode';
    return t;
  }

  factory Episode.fromRow(Row r) => Episode(
    sourceId: r['source_id'] as int,
    seriesExt: r['series_ext'] as String,
    extId: r['ext_id'] as String,
    season: r['season'] as int,
    episode: r['episode'] as int,
    title: r['title'] as String?,
    plot: r['plot'] as String?,
    image: r['image'] as String?,
    durationSec: r['duration_s'] as int?,
    container: r['container'] as String?,
    url: r['url'] as String?,
  );
}

class Program {
  const Program({required this.start, required this.stop, required this.title, this.description, this.category});
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? description;

  /// XMLTV genre, e.g. "Sport · Rugby".
  final String? category;

  bool isLiveAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);

  double progressAt(DateTime t) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  factory Program.fromRow(Row r) => Program(
    start: DateTime.fromMillisecondsSinceEpoch((r['start'] as int) * 1000),
    stop: DateTime.fromMillisecondsSinceEpoch((r['stop'] as int) * 1000),
    title: r['title'] as String,
    description: r['description'] as String?,
    category: r['category'] as String?,
  );
}

class ProgressEntry {
  const ProgressEntry({
    required this.sourceId,
    required this.kind,
    required this.extId,
    required this.position,
    required this.duration,
    required this.finished,
    required this.updatedAt,
    required this.title,
    this.subtitle,
    this.image,
    this.seriesExt,
  });
  final int sourceId;
  final ContentKind kind;
  final String extId;
  final Duration position;
  final Duration duration;
  final bool finished;
  final DateTime updatedAt;
  final String title;
  final String? subtitle;
  final String? image;
  final String? seriesExt;

  double get fraction =>
      duration.inMilliseconds <= 0 ? 0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  /// Whether playback should resume from [position] rather than start over.
  bool get resumable => !finished && position.inSeconds > 30 && fraction < 0.95;

  factory ProgressEntry.fromRow(Row r) => ProgressEntry(
    sourceId: r['source_id'] as int,
    kind: ContentKind.fromDb(r['kind'] as String),
    extId: r['ext_id'] as String,
    position: Duration(milliseconds: r['position_ms'] as int),
    duration: Duration(milliseconds: r['duration_ms'] as int),
    finished: (r['finished'] as int) == 1,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    title: r['title'] as String,
    subtitle: r['subtitle'] as String?,
    image: r['image'] as String?,
    seriesExt: r['series_ext'] as String?,
  );
}

/// A local profile: its own favourites, progress and recent channels.
class Profile {
  const Profile({required this.id, required this.name, required this.color, this.kids = false, this.avatar});

  /// Most profiles an installation can create.
  static const max = 10;

  final int id;
  final String name;
  final int color;

  /// Kids profile: categories behind the parental code are never shown.
  final bool kids;

  /// Picture of the profile: null for the initial on [color],
  /// `preset:<name>` for a bundled picture, or a photo (`data:image/jpeg;base64,…`).
  final String? avatar;

  String get initial => initialOf(name);

  /// First letter of [name], for avatars without a picture.
  static String initialOf(String name) =>
      name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();

  factory Profile.fromRow(Row r) => Profile(
    id: r['id'] as int,
    name: r['name'] as String,
    color: r['color'] as int,
    kids: (r['kids'] as int) == 1,
    avatar: r['avatar'] as String?,
  );
}

/// "Remind me" set on a future programme.
class Reminder {
  const Reminder({
    required this.id,
    required this.sourceId,
    required this.channelExt,
    required this.channelName,
    required this.title,
    required this.start,
    required this.stop,
  });
  final int id;
  final int sourceId;
  final String channelExt;
  final String channelName;
  final String title;
  final DateTime start;
  final DateTime stop;

  factory Reminder.fromRow(Row r) => Reminder(
    id: r['id'] as int,
    sourceId: r['source_id'] as int,
    channelExt: r['channel_ext'] as String,
    channelName: r['channel_name'] as String,
    title: r['title'] as String,
    start: DateTime.fromMillisecondsSinceEpoch((r['start'] as int) * 1000),
    stop: DateTime.fromMillisecondsSinceEpoch((r['stop'] as int) * 1000),
  );
}

enum RecordingStatus { scheduled, recording, done, failed, cancelled }

/// A recording of a live channel to a file.
class Recording {
  const Recording({
    required this.id,
    required this.sourceId,
    required this.channelExt,
    required this.channelName,
    required this.title,
    required this.start,
    required this.stop,
    required this.status,
    this.path,
    this.error,
    this.size,
  });
  final int id;
  final int sourceId;
  final String channelExt;
  final String channelName;
  final String title;
  final DateTime start;
  final DateTime stop;
  final RecordingStatus status;
  final String? path;
  final String? error;
  final int? size;

  factory Recording.fromRow(Row r) => Recording(
    id: r['id'] as int,
    sourceId: r['source_id'] as int,
    channelExt: r['channel_ext'] as String,
    channelName: r['channel_name'] as String,
    title: r['title'] as String,
    start: DateTime.fromMillisecondsSinceEpoch((r['start'] as int) * 1000),
    stop: DateTime.fromMillisecondsSinceEpoch((r['stop'] as int) * 1000),
    status: RecordingStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => RecordingStatus.failed),
    path: r['path'] as String?,
    error: r['error'] as String?,
    size: r['size'] as int?,
  );
}

/// A guide programme found by the search, with its channel.
class ProgramHit {
  const ProgramHit(this.channel, this.program);
  final Channel channel;
  final Program program;
}
