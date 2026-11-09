import 'dart:async';
import 'dart:io';

import 'package:bobine/cast/cast_device.dart';
import 'package:bobine/cast/cast_service.dart';
import 'package:bobine/cast/cast_session.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/player/playback_tracker.dart';
import 'package:bobine/player/player_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A TV that plays what it is given.
class FakeTv implements CastSession {
  FakeTv(this.device);

  @override
  final CastDevice device;
  RemoteStatus status = RemoteStatus(state: RemoteState.playing);
  final _updates = StreamController<RemoteStatus>.broadcast();

  @override
  InternetAddress? get localAddress => InternetAddress.loopbackIPv4;
  @override
  Stream<RemoteStatus> get updates => _updates.stream;
  void push(RemoteStatus s) => _updates.add(status = s);
  @override
  Future<void> connect() async {}
  @override
  List<String> contentTypesFor(String url, {required bool live}) => ['video/x-matroska'];
  @override
  Future<void> load(CastMedia media, {Duration? start}) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double level) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<RemoteStatus> poll() async => status;
  @override
  Future<void> close() async {}
}

const _film = PlayItem(
  kind: ContentKind.movie,
  sourceId: 1,
  extId: '5',
  url: 'http://127.0.0.1:9/movie/u/p/5.mkv',
  title: 'Dune',
);
const _tv = CastDevice(id: 'tv', name: 'Salon', protocol: CastProtocol.dlna, host: '127.0.0.1', port: 1400);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('changing profile: the position goes to the profile that was watching, none to the next', () async {
    final repo = Repository(openMemoryDatabase());
    expect(repo.insertSource(name: 'X', type: SourceType.xtream, url: 'http://127.0.0.1:9'), 1);
    final other = repo.createProfile(name: 'Léa', color: 0xFF336699);
    late FakeTv tv;
    final cast = CastService(sessionFactory: (d) => tv = FakeTv(d));
    // No engine is created: the film plays on the TV.
    final player = PlayerService(AppSettings(repo), Directory.systemTemp.path);
    final tracker = PlaybackTracker(player, repo, onSaved: () {}, cast: cast);
    addTearDown(tracker.dispose);

    await cast.start(_tv, _film);
    tv.push(
      RemoteStatus(
        state: RemoteState.playing,
        position: const Duration(minutes: 40),
        duration: const Duration(minutes: 150),
      ),
    );
    // The tracker looks every 2 s: it has seen the film.
    await Future<void>.delayed(const Duration(milliseconds: 2400));
    expect(repo.progress(1, ContentKind.movie, '5'), isNull, reason: 'nothing written yet');

    // What AppServices.switchProfile does, in its order: save and forget,
    // stop without waiting, then the other profile.
    tracker.flushAndForget();
    unawaited(cast.stop());
    repo.profileId = other;
    await Future<void>.delayed(const Duration(milliseconds: 2400));

    expect(cast.active, isFalse);
    expect(repo.progress(1, ContentKind.movie, '5'), isNull, reason: 'nothing of it in the other profile');
    repo.profileId = 1;
    expect(repo.progress(1, ContentKind.movie, '5')?.position.inMinutes, 40);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
