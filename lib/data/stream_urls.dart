import 'models.dart';

/// Protocols a provider's stream may use. Anything else (a file of this
/// computer, a `\\server\share` path, mpv's own `edl://`, `av://`,
/// `concat:`…) is refused: a playlist comes from the provider, and the
/// player would open whatever it names. A network path even makes Windows
/// log in to that server.
const Set<String> kStreamSchemes = {
  'http',
  'https',
  'rtmp',
  'rtmps',
  'rtmpe',
  'rtmpt',
  'rtsp',
  'rtsps',
  'rtp',
  'udp',
  'mms',
  'mmsh',
  'mmst',
  'srt',
};

final RegExp _streamAddress = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*)://[^/\\\s?#]');

/// Whether [url] is a network stream address: one of [kStreamSchemes]
/// followed by a host. Placeholders (`{utc}`) are fine: a catch-up
/// template is checked before it is filled.
bool isStreamUrl(String url) {
  final m = _streamAddress.firstMatch(url.trim());
  return m != null && kStreamSchemes.contains(m[1]!.toLowerCase());
}

/// Builds playable URLs. Xtream URLs are computed at play time from the
/// source credentials so a password change does not require a full refresh.
class StreamUrls {
  static String _seg(String? v) => Uri.encodeComponent(v ?? '');

  static String live(Source s, Channel c) {
    if (c.url != null && c.url!.isNotEmpty) return c.url!;
    return '${s.baseUrl}/live/${_seg(s.username)}/${_seg(s.password)}/${c.extId}.${s.liveFormat}';
  }

  static String movie(Source s, Movie m) {
    if (m.url != null && m.url!.isNotEmpty) return m.url!;
    return '${s.baseUrl}/movie/${_seg(s.username)}/${_seg(s.password)}/${m.extId}.${m.container ?? 'mp4'}';
  }

  static String episode(Source s, Episode e) {
    if (e.url != null && e.url!.isNotEmpty) return e.url!;
    return '${s.baseUrl}/series/${_seg(s.username)}/${_seg(s.password)}/${e.extId}.${e.container ?? 'mp4'}';
  }
}

/// Catch-up ("replay") addresses for past programmes of live channels.
///
/// Xtream: `/timeshift/<user>/<pass>/<minutes>/<YYYY-MM-DD:HH-MM>/<id>.ts`.
/// M3U playlists describe it with `catchup` / `catchup-source`
/// (default, append, shift, flussonic) and placeholders such as {utc},
/// {lutc}, {duration}, ${start}, ${timestamp}, {Y}-{m}-{d}.
class ReplayUrls {
  static String _two(int v) => v.toString().padLeft(2, '0');

  static String? build(Source s, Channel c, Program p, {DateTime? now}) {
    if (!c.hasReplay) return null;
    final at = now ?? DateTime.now();
    // Guide times were shifted at import; the provider uses its own clock.
    final start = p.start.subtract(Duration(minutes: s.epgOffsetMinutes));
    final stop = p.stop.subtract(Duration(minutes: s.epgOffsetMinutes));
    final minutes = (stop.difference(start).inSeconds / 60).ceil().clamp(1, 24 * 60);
    final type = (c.catchupType ?? (s.isXtream ? 'xc' : 'default')).toLowerCase();

    if (type == 'xc' || (s.isXtream && (c.url == null || c.url!.isEmpty))) {
      // The panel reads this time on its own clock, not on this computer's:
      // abroad (or with a provider hosted in another country) the replay
      // started hours away from the programme. Its offset is known from the
      // account answer; without it, this computer's time as before.
      final offset = s.accountInfo?['utc_offset'];
      final wall = offset is int ? start.toUtc().add(Duration(seconds: offset)) : start;
      final t = '${wall.year}-${_two(wall.month)}-${_two(wall.day)}:${_two(wall.hour)}-${_two(wall.minute)}';
      return '${s.baseUrl}/timeshift/${StreamUrls._seg(s.username)}/${StreamUrls._seg(s.password)}/'
          '$minutes/$t/${c.extId}.ts';
    }
    final live = c.url ?? '';
    final template = c.catchupSource;
    String fill(String t) => expand(t, start: start, stop: stop, now: at);
    switch (type) {
      case 'append':
        return live + fill(template ?? '?utc={utc}&lutc={lutc}');
      case 'shift':
        return '$live${live.contains('?') ? '&' : '?'}${fill('utc={utc}&lutc={lutc}')}';
      case 'flussonic' || 'flussonic-hls' || 'flussonic-ts' || 'fs':
        final secs = stop.difference(start).inSeconds;
        final utc = start.millisecondsSinceEpoch ~/ 1000;
        if (RegExp(r'/(index|playlist|mono)\.m3u8').hasMatch(live)) {
          return live.replaceFirstMapped(RegExp(r'/(index|playlist|mono)\.m3u8'), (m) => '/${m[1]}-$utc-$secs.m3u8');
        }
        if (live.contains('/mpegts')) return live.replaceFirst('/mpegts', '/timeshift_abs-$utc.ts');
        return live.replaceFirst(RegExp(r'/?$'), '/timeshift_abs-$utc.ts');
      default:
        if (template == null || template.isEmpty) {
          return '$live${live.contains('?') ? '&' : '?'}${fill('utc={utc}&lutc={lutc}')}';
        }
        // A relative template is appended to the live address.
        if (!template.contains('://')) return live + fill(template);
        return fill(template);
    }
  }

  /// Replaces catch-up placeholders.
  static String expand(String t, {required DateTime start, required DateTime stop, required DateTime now}) {
    final utc = start.millisecondsSinceEpoch ~/ 1000;
    final end = stop.millisecondsSinceEpoch ~/ 1000;
    final lutc = now.millisecondsSinceEpoch ~/ 1000;
    final duration = end - utc;
    final values = <String, String>{
      'utc': '$utc',
      'start': '$utc',
      'timestamp': '$utc',
      'utcend': '$end',
      'end': '$end',
      'lutc': '$lutc',
      'now': '$lutc',
      'duration': '$duration',
      'offset': '${lutc - utc}',
      'Y': '${start.year}',
      'm': _two(start.month),
      'd': _two(start.day),
      'H': _two(start.hour),
      'M': _two(start.minute),
      'S': _two(start.second),
    };
    return t.replaceAllMapped(RegExp(r'\$?\{([A-Za-z]+)(?::([^}]*))?\}'), (m) {
      final key = m[1]!;
      final format = m[2];
      // "{duration:60}" is the length in minutes, "{offset:3600}" the age in
      // hours: the number after the colon divides the seconds.
      if (format != null && (key == 'duration' || key == 'offset')) {
        final divider = int.tryParse(format.trim());
        if (divider == null || divider <= 0) return values[key]!;
        final seconds = key == 'duration' ? duration : lutc - utc;
        return '${seconds <= 0 ? 0 : seconds ~/ divider}';
      }
      if (format != null && (key == 'utc' || key == 'start' || key == 'utcend' || key == 'end')) {
        final d = key == 'utcend' || key == 'end' ? stop : start;
        return format
            .replaceAll('Y', '${d.year}')
            .replaceAll('m', _two(d.month))
            .replaceAll('d', _two(d.day))
            .replaceAll('H', _two(d.hour))
            .replaceAll('M', _two(d.minute))
            .replaceAll('S', _two(d.second));
      }
      return values[key] ?? m[0]!;
    });
  }
}
