import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/data/stream_urls.dart';

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
