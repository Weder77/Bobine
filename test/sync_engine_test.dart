import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/sync/sync_crypto.dart';
import 'package:bobine/sync/sync_engine.dart';

/// Same rules as `sync_push` on Supabase: the most recent version wins, the
/// server's newer versions are sent back, every write gets a new rev.
class MemoryRemote implements SyncRemote {
  final Map<String, RemoteItem> items = {};
  int _rev = 0;

  /// Runs while a push is "on the network".
  void Function()? duringPush;

  @override
  Future<List<RemoteItem>> pull(int afterRev, {int limit = 1000}) async {
    final list = items.values.where((i) => i.rev > afterRev).toList()..sort((a, b) => a.rev.compareTo(b.rev));
    return list.take(limit).toList();
  }

  @override
  Future<List<RemoteItem>> push(List<RemoteItem> sent) async {
    duringPush?.call();
    final newer = <RemoteItem>[];
    for (final i in sent) {
      final current = items[i.id];
      if (current == null || i.modifiedAt > current.modifiedAt) {
        items[i.id] = RemoteItem(
          id: i.id,
          modifiedAt: i.modifiedAt,
          deleted: i.deleted,
          payload: i.payload,
          rev: ++_rev,
        );
      } else if (current.modifiedAt > i.modifiedAt) {
        newer.add(current);
      }
    }
    return newer;
  }
}

final _keys = SyncKeys.deriveSync('moi@example.com', 'mot de passe', iterations: 10);

class Device {
  Device(this.remote, [SyncKeys? keys]) : repo = Repository(openMemoryDatabase()) {
    settings = AppSettings(repo);
    engine = SyncEngine(repo: repo, codec: SyncCodec(keys ?? _keys), remote: remote, settings: settings);
  }

  final MemoryRemote remote;
  final Repository repo;
  late final AppSettings settings;
  late final SyncEngine engine;

  Future<SyncChanges> sync() => engine.run();

  int xtream({String name = 'Mon IPTV', String password = 's3cret'}) => repo.insertSource(
    name: name,
    type: SourceType.xtream,
    url: 'http://tv.example:8080',
    username: 'bob',
    password: password,
  );

  Source source(String name) => repo.sources().firstWhere((s) => s.name == name);
  Profile profile(String name) => repo.profiles().firstWhere((p) => p.name.toLowerCase() == name.toLowerCase());
  int get pending => repo.db.select('SELECT count(*) AS n FROM sync_log').first['n'] as int;

  void watch(int src, String ext, Duration position) => repo.saveProgress(
    sourceId: src,
    kind: ContentKind.movie,
    extId: ext,
    position: position,
    duration: const Duration(minutes: 100),
    title: 'Film $ext',
  );
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 3));

