import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show SizedBox, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/core/text.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/player/multi_view.dart';
import 'package:bobine/player/player_service.dart';

class FakeEngine implements TileEngine {
  final opened = <String>[];
  double? volume;
  bool disposed = false;
  final _state = ValueNotifier(const TileState(loading: false));

  @override
  ValueListenable<TileState> get state => _state;

  @override
  Future<void> open(PlayItem item) async => opened.add(item.url);

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Widget view() => const SizedBox();

  @override
  Future<void> dispose() async => disposed = true;
}

(Repository, Source, List<Channel>) _fixture({int? maxConnections}) {
  final repo = Repository(openMemoryDatabase());
  final id = repo.insertSource(
    name: 'S',
    type: SourceType.xtream,
    url: 'http://tv.example:8080',
    username: 'u',
    password: 'p',
  );
  if (maxConnections != null) {
    repo.db.execute('UPDATE sources SET account_info = ? WHERE id = ?', ['{"max_connections":"$maxConnections"}', id]);
  }
  for (var i = 1; i <= 6; i++) {
    repo.db.execute('INSERT INTO channels (source_id, ext_id, name, search, position) VALUES (?, ?, ?, ?, ?)', [
      id,
      '$i',
      'Sport $i',
      searchKey('Sport $i'),
      i,
    ]);
  }
  final channels = [for (var i = 1; i <= 6; i++) repo.channelByExt(id, '$i')!];
  return (repo, repo.source(id)!, channels);
}

