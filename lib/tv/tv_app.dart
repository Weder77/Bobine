import 'package:flutter/material.dart';

import '../services.dart';
import '../ui/profiles.dart';
import 'tv_browse.dart';
import 'tv_focus.dart';
import 'tv_shell.dart';
import 'tv_theme.dart';

/// The TV version of Bobine (see docs/superpowers/specs/2026-11-14-bobine-tv-simple-design.md).
class TvShell extends StatelessWidget {
  const TvShell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.library]),
      builder: (context, _) => TvShellView(
        profile: ProfileAvatar(profile: s.profile, size: 56),
        pageBuilder: (context, tab, setEntry) => switch (tab) {
          TvTab.home || TvTab.films || TvTab.series => TvBrowsePage(tab: tab, setEntry: setEntry),
          _ => _TvSoon(tab: tab, setEntry: setEntry),
        },
      ),
    );
  }
}

/// Page not built yet (development only).
class _TvSoon extends StatelessWidget {
  const _TvSoon({required this.tab, required this.setEntry});
  final TvTab tab;
  final void Function(String? Function()) setEntry;

  @override
  Widget build(BuildContext context) {
    setEntry(() => 'soon-${tab.name}');
    return Center(
      child: TvFocusable(
        id: 'soon-${tab.name}',
        builder: (context, on) => Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: on ? Colors.white : TvColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(tab.name, style: tvText(30, color: on ? TvColors.bg : Colors.white)),
        ),
      ),
    );
  }
}
