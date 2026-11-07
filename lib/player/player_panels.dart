import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/epg_cache.dart';
import '../data/models.dart';
import '../ui/widgets/common.dart';
import 'player_widgets.dart';

/// Dark glass used by the panels drawn over the video.
const playerGlass = Color(0xD10A0A0C);

/// Technical figures (key I).
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.stats});
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 104,
    left: 32,
    child: IgnorePointer(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: playerGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STATISTIQUES · I',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.accent),
            ),
            const SizedBox(height: 10),
            for (final (k, v) in stats)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
                    ),
                    Expanded(
                      child: Text(
                        v.isEmpty ? '—' : v,
                        style: const TextStyle(fontSize: 13.5, fontFeatures: tabularFigures),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// "Audio" and "Sous-titres" side by side, above the controls.
class TracksPanel extends StatelessWidget {
  const TracksPanel({
    super.key,
    required this.tracks,
    required this.audioId,
    required this.subtitleId,
    required this.onAudio,
    required this.onSubtitle,
    required this.onClose,
  });
  final Tracks tracks;
  final String audioId;
  final String subtitleId;
  final ValueChanged<AudioTrack> onAudio;
  final ValueChanged<SubtitleTrack> onSubtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final noSub = !subs.any((t) => t.id == subtitleId);
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onClose),
          ),
          Positioned(
            right: 40,
            bottom: 140,
            child: Container(
              width: 600,
              constraints: const BoxConstraints(maxHeight: 460),
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              decoration: BoxDecoration(
                color: const Color(0xF51C1C21),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _TrackColumn(
                      title: 'Audio',
                      empty: 'Une seule piste',
                      entries: [
                        for (var i = 0; i < audio.length; i++)
                          (
                            audioTrackTitle(audio[i], i),
                            audioTrackDetail(audio[i]),
                            audio[i].id == audioId,
                            () => onAudio(audio[i]),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: _TrackColumn(
                      title: 'Sous-titres',
                      entries: [
                        ('Désactivés', '', noSub, () => onSubtitle(SubtitleTrack.no())),
                        for (var i = 0; i < subs.length; i++)
                          (
                            subtitleTrackTitle(subs[i], i),
                            subtitleTrackDetail(subs[i]),
                            subs[i].id == subtitleId,
                            () => onSubtitle(subs[i]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One column of the "Audio & sous-titres" panel.
class _TrackColumn extends StatelessWidget {
  const _TrackColumn({required this.title, required this.entries, this.empty});
  final String title;
  final List<(String, String, bool, VoidCallback)> entries;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (entries.isEmpty && empty != null) Text(empty!, style: const TextStyle(color: AppColors.muted)),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, detail, selected, onTap) in entries)
                  HoverBuilder(
                    builder: (context, hover) => Semantics(
                      button: true,
                      selected: selected,
                      child: GestureDetector(
                        onTap: onTap,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 30, child: selected ? const Icon(Icons.check_rounded, size: 20) : null),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                        color: selected || hover ? AppColors.text : const Color(0xFFB8B9BF),
                                      ),
                                    ),
                                    if (detail.isNotEmpty)
                                      Text(detail, style: const TextStyle(fontSize: 13, color: AppColors.faint)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Side list of channels to zap without leaving full screen (key C).
class ChannelPanel extends StatelessWidget {
  const ChannelPanel({
    super.key,
    required this.open,
    required this.channels,
    required this.selected,
    required this.epg,
    required this.scroll,
    required this.onPick,
    required this.onClose,
  });
  final bool open;
  final List<Channel> channels;
  final int selected;
  final EpgCache epg;
  final ScrollController scroll;
  final ValueChanged<int> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      right: open ? 0 : -400,
      width: 380,
      child: Material(
        color: const Color(0xF507080B),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 12, 12),
                child: Row(
                  children: [
                    Expanded(child: Text('Chaînes', style: displayStyle(24))),
                    IconButton(tooltip: 'Fermer (C)', onPressed: onClose, icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              Expanded(
                child: open
                    ? ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemExtent: 66,
                        itemCount: channels.length,
                        itemBuilder: (context, i) {
                          final c = channels[i];
                          final sel = i == selected;
                          final now = epg.now(c);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Material(
                              color: sel ? const Color(0x24FFFFFF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => onPick(i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 34,
                                        child: Text(
                                          '${c.number ?? i + 1}',
                                          style: TextStyle(
                                            color: sel ? AppColors.text : AppColors.faint,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: tabularFigures,
                                          ),
                                        ),
                                      ),
                                      ChannelLogo(name: c.name, url: c.logo, size: 40),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                            if (now != null)
                                              Text(
                                                now.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Épisode suivant dans 8 s" card at the end of an episode.
class NextEpisodeCard extends StatelessWidget {
  const NextEpisodeCard({
    super.key,
    required this.episode,
    required this.countdown,
    required this.onPlay,
    required this.onCancel,
  });
  final Episode episode;
  final int countdown;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 32,
      bottom: 170,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ÉPISODE SUIVANT DANS $countdown S', style: labelStyle(color: AppColors.accent)),
            const SizedBox(height: 6),
            Text(
              '${episode.code} · ${episode.displayTitle}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: displayStyle(19, weight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Lancer'),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onCancel, child: const Text('Annuler')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "⚡ +04:12 en cache" next to the position.
class CachePill extends StatelessWidget {
  const CachePill(this.ahead, {super.key});
  final Duration ahead;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bolt_rounded, size: 15, color: AppColors.accent),
        const SizedBox(width: 5),
        Text(
          '+${formatDuration(ahead)} en cache',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFDDE1E8),
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    ),
  );
}
