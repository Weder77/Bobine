import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../player/mini_player.dart';
import '../../services.dart';
import '../launch.dart';

/// "It starts now" card for a programme the user asked to be reminded of.
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ValueListenableBuilder(
      valueListenable: s.reminders.due,
      builder: (context, r, _) {
        if (r == null) return const SizedBox.shrink();
        final starts = r.start.isAfter(DateTime.now())
            ? 'Dans ${r.start.difference(DateTime.now()).inMinutes + 1} min'
            : 'Commence maintenant';
        // Bottom left: clear of the top bar menus and of the mini-player.
        return Positioned(
          left: 32,
          bottom: 32,
          width: 380,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.borderStrong),
                boxShadow: [BoxShadow(color: AppColors.shadow(0x99), blurRadius: 30, offset: Offset(0, 12))],
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_rounded, color: AppColors.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$starts · ${formatClock(r.start)}', style: labelStyle(color: AppColors.textSoft)),
                        const SizedBox(height: 4),
                        Text(
                          r.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        Text(r.channelName, style: TextStyle(color: AppColors.textSoft)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                              onPressed: () {
                                s.reminders.dismiss();
                                final c = s.repo.channelByExt(r.sourceId, r.channelExt);
                                final ctx = appNavigatorKey.currentContext;
                                // Over a film or the multi-view: it takes their place.
                                if (c != null && ctx != null) Launch.channel(ctx, c, [c], replacing: true);
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Regarder'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(onPressed: s.reminders.dismiss, child: const Text('Plus tard')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
