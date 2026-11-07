import '../data/models.dart';
import 'player_service.dart';

/// What the full screen player was opened with, kept when it shrinks into
/// the mini-player so it can grow back to the same place.
class PlayerSession {
  const PlayerSession({
    required this.item,
    this.start,
    this.channels,
    this.channelIndex = 0,
    this.episodes,
    this.series,
    this.keepAlive = false,
  });

  final PlayItem item;

  /// Resume position.
  final Duration? start;

  /// Live: channels of the current list, for zapping.
  final List<Channel>? channels;
  final int channelIndex;

  /// Series: all episodes, for "next episode".
  final List<Episode>? episodes;
  final Series? series;

  /// Keep the stream running when leaving (live preview continues behind).
  final bool keepAlive;

  PlayerSession copyWith({PlayItem? item, int? channelIndex, bool clearStart = false}) => PlayerSession(
    item: item ?? this.item,
    start: clearStart ? null : start,
    channels: channels,
    channelIndex: channelIndex ?? this.channelIndex,
    episodes: episodes,
    series: series,
    keepAlive: keepAlive,
  );
}
