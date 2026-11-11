import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/features/profile_photo.dart';
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
    // The column check of the real table: one payload too large and the
    // whole call fails.
    if (sent.any((i) => i.payload.length > 16384)) throw StateError('payload too large');
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

/// The id, on the account, of the first item of [table].
Future<String> _itemOf(MemoryRemote remote, String table) async {
  final codec = SyncCodec(_keys);
  for (final i in remote.items.values.toList()..sort((a, b) => a.rev.compareTo(b.rev))) {
    if ((await codec.open(i.id, i.payload))['t'] == table) return i.id;
  }
  throw StateError('no $table on the account');
}

/// Alters the stored content of an item, as a disk or a bug would.
void _damage(MemoryRemote remote, String id) {
  final i = remote.items[id]!;
  final bytes = base64Decode(i.payload)..[20] ^= 1;
  remote.items[id] = RemoteItem(
    id: i.id,
    modifiedAt: i.modifiedAt,
    deleted: i.deleted,
    payload: base64Encode(bytes),
    rev: i.rev,
  );
}

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

  test('what a device deleted while signed out is not deleted from the account when it signs in again', () async {
    final remote = MemoryRemote();
    final a = Device(remote), b = Device(remote);
    final srcA = a.xtream();
    a.repo.toggleFavorite(srcA, ContentKind.movie, '1');
    await a.sync();
    await b.sync();

    // A signs out, cleans this computer, signs in again.
    a.repo.kvSet(SyncEngine.cursorKey, null);
    a.repo.deleteSource(srcA);
    await _tick();
    await a.sync();
    await b.sync();
    final srcB = b.source('Mon IPTV').id;
    expect(b.repo.isFavorite(srcB, ContentKind.movie, '1'), isTrue);
    expect(a.pending, 0);
    // The account's source comes back here, as on any device linked.
    expect(a.repo.sources().map((s) => s.name), ['Mon IPTV']);

    // Once linked, a deletion is sent as before.
    a.repo.deleteSource(a.source('Mon IPTV').id);
    await _tick();
    await a.sync();
    await b.sync();
    expect(b.repo.sources(), isEmpty);
  });

  test('accepting an invalid certificate follows the source to the other devices', () async {
    final remote = MemoryRemote();
    final a = Device(remote), b = Device(remote);
    a.repo.insertSource(
      name: 'Panel',
      type: SourceType.xtream,
      url: 'https://tv.example',
      username: 'bob',
      password: 'p',
      acceptInvalidCertificate: true,
    );
    await a.sync();
    await b.sync();
    expect(b.source('Panel').acceptInvalidCertificate, isTrue);
    final src = a.source('Panel');
    a.repo.updateSource(src.id, name: 'Panel', url: src.url, username: 'bob', password: 'p');
    await _tick();
    await a.sync();
    await b.sync();
    expect(b.source('Panel').acceptInvalidCertificate, isFalse);
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

  group('a device whose clock is wrong', () {
    const day = 86400000;
    late MemoryRemote remote;
    late Device a, b;
    late int srcA, srcB;

    setUp(() async {
      remote = MemoryRemote();
      a = Device(remote);
      b = Device(remote);
      srcA = a.xtream();
      await a.sync();
      await b.sync();
      srcB = b.source('Mon IPTV').id;
    });

    Duration? at(Device d, int src) => d.repo.progress(src, ContentKind.movie, '9')?.position;

    test('ahead: a change made later on another device is not undone', () async {
      // B's clock is a day ahead: what it changes is dated tomorrow.
      b.watch(srcB, '9', const Duration(minutes: 10));
      b.repo.db.execute('UPDATE sync_log SET changed_at = changed_at + $day');
      await b.sync();
      await a.sync();
      expect(at(a, srcA), const Duration(minutes: 10));

      // Later, on A, whose clock is right: dated today, so "before".
      a.watch(srcA, '9', const Duration(minutes: 50));
      await a.sync();
      expect(at(a, srcA), const Duration(minutes: 50), reason: 'it came back to 10 min');
      expect(a.pending, 0);
      await b.sync();
      expect(at(b, srcB), const Duration(minutes: 50));

      // Deleting works the same way.
      b.repo.toggleFavorite(srcB, ContentKind.movie, '9');
      b.repo.db.execute('UPDATE sync_log SET changed_at = changed_at + $day');
      await b.sync();
      await a.sync();
      expect(a.repo.isFavorite(srcA, ContentKind.movie, '9'), isTrue);
      a.repo.toggleFavorite(srcA, ContentKind.movie, '9');
      await a.sync();
      await b.sync();
      expect(a.repo.isFavorite(srcA, ContentKind.movie, '9'), isFalse);
      expect(b.repo.isFavorite(srcB, ContentKind.movie, '9'), isFalse);
    });

    test('late: its own later change is not refused', () async {
      b.watch(srcB, '9', const Duration(minutes: 10));
      await b.sync();
      await a.sync();
      // A's clock is a day late.
      a.watch(srcA, '9', const Duration(minutes: 50));
      a.repo.db.execute('UPDATE sync_log SET changed_at = changed_at - $day');
      await a.sync();
      await b.sync();
      expect(at(a, srcA), const Duration(minutes: 50));
      expect(at(b, srcB), const Duration(minutes: 50));
    });

    test('an item written by a newer Bobine is not written over by an older one', () async {
      a.watch(srcA, '9', const Duration(minutes: 10));
      await a.sync();
      // Another device, with a newer version, rewrites it in a format this
      // one does not know.
      final id = await _itemOf(remote, 'progress');
      final codec = SyncCodec(_keys);
      final record = await codec.open(id, remote.items[id]!.payload);
      final newer = await codec.seal(id, {...record, 'v': 2, 'nouveau': 'champ'});
      remote.items[id] = RemoteItem(
        id: id,
        modifiedAt: DateTime.now().millisecondsSinceEpoch + 60000,
        payload: newer,
        rev: ++remote._rev,
      );
      await a.sync(); // received, left aside
      expect(at(a, srcA), const Duration(minutes: 10));

      // A change here, dated before it: it was not made on top of it.
      a.watch(srcA, '9', const Duration(minutes: 50));
      await a.sync();
      expect(remote.items[id]!.payload, newer, reason: 'the old version wrote over what it could not read');
      expect(a.pending, 0);
      await a.sync();
      expect(remote.items[id]!.payload, newer);
    });

    test('two changes made without seeing each other: still the most recent one', () async {
      // Neither device has the other's version: nothing says which came
      // last but their times.
      a.watch(srcA, '9', const Duration(minutes: 10));
      await _tick();
      b.watch(srcB, '9', const Duration(minutes: 30));
      await b.sync();
      await a.sync();
      await b.sync();
      expect(at(a, srcA), const Duration(minutes: 30));
      expect(at(b, srcB), const Duration(minutes: 30));
    });
  });

  group('what cannot be read or applied is left aside', () {
    test('an item damaged on the account does not stop the others, now or later', () async {
      final remote = MemoryRemote();
      final a = Device(remote);
      final src = a.xtream();
      a.repo.toggleFavorite(src, ContentKind.movie, '503');
      a.watch(src, '501', const Duration(minutes: 20));
      await a.sync();
      _damage(remote, await _itemOf(remote, 'favorites'));

      final b = Device(remote);
      final first = await b.sync();
      expect(first.skipped, 1);
      final srcB = b.source('Mon IPTV').id;
      expect(b.repo.progress(srcB, ContentKind.movie, '501')!.position, const Duration(minutes: 20));
      expect(b.repo.isFavorite(srcB, ContentKind.movie, '503'), isFalse);
      // It is behind this device now: not met again at every synchronisation.
      expect((await b.sync()).skipped, 0);

      // Alone in what arrives: the rest of the account proves the keys right.
      a.watch(src, '777', const Duration(minutes: 5));
      await a.sync();
      _damage(remote, remote.items.values.reduce((x, y) => x.rev > y.rev ? x : y).id);
      final later = await b.sync();
      expect(later.skipped, 1);
      expect(b.repo.progress(srcB, ContentKind.movie, '777'), isNull);

      // The device that holds the real thing writes over it.
      a.watch(src, '777', const Duration(minutes: 6));
      await a.sync();
      await b.sync();
      expect(b.repo.progress(srcB, ContentKind.movie, '777')!.position, const Duration(minutes: 6));
    });

    test('a record this version cannot apply is skipped, not the ones around it', () async {
      final remote = MemoryRemote();
      final a = Device(remote);
      final src = a.xtream();
      await a.sync();
      final codec = SyncCodec(_keys);
      Future<void> plant(Map<String, Object?> record, List<Object?> key) async {
        final id = codec.itemId(jsonEncode(key));
        remote.items[id] = RemoteItem(
          id: id,
          modifiedAt: DateTime.now().millisecondsSinceEpoch,
          payload: await codec.seal(id, record),
          rev: ++remote._rev,
        );
      }

      // A source whose login is a number, and something that is no record.
      await plant(
        {
          't': 'sources',
          'k': ['uid-cassé'],
          'v': 1,
          'd': {'name': 'Cassée', 'type': 'xtream', 'url': 'http://x', 'username': 42},
        },
        ['sources', 'uid-cassé'],
      );
      await plant({'t': 'profiles', 'k': <Object?>[], 'v': 'un'}, ['profiles']);
      a.watch(src, '501', const Duration(minutes: 20));
      await a.sync();

      final b = Device(remote);
      final changes = await b.sync();
      expect(changes.skipped, 2);
      expect(b.repo.sources().map((s) => s.name), ['Mon IPTV']);
      expect(b.repo.progress(b.source('Mon IPTV').id, ContentKind.movie, '501')!.position, const Duration(minutes: 20));
      expect((await b.sync()).skipped, 0);
    });

    test('a row too large for the account stays here instead of blocking every sending', () async {
      final remote = MemoryRemote();
      final a = Device(remote);
      final src = a.xtream();
      await a.sync();
      a.repo.saveProgress(
        sourceId: src,
        kind: ContentKind.movie,
        extId: 'énorme',
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 100),
        title: 'Film',
        image: 'data:image/png;base64,${'A' * 20000}',
      );
      a.watch(src, '501', const Duration(minutes: 20));
      final changes = await a.sync();
      expect(changes.skipped, 1);
      expect(a.pending, 0);

      final b = Device(remote);
      await b.sync();
      final srcB = b.source('Mon IPTV').id;
      expect(b.repo.progress(srcB, ContentKind.movie, '501')!.position, const Duration(minutes: 20));
      expect(b.repo.progress(srcB, ContentKind.movie, 'énorme'), isNull);
      expect(a.repo.progress(src, ContentKind.movie, 'énorme'), isNotNull);
    });
  });

  test('a run whose account is gone stops before writing anything', () async {
    final remote = MemoryRemote();
    final other = Device(remote);
    other.xtream();
    await other.sync();

    final a = Device(remote);
    var gone = false;
    final engine = SyncEngine(
      repo: a.repo,
      codec: SyncCodec(_keys),
      remote: remote,
      settings: a.settings,
      cancelled: () => gone,
    );
    // Signed out while the account was being read.
    gone = true;
    await expectLater(engine.run(), throwsA(isA<SyncCancelled>()));
    expect(a.repo.sources(), isEmpty);
    expect(engine.cursor, isNull);

    // Signed out while sending: what was noted is still to send.
    gone = false;
    a.repo.createProfile(name: 'Léa', color: 0xFF7FA6FF);
    remote.duringPush = () => gone = true;
    final before = remote.items.length;
    await expectLater(engine.run(), throwsA(isA<SyncCancelled>()));
    remote.duringPush = null;
    expect(a.pending, greaterThan(0));
    expect(remote.items.length, greaterThan(before), reason: 'the server had it; it is sent again, harmlessly');
  });

  group('an account that cannot be trusted', () {
    test('the deleted flag in clear deletes nothing, and a date in clear does not win', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      final src = a.xtream();
      a.repo.toggleFavorite(src, ContentKind.movie, '503');
      await a.sync();
      await b.sync();
      final bSrc = b.source('Mon IPTV').id;
      expect(b.repo.isFavorite(bSrc, ContentKind.movie, '503'), isTrue);

      // The server marks everything deleted and dated in the future, the
      // sealed content left as it was.
      final future = DateTime.now().millisecondsSinceEpoch + 3600000;
      for (final i in remote.items.values.toList()) {
        remote.items[i.id] = RemoteItem(
          id: i.id,
          modifiedAt: future,
          deleted: true,
          payload: i.payload,
          rev: ++remote._rev,
        );
      }
      final got = await b.sync();
      expect(b.repo.sources(), hasLength(1), reason: 'nothing deleted');
      expect(b.repo.isFavorite(bSrc, ContentKind.movie, '503'), isTrue);
      expect(got.skipped, greaterThan(0), reason: 'the altered items are left aside');
    });

    test('an older version handed back again is not followed', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      a.settings.update((s) => s.parentalPin = '1234');
      await a.sync();
      await b.sync();
      expect(b.settings.parentalPin, '1234');
      final codec = SyncCodec(_keys);
      String? pin;
      for (final i in remote.items.values) {
        final r = await codec.open(i.id, i.payload);
        if (r['t'] == 'settings' && (r['k'] as List).first == 'parentalPin') pin = i.id;
      }
      final withCode = remote.items[pin]!;

      // The code changes on A; then the server hands B the old version again.
      await _tick();
      a.settings.update((s) => s.parentalPin = '5678');
      await a.sync();
      await b.sync();
      expect(b.settings.parentalPin, '5678');
      remote.items[pin!] = RemoteItem(
        id: pin,
        modifiedAt: withCode.modifiedAt,
        payload: withCode.payload,
        rev: ++remote._rev,
      );
      await b.sync();
      expect(b.settings.parentalPin, '5678', reason: 'the old code came back');
    });
  });

  group('profile pictures', () {
    String? avatarOf(Device d, String name) => d.profile(name).avatar;

    void setAvatar(Device d, String name, String? avatar) {
      final p = d.profile(name);
      d.repo.updateProfile(p.id, name: p.name, color: p.color, kids: p.kids, avatar: avatar);
    }

    test('a bundled picture and a photo follow the profile, and so does going back to the initial', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      a.repo.createProfile(name: 'Léa', color: 0xFF7FA6FF, avatar: 'preset:renard');
      await a.sync();
      await b.sync();
      expect(avatarOf(b, 'Léa'), 'preset:renard');

      // The largest photo kept, with a long name: still one item on the account.
      final photo = ProfilePhoto.prefix + base64Encode(List.generate(ProfilePhoto.maxBytes, (i) => (i * 7919) % 256));
      final long = 'Léa ${'é' * 300}';
      final lea = a.profile('Léa');
      a.repo.updateProfile(lea.id, name: long, color: lea.color, kids: false, avatar: photo);
      await _tick();
      final sent = await a.sync();
      expect(sent.skipped, 0);
      await b.sync();
      expect(avatarOf(b, long), photo);

      setAvatar(a, long, null);
      await _tick();
      await a.sync();
      await b.sync();
      expect(avatarOf(b, long), isNull);
    });

    test('a version without pictures changing the profile does not take its picture away', () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      a.repo.createProfile(name: 'Léa', color: 0xFF7FA6FF, avatar: 'preset:panda');
      await a.sync();
      await b.sync();

      // An older Bobine renames the profile: its record has no picture.
      final codec = SyncCodec(_keys);
      String? id;
      Map<String, Object?>? record;
      for (final i in remote.items.values) {
        final r = await codec.open(i.id, i.payload);
        if (r['t'] == 'profiles' && (r['d'] as Map?)?['name'] == 'Léa') (id, record) = (i.id, r);
      }
      final data = Map<String, Object?>.from(record!['d'] as Map)
        ..remove('avatar')
        ..['name'] = 'Léa B.';
      remote.items[id!] = RemoteItem(
        id: id,
        modifiedAt: DateTime.now().millisecondsSinceEpoch + 1000,
        // An older Bobine does not seal the time either.
        payload: await codec.seal(id, {...record, 'd': data}..remove('m')),
        rev: ++remote._rev,
      );
      await b.sync();
      expect(b.profile('Léa B.').avatar, 'preset:panda');

      // The picture goes back to the account: a device linking now gets it.
      await b.sync();
      final c = Device(remote);
      await c.sync();
      expect(c.profile('Léa B.').avatar, 'preset:panda');
      await a.sync();
      expect(a.profile('Léa B.').avatar, 'preset:panda');
      // And it settles: nothing more goes back and forth.
      await a.sync();
      await b.sync();
      expect((await a.sync()).sent + (await b.sync()).sent, 0);
    });

    test('changing only the picture is a change to send', () async {
      final remote = MemoryRemote();
      final a = Device(remote);
      await a.sync();
      expect(a.pending, 0);
      setAvatar(a, 'Moi', 'preset:chat');
      expect(a.pending, 1);
    });
  });
}
