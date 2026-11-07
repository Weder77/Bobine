import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/settings.dart';

/// Pops up "it starts now" for programmes the user asked to be reminded of
/// (while the app is open).
class ReminderService {
  ReminderService(this._repo, this._settings) {
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => check());
  }

  final Repository _repo;
  final AppSettings _settings;
  Timer? _timer;
  final Set<int> _shown = {};

  /// The reminder to show now, or null.
  final ValueNotifier<Reminder?> due = ValueNotifier(null);

  void check() {
    if (due.value != null) return;
    final now = DateTime.now();
    final lead = Duration(minutes: _settings.reminderLeadMinutes);
    for (final r in _repo.reminders()) {
      if (_shown.contains(r.id)) continue;
      if (now.isAfter(r.start.subtract(lead)) && now.isBefore(r.stop)) {
        _shown.add(r.id);
        due.value = r;
        return;
      }
    }
  }

  void dismiss() {
    due.value = null;
    check();
  }

  void dispose() => _timer?.cancel();
}
