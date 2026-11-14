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
