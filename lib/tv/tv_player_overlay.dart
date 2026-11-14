import 'package:flutter/material.dart';

import '../data/models.dart';
import 'tv_cards.dart';
import 'tv_rows.dart';
import 'tv_stage.dart';
import 'tv_theme.dart';

/// What the player shows on the TV.
class TvPlayerInfo {
  const TvPlayerInfo.live({required this.channelName, this.channelNumber, this.logo, this.program, this.next})
    : live = true,
      kicker = '',
      title = '',
      meta = '';

  const TvPlayerInfo.vod({required this.kicker, required this.title, this.meta = ''})
    : live = false,
      channelName = null,
      channelNumber = null,
      logo = null,
      program = null,
      next = null;

  final bool live;
  final String? channelName;
  final int? channelNumber;
  final String? logo;
  final Program? program;
  final Program? next;
  final String kicker;
  final String title;
  final String meta;
}

String _hms(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${sec.toString().padLeft(2, '0')}';
}

/// The design's player on the TV: who / what at the top, the title and the
/// progress at the bottom, and the keys of the remote (no buttons to pick).
class TvPlayerOverlay extends StatelessWidget {
  const TvPlayerOverlay({
    super.key,
    required this.info,
    required this.visible,
    required this.paused,
    required this.position,
    required this.duration,
    required this.seekStep,
    this.nextLabel,
  });

  final TvPlayerInfo info;
  final bool visible;
  final bool paused;
  final Duration position;
  final Duration duration;
  final int seekStep;

  /// The next episode offered at the end of this one ("S01E03 · Titre"):
  /// OK plays it.
  final String? nextLabel;

  Widget _top() {
    if (!info.live) return Text(info.kicker.toUpperCase(), style: tvKicker());
    return Row(
      children: [
        TvChannelBadge(name: info.channelName ?? '', logo: info.logo, size: 72),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.channelName ?? '', style: tvText(32, weight: FontWeight.w600, height: 1)),
            if (info.channelNumber != null) ...[
              const SizedBox(height: 10),
              Text('Chaîne ${info.channelNumber}', style: tvMono(24)),
            ],
          ],
        ),
        const SizedBox(width: 30),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: TvColors.accent, borderRadius: BorderRadius.circular(8)),
          child: Text(
            '● EN DIRECT',
            style: tvMono(24, weight: FontWeight.w700, color: TvColors.accentInk),
          ),
        ),
      ],
    );
  }

  Widget _bottom(DateTime now) {
    final p = info.program;
    if (info.live) {
      final title = p?.title ?? info.channelName ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p?.category != null) ...[Text(p!.category!.toUpperCase(), style: tvKicker()), const SizedBox(height: 22)],
          Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tvTitle(tvTitleSize(title, 96)),
          ),
          if (p != null) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Text(tvClock(p.start), style: tvMono(26)),
                const SizedBox(width: 22),
                SizedBox(width: 1000, child: TvBar(value: p.progressAt(now), height: 8, radius: 4)),
                const SizedBox(width: 22),
                Text(tvClock(p.stop), style: tvMono(26)),
                const SizedBox(width: 22),
                Text('reste ${tvDuration(p.stop.difference(now))}', style: tvMono(26, color: TvColors.faint)),
              ],
            ),
          ],
          if (info.next != null) ...[
            const SizedBox(height: 22),
            Text.rich(
              TextSpan(
                text: 'Ensuite ${tvClock(info.next!.start)} · ',
                children: [
                  TextSpan(
                    text: info.next!.title,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              style: tvText(26, color: TvColors.muted, height: 1),
            ),
          ],
        ],
      );
    }
    final total = duration.inMilliseconds;
    final frac = total <= 0 ? 0.0 : position.inMilliseconds / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          info.title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tvTitle(tvTitleSize(info.title, 96)),
        ),
        if (info.meta.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(info.meta, style: tvText(26, color: TvColors.soft, height: 1)),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(_hms(position), style: tvMono(26, color: Colors.white)),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: SizedBox(
                height: 24,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // The track spans the whole width (a Stack only loosens it).
                    Positioned(left: 0, right: 0, top: 8, child: TvBar(value: frac, height: 8, radius: 4)),
                    Align(
                      alignment: Alignment((frac.clamp(0.0, 1.0) * 2) - 1, 0),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(color: TvColors.accent, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 22),
            SizedBox(
              width: 120,
              child: Text('−${_hms(duration - position)}', textAlign: TextAlign.right, style: tvMono(26)),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final show = visible || paused || nextLabel != null;
    return IgnorePointer(
      child: TvStage(
        child: Stack(
          children: [
            AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB8000000), Color(0x00000000), Color(0x00000000), Color(0xF0000000)],
                    stops: [0, 0.22, 0.42, 1],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            if (paused)
              Positioned(
                left: 885,
                top: 400,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: const BoxDecoration(color: Color(0xA60D0C0B), shape: BoxShape.circle),
                  child: const Icon(Icons.pause_rounded, size: 72, color: Colors.white),
                ),
              ),
            Positioned(
              left: 96,
              right: 96,
              top: 56,
              child: AnimatedOpacity(opacity: show ? 1 : 0, duration: const Duration(milliseconds: 400), child: _top()),
            ),
            Positioned(
              left: 96,
              right: 96,
              bottom: 64,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: const Duration(milliseconds: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (nextLabel != null) ...[
                      Text('ÉPISODE SUIVANT', style: tvKicker()),
                      const SizedBox(height: 12),
                      Text(nextLabel!.toUpperCase(), style: tvTitle(44)),
                      const SizedBox(height: 28),
                    ],
                    _bottom(now),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        if (info.live)
                          const Row(children: [TvKey('▲'), SizedBox(width: 12), TvKey('▼')])
                        else
                          const Row(children: [TvKey('◀'), SizedBox(width: 12), TvKey('▶')]),
                        const SizedBox(width: 12),
                        Text(
                          info.live ? 'Changer de chaîne' : '$seekStep secondes',
                          style: tvText(26, color: TvColors.soft, height: 1),
                        ),
                        const SizedBox(width: 36),
                        TvKeyHint('OK', nextLabel != null ? 'Épisode suivant' : (paused ? 'Lecture' : 'Pause')),
                        const SizedBox(width: 36),
                        const TvKeyHint('Retour', 'Quitter'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
