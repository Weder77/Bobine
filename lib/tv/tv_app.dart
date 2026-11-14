import 'package:flutter/material.dart';

import '../services.dart';
import '../ui/profiles.dart';
import 'tv_browse.dart';
import 'tv_guide.dart';
import 'tv_live.dart';
import 'tv_settings.dart';
import 'tv_shell.dart';

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
          TvTab.live => TvLivePage(setEntry: setEntry),
          TvTab.guide => TvGuidePage(setEntry: setEntry),
          TvTab.settings => TvSettingsPage(setEntry: setEntry),
        },
      ),
    );
  }
}
