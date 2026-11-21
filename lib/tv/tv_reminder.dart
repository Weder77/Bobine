import 'package:flutter/material.dart';

import '../data/models.dart';
import '../player/mini_player.dart' show appNavigatorKey;
import '../services.dart';
import '../ui/launch.dart';
import 'tv_focus.dart';
import 'tv_form.dart';
import 'tv_rows.dart';
import 'tv_stage.dart';
import 'tv_theme.dart';

/// On the TV, a reminder that falls due opens a card of its own over what
/// is on screen (Direct, a film…): the remote goes to its two buttons, then
/// back where it was.
class TvReminderPrompt extends StatefulWidget {
  const TvReminderPrompt({super.key});

  @override
  State<TvReminderPrompt> createState() => _TvReminderPromptState();
}

class _TvReminderPromptState extends State<TvReminderPrompt> {
  ValueNotifier<Reminder?>? _due;
  Route<void>? _route;
  int? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final due = AppScope.of(context).reminders.due;
    if (due != _due) {
      _due?.removeListener(_changed);
      _due = due..addListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
    }
  }

  @override
  void dispose() {
    _due?.removeListener(_changed);
    super.dispose();
  }

  void _close() {
    final route = _route;
    _route = null;
    _shown = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  void _changed() {
    if (!mounted) return;
    final r = _due?.value;
    if (r?.id == _shown) return;
    _close();
    final nav = appNavigatorKey.currentState;
    if (r == null || nav == null) return;
    final route = PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => TvReminderCard(reminder: r),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    );
    _route = route;
    _shown = r.id;
    nav.push(route).whenComplete(() {
      if (_route == route) {
        _route = null;
        _shown = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// "Ça commence" on the TV: Regarder opens the channel (in place of a film
/// playing), Plus tard and Retour close the card.
class TvReminderCard extends StatefulWidget {
  const TvReminderCard({super.key, required this.reminder});
  final Reminder reminder;

  @override
  State<TvReminderCard> createState() => _TvReminderCardState();
}

class _TvReminderCardState extends State<TvReminderCard> {
  final _c = TvFocusController(initial: 'rem-watch');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _watch() {
    final s = AppScope.of(context);
    final r = widget.reminder;
    final channel = s.repo.channelByExt(r.sourceId, r.channelExt);
    // Closes this card (the prompt follows the reminder).
    s.reminders.dismiss();
    final ctx = appNavigatorKey.currentContext;
    if (channel != null && ctx != null) Launch.channel(ctx, channel, [channel], replacing: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final r = widget.reminder;
    final now = DateTime.now();
    final when = r.start.isAfter(now)
        ? 'Dans ${r.start.difference(now).inMinutes + 1} min · ${tvClock(r.start)}'
        : 'Commence maintenant · ${tvClock(r.start)}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) s.reminders.dismiss();
      },
      child: TvStage(
        background: const Color(0x00000000),
        child: Material(
          type: MaterialType.transparency,
          child: TvFocusScope(
            controller: _c,
            onBack: s.reminders.dismiss,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xE6000000), Color(0x00000000)],
                        stops: [0, 0.6],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 96,
                  bottom: 96,
                  width: 1000,
                  child: Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: TvColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TvColors.border, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('RAPPEL · $when'.toUpperCase(), style: tvKicker()),
                        const SizedBox(height: 18),
                        Text(
                          r.title.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tvTitle(tvTitleSize(r.title, 64)),
                        ),
                        const SizedBox(height: 12),
                        Text(r.channelName, style: tvText(28, color: TvColors.soft, height: 1.2)),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            TvButton(
                              id: 'rem-watch',
                              label: 'Regarder',
                              icon: Icons.play_arrow_rounded,
                              primary: true,
                              onOk: _watch,
                            ),
                            const SizedBox(width: 20),
                            TvButton(id: 'rem-later', label: 'Plus tard', onOk: s.reminders.dismiss),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
