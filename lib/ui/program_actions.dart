import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'launch.dart';
import 'widgets/common.dart';

/// What can be done with a guide programme, depending on when it airs.
enum ProgramTime { past, live, future }

ProgramTime programTime(Program p, [DateTime? now]) {
  final t = now ?? DateTime.now();
  if (p.isLiveAt(t)) return ProgramTime.live;
  return p.stop.isAfter(t) ? ProgramTime.future : ProgramTime.past;
}

/// Whether [p] can still be replayed on [c] (within its catch-up days).
bool canReplay(Channel c, Program p, [DateTime? now]) {
  final t = now ?? DateTime.now();
  return c.hasReplay && p.start.isBefore(t) && t.difference(p.start) <= Duration(days: c.catchupDays);
}

/// Dialog with the actions of a programme: watch, replay from the start,
/// remind, record.
Future<void> showProgramActions(BuildContext context, Channel c, Program p, {List<Channel>? channels}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ProgramDialog(channel: c, program: p, channels: channels ?? [c]),
  );
}

class _ProgramDialog extends StatefulWidget {
  const _ProgramDialog({required this.channel, required this.program, required this.channels});
  final Channel channel;
  final Program program;
  final List<Channel> channels;

  @override
  State<_ProgramDialog> createState() => _ProgramDialogState();
}

class _ProgramDialogState extends State<_ProgramDialog> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = widget.channel;
    final p = widget.program;
    final time = programTime(p);
    final replay = canReplay(c, p);
    final reminded = s.repo.hasReminder(c.sourceId, c.extId, p.start);
    final recording = s.repo.hasRecording(c.sourceId, c.extId, p.start.subtract(const Duration(minutes: 1)));
    void close() => Navigator.of(context).pop();

    final actions = <Widget>[
      if (time == ProgramTime.live)
        FilledButton.icon(
          onPressed: () {
            close();
            Launch.channel(context, c, widget.channels);
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 24),
          label: const Text('Regarder en direct'),
        ),
      if (replay)
        _button(
          primary: time != ProgramTime.live,
          onPressed: () {
            close();
            Launch.replay(context, c, p);
          },
          icon: const Icon(Icons.replay_rounded, size: 22),
          label: time == ProgramTime.live ? 'Depuis le début' : 'Revoir',
        ),
      if (time == ProgramTime.future)
        _button(
          primary: !reminded,
          onPressed: () {
            final on = s.repo.toggleReminder(c, p);
            s.library.userChanged();
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  on
                      ? 'Rappel le ${formatDay(p.start)} à ${formatClock(p.start)} pour « ${p.title} »'
                      : 'Rappel retiré',
                ),
              ),
            );
          },
          icon: Icon(reminded ? Icons.notifications_off_outlined : Icons.notifications_active_outlined, size: 22),
          label: reminded ? 'Ne plus me le rappeler' : 'Me le rappeler',
        ),
      if (time != ProgramTime.past)
        OutlinedButton.icon(
          onPressed: recording
              ? null
              : () {
                  if (time == ProgramTime.live) {
                    s.recordings.recordNow(c, current: p);
                  } else {
                    s.recordings.schedule(c, p);
                  }
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        time == ProgramTime.live
                            ? 'Enregistrement de « ${p.title} » en cours'
                            : 'Enregistrement prévu le ${formatDay(p.start)} à ${formatClock(p.start)}',
                      ),
                    ),
                  );
                },
          icon: Icon(Icons.fiber_manual_record_rounded, size: 18, color: recording ? AppColors.faint : AppColors.live),
          label: Text(recording ? 'Enregistrement prévu' : 'Enregistrer'),
        ),
    ];

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 14, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
      title: Row(
        children: [
          ChannelLogo(name: s.channelName(c), url: c.logo, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: displayStyle(22)),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (time == ProgramTime.live) const LiveBadge(),
                Text(
                  '${s.channelName(c)} · ${formatDay(p.start)} ${formatClock(p.start)} – ${formatClock(p.stop)}',
                  style: const TextStyle(color: AppColors.textSoft),
                ),
              ],
            ),
            if (p.description != null && p.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                p.description!,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.5, color: AppColors.textSoft),
              ),
            ],
            if (time == ProgramTime.past && !replay) ...[
              const SizedBox(height: 14),
              Text(
                c.hasReplay ? 'Trop ancien pour le replay de cette chaîne.' : "Cette chaîne n'a pas de replay.",
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            TextButton(onPressed: close, child: const Text('Fermer')),
            ...actions,
          ],
        ),
      ],
    );
  }
}

Widget _button({required bool primary, required VoidCallback onPressed, required Widget icon, required String label}) =>
    primary
    ? FilledButton.icon(onPressed: onPressed, icon: icon, label: Text(label))
    : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: Text(label));