void main() {
  test('keys: PBKDF2 test vectors, encryption round trip, tampering and wrong keys', () async {
    String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    expect(
      hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 1)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 4096)),
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    );

    final again = SyncKeys.deriveSync(' Moi@Example.com ', 'mot de passe', iterations: 10);
    expect(again.authSecret, _keys.authSecret); // the email is normalised
    expect(_keys.authSecret, isNot(contains('mot de passe')));
    expect(base64Url.normalize(_keys.authSecret), isNotEmpty);
    expect(SyncKeys.fromStorage(_keys.toStorage())!.encKey, _keys.encKey);

    final codec = SyncCodec(_keys);
    final id = codec.itemId('["favorites","x"]');
    expect(id, hasLength(43));
    final sealed = await codec.seal(id, {'secret': 's3cret'});
    expect(sealed, isNot(contains('s3cret')));
    expect(await codec.open(id, sealed), {'secret': 's3cret'});
    // Moved to another id, altered or read with other keys: refused.
    await expectLater(codec.open(codec.itemId('other'), sealed), throwsA(isA<SyncKeyException>()));
    final bytes = base64Decode(sealed)..[20] ^= 1;
    await expectLater(codec.open(id, base64Encode(bytes)), throwsA(isA<SyncKeyException>()));
    final other = SyncCodec(SyncKeys.deriveSync('moi@example.com', 'autre', iterations: 10));
    await expectLater(other.open(id, sealed), throwsA(isA<SyncKeyException>()));
  });

  test('a second device receives sources, profiles, favourites, progress and preferences', () async {
    final remote = MemoryRemote();
    final a = Device(remote);
    final src = a.xtream();
    final lea = a.repo.createProfile(name: 'Léa', color: 0xFF7FA6FF, kids: true);
    a.repo.toggleFavorite(src, ContentKind.movie, '503');
    a.repo.profileId = lea;
    a.repo.toggleFavorite(src, ContentKind.series, '900');
    a.repo.profileId = 1;
    a.watch(src, '501', const Duration(minutes: 20));
    a.repo.setCategoryHidden(src, ContentKind.live, 'sport', true);
    a.repo.setChannelHidden(src, 'tf1', true);
    a.settings.update((s) {
      s.seekStep = 30;
      s.parentalPin = '1234';
      s.cacheMb = 4096; // depends on the computer: stays here
    });

    final sentA = await a.sync();
    expect(sentA.sent, greaterThan(5));
    expect(a.pending, 0);
    // The server sees nothing readable.
    final stored = remote.items.values.map((i) => '${i.id} ${i.payload}').join();
    for (final clear in ['s3cret', 'tv.example', 'Léa', '503', '1234', 'sport']) {
      expect(stored, isNot(contains(clear)));
    }

    final b = Device(remote);
    final got = await b.sync();
    expect(got.sourcesAdded, hasLength(1));
    expect(got.profiles && got.userData && got.settings, isTrue);
    final bSrc = b.source('Mon IPTV');
    expect(bSrc.password, 's3cret');
    expect(b.repo.isFavorite(bSrc.id, ContentKind.movie, '503'), isTrue);
    final bLea = b.profile('Léa');
    expect(bLea.kids, isTrue);
    b.repo.profileId = bLea.id;
    expect(b.repo.isFavorite(bSrc.id, ContentKind.series, '900'), isTrue);
    expect(b.repo.isFavorite(bSrc.id, ContentKind.movie, '503'), isFalse);
    b.repo.profileId = 1;
    expect(b.repo.progress(bSrc.id, ContentKind.movie, '501')!.position, const Duration(minutes: 20));
    expect(b.repo.db.select('SELECT hidden FROM category_prefs').single['hidden'], 1);
    expect(b.repo.db.select('SELECT hidden FROM channel_prefs').single['hidden'], 1);
    expect(b.settings.seekStep, 30);
    expect(b.settings.parentalPin, '1234');
    expect(b.settings.cacheMb, 1024);
    expect(b.repo.profiles(), hasLength(2)); // "Moi" is the same profile on both
    expect(b.pending, 0, reason: 'what came from the account is not sent back');

    final again = await b.sync();
    expect(again.sent + again.received, 0);
  });

  test('deletions, newer changes and preferences go both ways', () async {
    final remote = MemoryRemote();
    final a = Device(remote), b = Device(remote);
    final srcA = a.xtream();
    a.repo.toggleFavorite(srcA, ContentKind.movie, '1');
    a.repo.toggleFavorite(srcA, ContentKind.movie, '2');
    a.watch(srcA, '7', const Duration(minutes: 5));
    await a.sync();
    await b.sync();
    final srcB = b.source('Mon IPTV').id;

    // Removed on A, watched further on B.
    a.repo.toggleFavorite(srcA, ContentKind.movie, '1');
    await _tick();
    b.watch(srcB, '7', const Duration(minutes: 40));
    b.settings.update((s) => s.audioLang = 'en');
    await a.sync();
    await b.sync();
    await a.sync();
    expect(b.repo.isFavorite(srcB, ContentKind.movie, '1'), isFalse);
    expect(b.repo.isFavorite(srcB, ContentKind.movie, '2'), isTrue);
    expect(a.repo.progress(srcA, ContentKind.movie, '7')!.position, const Duration(minutes: 40));
    expect(a.settings.audioLang, 'en');

    // The volume (local) changing on A does not bring back A's old languages.
    a.settings.update((s) => s.volume = 40);
    b.settings.update((s) => s.audioLang = 'de');
    await b.sync();
    await a.sync();
    expect(a.settings.audioLang, 'de');

    // A source deleted on B disappears from A with its favourites.
    b.repo.deleteSource(srcB);
    await b.sync();
    final changes = await a.sync();
    expect(changes.sources, isTrue);
    expect(a.repo.sources(), isEmpty);
    expect(a.repo.db.select('SELECT * FROM favorites'), isEmpty);
    expect(a.pending, 0);
  });

  test('the newer of two conflicting changes wins on both devices', () async {
    final remote = MemoryRemote();
    final a = Device(remote), b = Device(remote);
    final srcA = a.xtream();
    a.watch(srcA, '9', const Duration(minutes: 1));
    await a.sync();
    await b.sync();
    final srcB = b.source('Mon IPTV').id;

    // Both offline: B watches later than A.
    a.watch(srcA, '9', const Duration(minutes: 10));
    await _tick();
    b.watch(srcB, '9', const Duration(minutes: 30));
    await b.sync();
    await a.sync(); // A's older change loses
    await b.sync();
    expect(a.repo.progress(srcA, ContentKind.movie, '9')!.position, const Duration(minutes: 30));
    expect(b.repo.progress(srcB, ContentKind.movie, '9')!.position, const Duration(minutes: 30));

    // The other way round: A is newer but B synchronises first.
    b.watch(srcB, '9', const Duration(minutes: 50));
    await _tick();
    a.watch(srcA, '9', const Duration(minutes: 60));
    await b.sync();
    await a.sync();
    await b.sync();
    expect(a.repo.progress(srcA, ContentKind.movie, '9')!.position, const Duration(minutes: 60));
    expect(b.repo.progress(srcB, ContentKind.movie, '9')!.position, const Duration(minutes: 60));
  });

  test('linking a device that already has data merges it instead of duplicating', () async {
    final remote = MemoryRemote();
    final a = Device(remote);
    final srcA = a.xtream();
    a.repo.createProfile(name: 'Léa', color: 1);
    a.repo.toggleFavorite(srcA, ContentKind.movie, 'a-fav');
    a.watch(srcA, 'shared', const Duration(minutes: 10));
    await a.sync();

    final b = Device(remote);
    // Same provider and login, added by hand before the account existed.
    final srcB = b.xtream(name: 'IPTV salon');
    final leaB = b.repo.createProfile(name: 'léa', color: 2);
    b.repo.toggleFavorite(srcB, ContentKind.movie, 'b-fav');
    b.repo.profileId = leaB;
    b.repo.toggleFavorite(srcB, ContentKind.live, 'b-lea');
    b.repo.profileId = 1;
    b.watch(srcB, 'shared', const Duration(minutes: 45)); // more recent
    await b.sync();
    await a.sync();

    for (final d in [a, b]) {
      expect(d.repo.sources(), hasLength(1));
      expect(d.repo.profiles(), hasLength(2));
      final s = d.repo.sources().single.id;
      expect(d.repo.favoriteKeys(s, ContentKind.movie), {'a-fav', 'b-fav'});
      expect(d.repo.progress(s, ContentKind.movie, 'shared')!.position, const Duration(minutes: 45));
      d.repo.profileId = d.profile('Léa').id;
      expect(d.repo.favoriteKeys(s, ContentKind.live), {'b-lea'});
      d.repo.profileId = 1;
    }
    // Both end up with the same names: B's, made after the account's.
    expect(a.repo.sources().single.name, 'IPTV salon');
    expect(b.repo.sources().single.name, 'IPTV salon');
    expect(a.profile('Léa').name, b.profile('Léa').name);
  });

  test('first sync keeps a profile the device used, even deleted on the account', () async {
    final remote = MemoryRemote();
    final a = Device(remote);
    final srcA = a.xtream();
    a.repo.toggleFavorite(srcA, ContentKind.movie, 'a-old'); // in "Moi", sent to the account
    final alice = a.repo.createProfile(name: 'Alice', color: 1);
    await a.sync();
    // "Moi" (same uid on every device) is deleted on A.
    a.repo.profileId = alice;
    a.repo.deleteProfile(1);
    await _tick();
    await a.sync();
    expect(a.repo.profiles().map((p) => p.name), ['Alice']);

    // A new, empty device follows the account: no "Moi" there either, even
    // though favourites of the deleted profile are still on the account.
    final fresh = Device(remote);
    await fresh.sync();
    expect(fresh.repo.profiles().map((p) => p.name), ['Alice']);
    expect(fresh.repo.db.select('SELECT * FROM favorites'), isEmpty);

    // A device used for months without an account: its "Moi" has favourites
    // and progress that exist nowhere else.
    final b = Device(remote);
    final srcB = b.xtream();
    b.repo.toggleFavorite(srcB, ContentKind.movie, 'b-fav');
    b.watch(srcB, 'film', const Duration(minutes: 30));
    b.repo.db.execute('DELETE FROM sync_log'); // nothing was ever noted for it
    await b.sync();
    expect(b.repo.profiles().map((p) => p.name).toSet(), {'Moi', 'Alice'});
    expect(b.repo.isFavorite(b.repo.sources().single.id, ContentKind.movie, 'b-fav'), isTrue);
    expect(b.repo.progress(b.repo.sources().single.id, ContentKind.movie, 'film')!.position.inMinutes, 30);
    expect(b.pending, 0);

    // "Moi" lives on the account again, with what B had.
    await a.sync();
    expect(a.repo.profiles().map((p) => p.name).toSet(), {'Moi', 'Alice'});
    a.repo.profileId = a.profile('Moi').id;
    expect(a.repo.isFavorite(srcA, ContentKind.movie, 'b-fav'), isTrue);
    expect(a.repo.progress(srcA, ContentKind.movie, 'film')!.position.inMinutes, 30);
  });

  test('a profile deleted on one linked device is deleted on the other', () async {
    final remote = MemoryRemote();
    final a = Device(remote), b = Device(remote);
    final src = a.xtream();
    final lea = a.repo.createProfile(name: 'Léa', color: 1);
    await a.sync();
    await b.sync();
    final leaB = b.profile('Léa').id;
    b.repo.profileId = leaB;
    b.repo.toggleFavorite(b.repo.sources().single.id, ContentKind.movie, 'x');
    b.repo.profileId = 1;
    await b.sync();
    await _tick();
    a.repo.deleteProfile(lea);
    await a.sync();
    final changes = await b.sync();
    expect(changes.profiles, isTrue);
    expect(b.repo.profiles().map((p) => p.name), ['Moi']);
    expect(b.repo.db.select('SELECT * FROM favorites WHERE profile_id = ?', [leaB]), isEmpty);
    expect(a.repo.isFavorite(src, ContentKind.movie, 'x'), isFalse);
  });

  test('first sync: an account without parental code or TMDB key does not erase the device ones', () async {
    final remote = MemoryRemote();
    // The account is created on a laptop that has neither.
    final laptop = Device(remote);
    laptop.settings.update((s) => s.audioLang = 'en');
    await laptop.sync();
    expect(laptop.settings.parentalPin, isNull);

    // The family PC had its code and key before accounts existed.
    final family = Device(remote);
    family.settings.update((s) {
      s.parentalPin = '4821';
      s.tmdbKey = 'cle-tmdb';
      s.audioLang = 'de';
    });
    family.repo.db.execute('DELETE FROM sync_log'); // as after the v5 migration
    final changes = await family.sync();
    expect(family.settings.parentalPin, '4821');
    expect(family.settings.tmdbKey, 'cle-tmdb');
    // Values both sides have: the account still wins on the first sync.
    expect(family.settings.audioLang, 'en');
    expect(changes.settings, isTrue);
    expect(family.pending, 0);

    // The code now protects the laptop too.
    await laptop.sync();
    expect(laptop.settings.parentalPin, '4821');
    expect(laptop.settings.tmdbKey, 'cle-tmdb');

    // Once linked, removing the code on purpose goes through normally.
    await _tick();
    laptop.settings.update((s) => s.parentalPin = null);
    await laptop.sync();
    await family.sync();
    expect(family.settings.parentalPin, isNull);
  });

  test('data a device held before the update loses to the account on linking', () async {
    final remote = MemoryRemote();
    final a = Device(remote);
    a.xtream();
    await a.sync();
    final b = Device(remote);
    b.xtream(name: 'Ancien nom');
    b.repo.db.execute('DELETE FROM sync_log'); // as after the v5 migration
    await b.sync();
    expect(b.repo.sources().single.name, 'Mon IPTV');
    await a.sync();
    expect(a.repo.sources().single.name, 'Mon IPTV');
  });

  test('a change made while sending is sent next time', () async {
    final remote = MemoryRemote();
    final a = Device(remote), b = Device(remote);
    final src = a.xtream();
    a.watch(src, '1', const Duration(minutes: 1));
    remote.duringPush = () {
      remote.duringPush = null;
      a.watch(src, '1', const Duration(minutes: 2));
    };
    await a.sync();
    expect(a.pending, 1);
    await a.sync();
    expect(a.pending, 0);
    await b.sync();
    expect(b.repo.progress(b.source('Mon IPTV').id, ContentKind.movie, '1')!.position, const Duration(minutes: 2));
  });

  test('another password cannot read the account', () async {
    final remote = MemoryRemote();
    final a = Device(remote);
    a.xtream();
    await a.sync();
    final intruder = Device(remote, SyncKeys.deriveSync('moi@example.com', 'devine', iterations: 10));
    await expectLater(intruder.sync(), throwsA(isA<SyncKeyException>()));
    expect(intruder.repo.sources(), isEmpty);
  });
}
