import 'dart:async';
import 'dart:io';

import 'package:bobine/cast/cast_device.dart';
import 'package:bobine/cast/cast_service.dart';
import 'package:bobine/cast/cast_session.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/player/cast_view.dart';
import 'package:bobine/player/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A TV that refuses whatever it is sent.
class RefusingTv implements CastSession {
  RefusingTv(this.device);

  @override
  final CastDevice device;
  final loaded = <CastMedia>[];

  @override
  InternetAddress? get localAddress => InternetAddress.loopbackIPv4;
  @override
  Stream<RemoteStatus> get updates => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  List<String> contentTypesFor(String url, {required bool live}) => ['video/x-matroska'];
  @override
  Future<void> load(CastMedia media, {Duration? start}) async {
    loaded.add(media);
    throw CastException("La télé n'a pas pu lire ce flux.");
  }

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
  Future<RemoteStatus> poll() async => RemoteStatus();
  @override
  Future<void> close() async {}
}

const _tv = CastDevice(id: 'lg', name: 'Chambre', protocol: CastProtocol.dlna, host: '127.0.0.1', port: 1400);

PlayItem _film(String url) =>
    PlayItem(kind: ContentKind.movie, sourceId: 1, extId: '9', url: url, title: 'Le film', subtitle: '2024');

void main() {
  testWidgets('direct mode is confirmed before the TV is given the identifiers', (tester) async {
    late RefusingTv tv;
    final cast = CastService(sessionFactory: (d) => tv = RefusingTv(d));
    final asked = <bool?>[];
    Future<void> show(PlayItem item) async {
      await tester.runAsync(() => cast.start(_tv, item));
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: CastRemoteView(
              cast: cast,
              image: null,
              onRetry: ({bool? viaRelay}) => asked.add(viaRelay),
              onStop: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // An Xtream film: the address holds the login and the password.
    await show(_film('http://host:8080/movie/jean/s3cret/9.mkv'));
    // Through this computer by default: the TV was not given them.
    expect(tv.loaded.single.url, isNot(contains('s3cret')));
    await tester.tap(find.text('Essayer en direct'));
    await tester.pumpAndSettle();
    expect(find.text('Diffuser en direct ?'), findsOneWidget);
    expect(find.textContaining('identifiant et mot de passe compris'), findsOneWidget);
    expect(find.textContaining('« Chambre »'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(asked, isEmpty, reason: 'nothing changes without a yes');

    await tester.tap(find.text('Essayer en direct'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diffuser en direct'));
    await tester.pumpAndSettle();
    expect(asked, [false]);

    // A public address has nothing to give away: no question.
    asked.clear();
    await show(_film('https://cdn.example/film.mp4'));
    await tester.tap(find.text('Essayer en direct'));
    await tester.pumpAndSettle();
    expect(find.text('Diffuser en direct ?'), findsNothing);
    expect(asked, [false]);

    // Once in direct mode, the screen keeps saying what the TV was given.
    cast.setDirect(_tv, true);
    await show(_film('http://host:8080/movie/jean/s3cret/9.mkv'));
    expect(tv.loaded.single.url, contains('s3cret'));

    await tester.runAsync(cast.stop);
    await tester.pumpWidget(const SizedBox());
  });
}