void main() {
  test('every layout is made of 16:9 cells inside a 16:9 stage, without overlap', () {
    for (final l in MultiLayout.values) {
      final rects = l.rects;
      expect(rects, hasLength(l.slots), reason: l.name);
      for (final r in rects) {
        expect(r.left >= 0 && r.top >= 0 && r.right <= 1 + 1e-9 && r.bottom <= 1 + 1e-9, isTrue, reason: '$l $r');
        expect(r.width, closeTo(r.height, 1e-9), reason: 'a square of the stage is 16:9 on screen ($l)');
      }
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          final o = rects[i].intersect(rects[j]);
          expect(o.width <= 1e-9 || o.height <= 1e-9, isTrue, reason: '$l: $i and $j overlap');
        }
      }
    }
    expect(MultiLayout.stage(const Size(1920, 1080)), const Rect.fromLTWH(0, 0, 1920, 1080));
    expect(MultiLayout.stage(const Size(1000, 1000)), const Rect.fromLTWH(0, 218.75, 1000, 562.5));
    expect(MultiLayout.stage(const Size(2560, 1080)), const Rect.fromLTWH(320, 0, 1920, 1080));
    expect(
      [for (var n = 1; n <= 4; n++) MultiLayout.forCount(n)],
      [MultiLayout.duo, MultiLayout.duo, MultiLayout.trio, MultiLayout.quad],
    );
  });

  test('channels fill the free slots, the layout grows, only the selected one is heard', () {
    final (repo, source, ch) = _fixture();
    final engines = <FakeEngine>[];
    final c = MultiViewController(
      repo: repo,
      source: source,
      engine: () {
        engines.add(FakeEngine());
        return engines.last;
      },
      volume: 80,
    )..restore();
    expect(c.isEmpty, isTrue);

    c.add(ch[0]);
    c.add(ch[1]);
    expect(c.layout, MultiLayout.duo);
    expect(engines.map((e) => e.opened.single), [contains('/live/u/p/1.ts'), contains('/live/u/p/2.ts')]);
    expect(c.selected, 1, reason: 'the channel just added is heard');
    expect(engines[0].volume, 0);
    expect(engines[1].volume, 80);

    c.add(ch[2]);
    expect(c.layout, MultiLayout.trio);
    c.add(ch[3]);
    expect(c.layout, MultiLayout.quad);
    expect(c.count, 4);

    // Already there: it is heard, nothing reopens.
    c.add(ch[0]);
    expect(c.selected, 0);
    expect(engines, hasLength(4));
    expect(engines[0].volume, 80);
    expect(engines[3].volume, 0);

    // Full: the last slot changes channel with the same player.
    c.add(ch[4]);
    expect(engines, hasLength(4));
    expect(engines[3].opened.last, contains('/5.ts'));
    expect(c.slots[3]!.channel.extId, '5');

    c.toggleMute();
    expect(engines.every((e) => e.volume == 0), isTrue);
    c.toggleMute();
    c.changeVolume(-30);
    expect(engines[3].volume, 50);

    c.selectNext(1);
    expect(c.selected, 0);
    c.selectNext(-1);
    expect(c.selected, 3);
  });

  test('removing, changing layout and showing one slot alone', () {
    final (repo, source, ch) = _fixture();
    final engines = <FakeEngine>[];
    final c = MultiViewController(
      repo: repo,
      source: source,
      engine: () {
        engines.add(FakeEngine());
        return engines.last;
      },
    )..restore();
    for (final x in ch.take(4)) {
      c.add(x);
    }
    c.select(2);
    c.remove(2);
    expect(engines[2].disposed, isTrue);
    expect(c.slots[2], isNull);
    expect(c.selected, 0, reason: 'the sound goes to another channel');

    c.toggleSolo(3);
    expect(c.solo, 3);
    expect(c.selected, 3);
    c.toggleSolo(3);
    expect(c.solo, isNull);

    // 1 + 3 keeps the order; back to two slots stops the channel that no longer fits.
    c.setLayout(MultiLayout.focus);
    expect(c.channels.map((x) => x.extId), ['1', '2', '4']);
    c.setLayout(MultiLayout.duo);
    expect(c.channels.map((x) => x.extId), ['1', '2']);
    expect(engines[3].disposed, isTrue);
    expect(c.selected, 0, reason: 'the channel heard left the screen');
  });

  test('the multi-view comes back as it was, with the channel opened from elsewhere', () async {
    final (repo, source, ch) = _fixture();
    final first = MultiViewController(repo: repo, source: source, engine: FakeEngine.new)..restore();
    first.add(ch[0]);
    first.add(ch[1]);
    first.add(ch[2]);
    first.select(1);
    await first.stopAll();
    first.dispose();

    final again = MultiViewController(repo: repo, source: source, engine: FakeEngine.new)..restore();
    expect(again.layout, MultiLayout.trio);
    expect(again.channels.map((x) => x.extId), ['1', '2', '3']);
    expect(again.selected, 1);
    again.dispose();

    // Opened from channel 5: added, and heard.
    final withNew = MultiViewController(repo: repo, source: source, engine: FakeEngine.new)..restore(add: ch[4]);
    expect(withNew.channels.map((x) => x.extId), ['1', '2', '3', '5']);
    expect(withNew.layout, MultiLayout.quad);
    expect(withNew.selected, 3);
    withNew.dispose();

    // A channel gone from the playlist is skipped.
    repo.db.execute("DELETE FROM channels WHERE ext_id = '2'");
    final gone = MultiViewController(repo: repo, source: source, engine: FakeEngine.new)..restore();
    expect(gone.channels.map((x) => x.extId), ['1', '3', '5']);
    gone.dispose();
  });

  test('more streams than the subscription allows are flagged', () {
    final (repo, source, ch) = _fixture(maxConnections: 2);
    final c = MultiViewController(repo: repo, source: source, engine: FakeEngine.new)..restore();
    expect(c.maxConnections, 2);
    c.add(ch[0]);
    c.add(ch[1]);
    expect(c.overLimit, isFalse);
    c.add(ch[2]);
    expect(c.overLimit, isTrue);
    c.dispose();

    final (repo2, unknown, ch2) = _fixture();
    final d = MultiViewController(repo: repo2, source: unknown, engine: FakeEngine.new)..restore();
    for (final x in ch2.take(4)) {
      d.add(x);
    }
    expect(d.maxConnections, isNull);
    expect(d.overLimit, isFalse);
    d.dispose();
  });
}
