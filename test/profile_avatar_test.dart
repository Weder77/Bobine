import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/features/backup.dart';
import 'package:bobine/features/profile_photo.dart';
import 'package:bobine/ui/profiles.dart';

img.Image _decoded(String avatar) => img.decodeJpg(ProfilePhoto.bytesOf(avatar)!)!;

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

/// A real PNG whose header claims [width] x [height] pixels.
Uint8List _pngClaiming(int width, int height) {
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));
  final data = ByteData.sublistView(png);
  // Signature (8), length (4), "IHDR" (4), then width and height.
  data.setUint32(16, width);
  data.setUint32(20, height);
  data.setUint32(29, _crc32(png.sublist(12, 29)));
  return png;
}

void main() {
  group('photo', () {
    test('a landscape photo is cut to its centre square and kept small', () {
      // Red on the sides, green in the middle: only the green stays.
      final src = img.Image(width: 900, height: 500);
      img.fill(src, color: img.ColorRgb8(220, 20, 20));
      img.fillRect(src, x1: 200, y1: 0, x2: 700, y2: 500, color: img.ColorRgb8(20, 200, 40));
      final avatar = ProfilePhoto.encode(img.encodeJpg(src));
      expect(avatar, startsWith(ProfilePhoto.prefix));
      expect(ProfilePhoto.isPhoto(avatar), isTrue);
      expect(ProfilePhoto.bytesOf(avatar)!.length, lessThanOrEqualTo(ProfilePhoto.maxBytes));
      final out = _decoded(avatar!);
      expect(out.width, out.height);
      expect(out.width, 192);
      for (final (x, y) in [(2, 2), (out.width - 3, out.height ~/ 2), (out.width ~/ 2, out.height - 3)]) {
        final p = out.getPixel(x, y);
        expect(p.g, greaterThan(150), reason: 'pixel $x,$y');
        expect(p.r, lessThan(80), reason: 'pixel $x,$y');
      }
    });

    test('a photo full of detail still fits, smaller or less sharp', () {
      final rnd = math.Random(7);
      final src = img.Image(width: 1200, height: 1200);
      for (final p in src) {
        p
          ..r = rnd.nextInt(256)
          ..g = rnd.nextInt(256)
          ..b = rnd.nextInt(256);
      }
      final avatar = ProfilePhoto.encode(img.encodePng(src));
      expect(avatar, isNotNull);
      expect(ProfilePhoto.bytesOf(avatar)!.length, lessThanOrEqualTo(ProfilePhoto.maxBytes));
    });

    test('a transparent picture is laid on the colour given, a small one is enlarged', () {
      final src = img.Image(width: 40, height: 40, numChannels: 4); // all transparent
      final avatar = ProfilePhoto.encode(img.encodePng(src), background: 0xFF7FA6FF);
      final out = _decoded(avatar!);
      expect(out.width, 192);
      final p = out.getPixel(96, 96);
      expect(p.r, closeTo(0x7F, 8));
      expect(p.g, closeTo(0xA6, 8));
      expect(p.b, closeTo(0xFF, 8));
    });

    test('a grey picture stays grey, with or without transparency', () {
      for (final channels in [1, 2]) {
        final src = img.Image(width: 120, height: 90, numChannels: channels);
        for (final p in src) {
          p
            ..r = 128
            ..a = 255;
        }
        final png = img.encodePng(src);
        expect(img.decodePng(png)!.numChannels, channels);
        final p = _decoded(ProfilePhoto.encode(png)!).getPixel(96, 96);
        expect([p.r, p.g, p.b], everyElement(closeTo(128, 6)), reason: '$channels channel(s): ${[p.r, p.g, p.b]}');
      }
    });

    test('a palette picture keeps its colours', () {
      final src = img.Image(width: 100, height: 100);
      img.fill(src, color: img.ColorRgb8(30, 90, 220));
      final gif = img.encodeGif(src);
      final p = _decoded(ProfilePhoto.encode(gif)!).getPixel(96, 96);
      expect(p.r, closeTo(30, 12));
      expect(p.g, closeTo(90, 12));
      expect(p.b, closeTo(220, 12));
    });

    test('a large JPEG is decoded at a reduced size; a huge picture is refused before decoding', () {
      final big = img.Image(width: 4000, height: 3000);
      img.fill(big, color: img.ColorRgb8(200, 120, 40));
      final out = _decoded(ProfilePhoto.encode(img.encodeJpg(big, quality: 60))!);
      expect(out.width, 192);
      expect(out.getPixel(96, 96).r, closeTo(200, 10));

      // 12000 x 12000 would take about 430 MB: never decoded.
      final huge = _pngClaiming(12000, 12000);
      expect(img.PngDecoder().startDecode(huge)!.width, 12000);
      expect(ProfilePhoto.encode(huge), isNull);
    });

    test('what is not a picture is refused', () {
      expect(ProfilePhoto.encode(Uint8List(0)), isNull);
      expect(ProfilePhoto.encode(Uint8List.fromList(utf8.encode('pas une image'))), isNull);
      expect(ProfilePhoto.bytesOf(null), isNull);
      expect(ProfilePhoto.bytesOf('preset:chat'), isNull);
      expect(ProfilePhoto.bytesOf('${ProfilePhoto.prefix}%%%'), isNull);
    });

    test('in another isolate too', () async {
      final src = img.Image(width: 300, height: 200);
      expect(await ProfilePhoto.fromFile(img.encodePng(src)), startsWith(ProfilePhoto.prefix));
    });
  });

  test('bundled pictures: every one offered is an asset, unknown names fall back to the initial', () {
    expect(profileAvatars, hasLength(6));
    for (final name in profileAvatars.keys) {
      expect(avatarAsset(presetAvatar(name)), 'assets/avatars/$name.png');
    }
    expect(avatarAsset(null), isNull);
    expect(avatarAsset('preset:licorne'), isNull); // from a newer version
    expect(avatarAsset('${ProfilePhoto.prefix}AAAA'), isNull);
  });

  test('a new profile has no picture; the picture is kept and changed with the profile', () {
    final repo = Repository(openMemoryDatabase());
    expect(repo.profiles().single.avatar, isNull);
    final id = repo.createProfile(name: 'Léa', color: 1, avatar: 'preset:robot');
    expect(repo.profile(id)!.avatar, 'preset:robot');
    repo.updateProfile(id, name: 'Léa', color: 1, kids: false, avatar: null);
    expect(repo.profile(id)!.avatar, isNull);
  });

  test('ten profiles at most', () {
    final repo = Repository(openMemoryDatabase());
    for (var i = 2; i <= Profile.max; i++) {
      expect(repo.canAddProfile, isTrue);
      repo.createProfile(name: 'P$i', color: 1);
    }
    expect(repo.profiles(), hasLength(Profile.max));
    expect(repo.canAddProfile, isFalse);
    expect(() => repo.createProfile(name: 'De trop', color: 1), throwsStateError);
    expect(repo.profiles(), hasLength(Profile.max));
    repo.deleteProfile(repo.profiles().last.id);
    expect(repo.canAddProfile, isTrue);
  });

  group('backup', () {
    (Repository, BackupService) install() {
      final repo = Repository(openMemoryDatabase());
      return (repo, BackupService(repo, AppSettings(repo)));
    }

    test('pictures and photos are saved and restored with their profile', () {
      final (a, aBackup) = install();
      final photo = ProfilePhoto.encode(img.encodePng(img.Image(width: 64, height: 64)))!;
      a.createProfile(name: 'Léa', color: 1, avatar: 'preset:clap');
      a.createProfile(name: 'Tom', color: 1, avatar: photo);
      final json = jsonDecode(jsonEncode(aBackup.build(credentials: false))) as Map<String, Object?>;

      final (b, bBackup) = install();
      expect(bBackup.restore(json).profilesCreated, 2);
      expect(b.profiles().firstWhere((p) => p.name == 'Léa').avatar, 'preset:clap');
      expect(b.profiles().firstWhere((p) => p.name == 'Tom').avatar, photo);
    });

    test('a profile found by name gets its picture back, unless it has one here', () {
      final (a, aBackup) = install();
      final moi = a.profile(1)!;
      a.updateProfile(1, name: moi.name, color: moi.color, kids: false, avatar: 'preset:chat');
      a.createProfile(name: 'Léa', color: 1, avatar: 'preset:panda');
      final json = jsonDecode(jsonEncode(aBackup.build(credentials: false))) as Map<String, Object?>;

      final (b, bBackup) = install(); // a new computer: it has its own "Moi"
      b.createProfile(name: 'Léa', color: 1, avatar: 'preset:robot');
      expect(bBackup.restore(json).profilesCreated, 0);
      expect(b.profile(1)!.avatar, 'preset:chat');
      expect(b.profiles().firstWhere((p) => p.name == 'Léa').avatar, 'preset:robot');
    });

    test('profiles beyond ten are left out, with what belongs to them', () {
      final (a, aBackup) = install();
      final src = a.insertSource(name: 'S', type: SourceType.m3u, url: 'http://s/list.m3u');
      for (final name in ['Léa', 'Tom', 'Zoé']) {
        a.profileId = a.createProfile(name: name, color: 1);
        a.toggleFavorite(src, ContentKind.movie, 'film-$name');
      }
      final json = jsonDecode(jsonEncode(aBackup.build(credentials: true))) as Map<String, Object?>;

      final (b, bBackup) = install();
      for (var i = 2; i < Profile.max; i++) {
        b.createProfile(name: 'P$i', color: 1); // room for one more
      }
      final report = bBackup.restore(json);
      expect(report.profilesCreated, 1);
      expect(report.skippedProfiles, ['Tom', 'Zoé']);
      expect(report.toString(), contains('${Profile.max} profils au maximum'));
      expect(report.toString(), isNot(contains('rien de nouveau')));
      expect(b.profiles(), hasLength(Profile.max));
      final favorites = b.db.select('SELECT profile_id, ext_id FROM favorites');
      expect(favorites.map((r) => r['ext_id']), ['film-Léa']);
      expect(favorites.single['profile_id'], b.profiles().firstWhere((p) => p.name == 'Léa').id);
    });
  });

  testWidgets('a kids profile with a picture still shows the child', (tester) async {
    Future<int> badges({required bool kids, String? avatar}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: AvatarView(avatar: avatar, color: 0xFF7FA6FF, initial: 'Z', kids: kids, size: 64),
          ),
        ),
      );
      return find.byIcon(Icons.child_care_rounded).evaluate().length;
    }

    expect(await badges(kids: true, avatar: 'preset:panda'), 1);
    expect(await badges(kids: true), 1); // the child instead of the initial
    expect(await badges(kids: false, avatar: 'preset:panda'), 0);
  });

  test('the sync log notes a change of picture alone', () {
    final repo = Repository(openMemoryDatabase());
    repo.db.execute('DELETE FROM sync_log');
    repo.updateProfile(1, name: 'Moi', color: repo.profile(1)!.color, kids: false, avatar: 'preset:popcorn');
    expect(repo.db.select('SELECT tbl, key FROM sync_log').map((r) => '${r['tbl']} ${r['key']}'), [
      'profiles $kDefaultProfileUid',
    ]);
    expect(repo.db.select('PRAGMA user_version').first.columnAt(0), kSchemaVersion);
  });
}
