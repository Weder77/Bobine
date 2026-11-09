/// How often a live stream that stops is reopened.
///
/// Up to [max] attempts in a row, each after a longer wait ([step] × the
/// attempt number). The count starts again once the stream really played
/// for [recovery] ([playing] says when pictures come), and when another
/// stream is opened ([reset]). One failure often comes as several errors
/// ("tcp: …" then "Failed to open …"): nothing more is counted while an
/// attempt is pending.
class ReconnectBudget {
  ReconnectBudget({
    this.max = 6,
    this.step = const Duration(milliseconds: 600),
    this.recovery = const Duration(seconds: 45),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int max;
  final Duration step;
  final Duration recovery;
  final DateTime Function() _clock;

  int _attempts = 0;
  bool _pending = false;

  /// Since when the stream has been playing without stopping.
  DateTime? _playingSince;

  /// Attempts made in a row (shown as "Reconnexion… (2)").
  int get attempts => _attempts;

  /// An attempt is waiting to be launched.
  bool get pending => _pending;

  /// Every attempt was used and the stream did not come back.
  bool get exhausted => !_pending && _attempts >= max;

  /// Pictures are coming. Time alone says nothing: a dead stream can take a
  /// minute to fail, and counting that minute as "it held" gave it its
  /// attempts back every time, for ever.
  void playing() {
    if (!_pending) _playingSince ??= _clock();
  }

  /// The stream stopped. Returns how long to wait before reopening it, or
  /// null when an attempt is already pending or none is left (see
  /// [exhausted]).
  Duration? next() {
    if (_pending) return null;
    final since = _playingSince;
    _playingSince = null;
    if (since != null && _clock().difference(since) > recovery) _attempts = 0;
    if (_attempts >= max) return null;
    _attempts++;
    _pending = true;
    return step * _attempts;
  }

  /// The pending attempt is being made now.
  void launched() {
    _pending = false;
    _playingSince = null;
  }

  /// Another stream is opened, or the user asked again: a fresh count.
  void reset() {
    _attempts = 0;
    _pending = false;
    _playingSince = null;
  }
}
