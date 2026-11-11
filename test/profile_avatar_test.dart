import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
      expect(b.profiles(), hasLength(Profile.max));
      final favorites = b.db.select('SELECT profile_id, ext_id FROM favorites');
      expect(favorites.map((r) => r['ext_id']), ['film-Léa']);
      expect(favorites.single['profile_id'], b.profiles().firstWhere((p) => p.name == 'Léa').id);
    });
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
