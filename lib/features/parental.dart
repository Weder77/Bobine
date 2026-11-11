import 'dart:math' as math;

import '../core/format.dart';
import '../data/repository.dart';
import '../data/settings.dart';

/// Checks the parental code. After a few wrong codes in a row, each new
/// one makes the code refused a while longer: 4 digits are only 10 000
/// tries otherwise. The count is kept in the database, so restarting the
/// app does not start it again.
class ParentalGuard {
  ParentalGuard(this._repo, this._settings, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Repository _repo;
  final AppSettings _settings;
  final DateTime Function() _clock;

  /// Wrong codes allowed before the waits start.
  static const freeTries = 5;

  /// First wait, doubled at each wrong code after it, up to [maxWait].
  static const firstWait = Duration(seconds: 30);
  static const maxWait = Duration(hours: 1);

  static const _failsKey = 'parental.fails';
  static const _untilKey = 'parental.until';

  int get _fails => int.tryParse(_repo.kvGet(_failsKey) ?? '') ?? 0;

  /// Until when no code is accepted, or null.
  DateTime? get lockedUntil {
    final ms = int.tryParse(_repo.kvGet(_untilKey) ?? '');
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(_clock()) ? until : null;
  }

  /// Whether [pin] is the parental code. Always false while [lockedUntil],
  /// whatever is typed, and when the code saved here cannot be read.
  bool check(String pin) {
    if (lockedUntil != null) return false;
    final code = _settings.parentalPin;
    if (_settings.parentalEnabled && code != null && code.isNotEmpty && pin == code) {
      if (_fails != 0) {
        _repo.kvSet(_failsKey, null);
        _repo.kvSet(_untilKey, null);
      }
      return true;
    }
    final fails = _fails + 1;
    _repo.kvSet(_failsKey, '$fails');
    if (fails >= freeTries) {
      final wait = firstWait * math.pow(2, math.min(fails - freeTries, 10));
      final capped = wait > maxWait ? maxWait : wait;
      _repo.kvSet(_untilKey, '${_clock().add(capped).millisecondsSinceEpoch}');
    }
    return false;
  }

  /// Forgets the wrong codes typed (a new code was chosen).
  void reset() {
    _repo.kvSet(_failsKey, null);
    _repo.kvSet(_untilKey, null);
  }

  /// What to tell after a code was refused.
  String get refusal {
    final until = lockedUntil;
    if (until == null) return 'Code incorrect.';
    return 'Trop de codes faux : réessaie dans ${formatSpan(until.difference(_clock()))}.';
  }
}
