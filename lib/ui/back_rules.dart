import 'package:flutter/widgets.dart';

import 'shell.dart';

/// What Back (TV remote, Échap) does in the tabs.
enum ShellBack { closeSearch, goHome, exit }

ShellBack shellBack({required bool searchOpen, required int tab}) {
  if (searchOpen) return ShellBack.closeSearch;
  if (tab != ShellTab.home) return ShellBack.goHome;
  return ShellBack.exit;
}

/// What Back does in the player, one layer at a time.
enum PlayerBack { closePanel, hideStats, leaveFullscreen, minimize, leave }

/// On a [tv] the player is always full screen: Back leaves it at once.
PlayerBack playerBack({
  required bool panelOpen,
  required bool statsShown,
  required bool fullscreen,
  required bool casting,
  required bool tv,
}) {
  if (panelOpen) return PlayerBack.closePanel;
  if (statsShown) return PlayerBack.hideStats;
  if (fullscreen && !tv) return PlayerBack.leaveFullscreen;
  if (casting) return PlayerBack.minimize;
  return PlayerBack.leave;
}

/// A screen whose Back (TV remote, Android) first closes its own layers
/// (panel, enlarged slot…): [onBack] runs until [atLastLayer], then Back
/// leaves the screen.
///
/// The screen's own exits (a "Quitter" button, the mini-player, leaving
/// while casting) go through [leave], never `maybePop`: that would be
/// turned into "close a layer" too, and the screen would never leave.
class BackLayers extends StatelessWidget {
  const BackLayers({super.key, required this.atLastLayer, required this.onBack, required this.child});

  final bool atLastLayer;
  final VoidCallback onBack;
  final Widget child;

  /// Leaves the screen now, whatever layer is open.
  static void leave(BuildContext context) => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: atLastLayer,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onBack();
    },
    child: child,
  );
}
