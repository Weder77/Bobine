import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/features/parental.dart';
import 'package:bobine/ui/widgets/pin_dialog.dart';

void main() {
  test('what can undo the parental control asks the code: always in a kids profile, elsewhere until typed', () {
    // No code: nothing to protect.
    expect(codeNeeded(enabled: false, kids: true, unlocked: false), isFalse);
    expect(codeNeeded(enabled: false, kids: false, unlocked: false), isFalse);
    // A kids profile: always, even after the code was typed for the categories.
    expect(codeNeeded(enabled: true, kids: true, unlocked: false), isTrue);
    expect(codeNeeded(enabled: true, kids: true, unlocked: true), isTrue);
    // Another profile: until the code was typed this session.
    expect(codeNeeded(enabled: true, kids: false, unlocked: false), isTrue);
    expect(codeNeeded(enabled: true, kids: false, unlocked: true), isFalse);
  });

  group('wrong codes', () {
    late Repository repo;
    late AppSettings settings;
    late DateTime now;
    ParentalGuard guard() => ParentalGuard(repo, settings, clock: () => now);

    setUp(() {
      repo = Repository(openMemoryDatabase());
      settings = AppSettings(repo)..update((s) => s.parentalPin = '1234');
      now = DateTime(2026, 11, 11, 20);
    });

    test('a few are free, then each one waits longer, even after a restart', () {
      var g = guard();
      for (var i = 0; i < ParentalGuard.freeTries - 1; i++) {
        expect(g.check('0000'), isFalse);
        expect(g.lockedUntil, isNull);
      }
      expect(g.check('0000'), isFalse);
      expect(g.lockedUntil, now.add(ParentalGuard.firstWait));
      expect(g.refusal, contains('réessaie dans'));
      // Locked: even the right code is refused.
      expect(g.check('1234'), isFalse);
      // The app restarts: still locked.
      g = guard();
      expect(g.lockedUntil, isNotNull);
      now = now.add(ParentalGuard.firstWait + const Duration(seconds: 1));
      expect(g.check('1111'), isFalse);
      expect(g.lockedUntil, now.add(ParentalGuard.firstWait * 2), reason: 'the wait doubles');
      now = now.add(const Duration(hours: 2));
      expect(g.check('1234'), isTrue);
      expect(g.check('0000'), isFalse);
      expect(g.lockedUntil, isNull, reason: 'the count starts again after the right code');
    });

    test('the waits stop growing at an hour', () {
      final g = guard();
      for (var i = 0; i < 30; i++) {
        now = now.add(const Duration(hours: 2));
        g.check('0000');
      }
      expect(g.lockedUntil, now.add(ParentalGuard.maxWait));
    });
  });

  test('a code that could not be typed is not taken from a backup or the account', () {
    final settings = AppSettings(Repository(openMemoryDatabase()))..update((s) => s.parentalPin = '1234');
    for (final bad in ['12345', 'abcd', '12 4', 42]) {
      settings.applySynced({'parentalPin': bad});
      expect(settings.parentalPin, '1234', reason: '$bad');
      settings.restoreBackup({'parentalPin': bad});
      expect(settings.parentalPin, '1234', reason: '$bad');
    }
    settings.applySynced({'parentalPin': '9876'});
    expect(settings.parentalPin, '9876');
    settings.applySynced({'parentalPin': null});
    expect(settings.parentalEnabled, isFalse);
  });

  test('a code encrypted elsewhere keeps the control on, unsent, until a new one is chosen', () {
    final repo = Repository(openMemoryDatabase());
    // What another computer's DPAPI wrote: unreadable here.
    repo.kvSet('settings', jsonEncode({'parentalPin': 'dpapi:AAAAAAAA'}));
    final settings = AppSettings(repo);
    expect(settings.parentalPinUnreadable, isTrue);
    expect(settings.parentalEnabled, isTrue);
    expect(ParentalGuard(repo, settings).check(''), isFalse);
    expect(settings.syncedValues().containsKey('parentalPin'), isFalse, reason: 'not "no code" for the account');
    settings.update((s) => s.seekStep = 30); // saved: the stored code stays
    expect(AppSettings(repo).parentalPinUnreadable, isTrue);
    settings
      ..forgetUnreadablePin()
      ..update((s) => s.parentalPin = '4321');
    expect(settings.parentalPinUnreadable, isFalse);
    expect(ParentalGuard(repo, settings).check('4321'), isTrue);
  });

  test('adult categories are found without accents or case, and look-alikes are not', () {
    for (final name in ['EROTIQUE', 'Érotique', 'XXX', 'Adultes', 'SEXE', 'Films -18', '18+', 'Charme', 'For Adults']) {
      expect(Repository.looksAdult(name), isTrue, reason: name);
    }
    for (final name in ['Adult Swim', 'Young Adult', 'Shot', 'Sport', 'Sexton', 'France 3', 'Top 18 ans']) {
      expect(Repository.looksAdult(name), isFalse, reason: name);
    }
  });

  test('a recording whose channel left the list stays out while the code is needed', () {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
    repo.hideLocked = true;
    expect(repo.isRecordingLocked(src, 'gone'), isTrue);
    repo.hideLocked = false;
    expect(repo.isRecordingLocked(src, 'gone'), isFalse);
  });
}
