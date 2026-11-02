import 'models.dart';

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
