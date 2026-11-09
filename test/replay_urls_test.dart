import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/stream_urls.dart';

void main() {
  final start = DateTime(2026, 11, 7, 20, 45);
  final p = Program(start: start, stop: start.add(const Duration(minutes: 105)), title: 'Match');
  final now = DateTime(2026, 11, 7, 23, 0);

  test('Xtream replay address', () {
    const s = Source(id: 1, name: 'X', type: SourceType.xtream, url: 'http://srv:8080', username: 'u', password: 'p w');
    const c = Channel(id: 1, sourceId: 1, extId: '42', name: 'Sport', catchupDays: 7, catchupType: 'xc');
    expect(ReplayUrls.build(s, c, p, now: now), 'http://srv:8080/timeshift/u/p%20w/105/2026-11-07:20-45/42.ts');
    // The guide offset is taken back out of the time sent to the provider.
    const shifted = Source(
      id: 1,
      name: 'X',
      type: SourceType.xtream,
      url: 'http://srv:8080',
      username: 'u',
      password: 'p',
      epgOffsetMinutes: 60,
    );
    expect(ReplayUrls.build(shifted, c, p, now: now), contains('/2026-11-07:19-45/'));
  });

  test('Xtream replay is asked at the time of the panel, not of this computer', () {
    const c = Channel(id: 1, sourceId: 1, extId: '42', name: 'Sport', catchupDays: 7, catchupType: 'xc');
    // 19:45 UTC, wherever the tests run.
    final at = DateTime.utc(2026, 11, 7, 19, 45).toLocal();
    final match = Program(start: at, stop: at.add(const Duration(minutes: 105)), title: 'Match');
    Source panel(int? offset) => Source(
      id: 1,
      name: 'X',
      type: SourceType.xtream,
      url: 'http://srv:8080',
      username: 'u',
      password: 'p',
      accountInfo: {'max_connections': 1, 'utc_offset': offset},
    );
    // A panel in Paris (UTC+1 in winter), one in New York, one in India.
    expect(ReplayUrls.build(panel(3600), c, match, now: now), contains('/105/2026-11-07:20-45/'));
    expect(ReplayUrls.build(panel(-5 * 3600), c, match, now: now), contains('/105/2026-11-07:14-45/'));
    expect(ReplayUrls.build(panel(5 * 3600 + 1800), c, match, now: now), contains('/105/2026-11-08:01-15/'));
    // A panel that does not say: this computer's time, as before.
    final local =
        '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}'
        ':${at.hour.toString().padLeft(2, '0')}-${at.minute.toString().padLeft(2, '0')}';
    expect(ReplayUrls.build(panel(null), c, match, now: now), contains('/105/$local/'));
  });

  test('a number after duration or offset divides the seconds', () {
    final stop = start.add(const Duration(minutes: 105));
    String fill(String t) => ReplayUrls.expand(t, start: start, stop: stop, now: now);
    // 105 minutes; the programme started 2 h 15 before "now".
    expect(fill('?d={duration}&m={duration:60}&h={duration:3600}'), '?d=6300&m=105&h=1');
    expect(fill(r'?o=${offset}&m=${offset:60}&h={offset:3600}'), '?o=8100&m=135&h=2');
    expect(fill('{duration:1}'), '6300');
    // Nonsense after the colon: the seconds, rather than a broken address.
    expect(fill('{duration:0}/{duration:x}'), '6300/6300');
    // A programme of the future has no age.
    expect(ReplayUrls.expand('{offset:60}', start: now.add(const Duration(hours: 1)), stop: stop, now: now), '0');
  });

  test('no replay without catch-up days', () {
    const s = Source(id: 1, name: 'X', type: SourceType.xtream, url: 'http://srv');
    const c = Channel(id: 1, sourceId: 1, extId: '42', name: 'Sport');
    expect(ReplayUrls.build(s, c, p, now: now), isNull);
  });

  test('M3U catch-up variants', () {
    const s = Source(id: 1, name: 'M', type: SourceType.m3u, url: 'http://list');
    final utc = start.millisecondsSinceEpoch ~/ 1000;
    final lutc = now.millisecondsSinceEpoch ~/ 1000;
    Channel ch(String type, [String? source]) => Channel(
      id: 1,
      sourceId: 1,
      extId: 'x',
      name: 'C',
      url: 'http://cdn/live/ch1/index.m3u8',
      catchupDays: 3,
      catchupType: type,
      catchupSource: source,
    );
    expect(ReplayUrls.build(s, ch('shift'), p, now: now), 'http://cdn/live/ch1/index.m3u8?utc=$utc&lutc=$lutc');
    expect(
      ReplayUrls.build(s, ch('append', '&start={utc}&end={utcend}'), p, now: now),
      'http://cdn/live/ch1/index.m3u8&start=$utc&end=${utc + 105 * 60}',
    );
    expect(ReplayUrls.build(s, ch('flussonic'), p, now: now), 'http://cdn/live/ch1/index-$utc-${105 * 60}.m3u8');
    expect(
      ReplayUrls.build(s, ch('default', 'http://arch/ch1/{Y}-{m}-{d}/{H}{M}.ts?d={duration}'), p, now: now),
      'http://arch/ch1/2026-11-07/2045.ts?d=${105 * 60}',
    );
    expect(
      ReplayUrls.build(s, ch('default', r'http://arch/${start}/${timestamp}'), p, now: now),
      'http://arch/$utc/$utc',
    );
    expect(
      ReplayUrls.build(s, ch('default', 'http://arch/{utc:Y-m-d:H-M}'), p, now: now),
      'http://arch/2026-11-07:20-45',
    );
  });
}
