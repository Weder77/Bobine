import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'cast_service.dart';

/// Keeps the computer awake while it sends a stream to the TV. During a
/// cast the local player is stopped, and it alone kept the computer from
/// sleeping; the stream goes through this computer (the relay), so the TV
/// stopped when it fell asleep.
class CastKeepAwake {
  CastKeepAwake(this._cast, {required this.localPlaying, Future<void> Function(bool on)? toggle})
    : _toggle = toggle ?? ((on) => WakelockPlus.toggle(enable: on)) {
    _cast.addListener(_update);
  }

  final CastService _cast;

  /// The local player shows a picture: it keeps the computer awake itself.
  final bool Function() localPlaying;
  final Future<void> Function(bool on) _toggle;
  bool _on = false;

  @visibleForTesting
  bool get on => _on;

  void _update() {
    // Only while it really plays (or starts to): not on an error screen.
    final want = _cast.active && (_cast.playing || _cast.loading);
    if (want == _on) return;
    _on = want;
    if (want || !localPlaying()) {
      _toggle(want).catchError((Object e) => debugPrint('Mise en veille : $e'));
    }
  }

  void dispose() => _cast.removeListener(_update);
}
