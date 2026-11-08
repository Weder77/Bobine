import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/theme.dart';
import '../core/window.dart';
import '../services.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/reminder_banner.dart';
import 'player_screen.dart';
import 'player_service.dart';

/// Navigator of the app, so the mini-player (drawn above every page) can
/// reopen the full screen player.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Draws the mini-player above the pages, or the floating video when the
/// window itself became the floating player.
class PipLayer extends StatelessWidget {
  const PipLayer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.pip.session, s.pip.floating, s.player.current]),
      builder: (context, _) {
        final session = s.pip.session.value;
        // Playback stopped elsewhere: nothing left to show.
        if (session != null && s.player.current.value == null) {
          scheduleMicrotask(s.pip.close);
        }
        final show = session != null && s.player.current.value != null;
        if (s.pip.floating.value && show) {
          return Stack(
            children: [
              Offstage(child: child),
              const Positioned.fill(child: FloatingPlayerView()),
            ],
          );
        }
        return Stack(children: [child, if (show) const MiniPlayer(), const ReminderBanner()]);
      },
    );
  }
}

/// Reopens the full screen player where the mini-player was.
Future<void> expandPip(AppServices s) async {
  final session = s.pip.session.value;
  final nav = appNavigatorKey.currentState;
  if (session == null || nav == null) return;
  await s.pip.unfloat();
  final current = s.player.current.value;
  s.pip.release();
  await nav.push(PlayerScreen.route(session.copyWith(item: current ?? session.item, clearStart: true)));
}

/// Small video in a corner while browsing: drag it, pause it, grow it back.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  static const _width = 448.0;
  static const _height = _width * 9 / 16;
  Offset _offset = Offset.zero; // from the bottom-right corner
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final item = s.player.current.value;
    final right = (24 - _offset.dx).clamp(8.0, size.width - _width - 8);
    final bottom = (24 - _offset.dy).clamp(8.0, size.height - _height - 8);
    return Positioned(
      right: right,
      bottom: bottom,
      width: _width,
      height: _height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onPanUpdate: (d) => setState(() => _offset += d.delta),
          onDoubleTap: () => expandPip(s),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Color(0xB3000000), blurRadius: 80, offset: Offset(0, 30)),
                BoxShadow(color: Color(0x1FFFFFFF), spreadRadius: 1),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: s.player.video,
                  controls: NoVideoControls,
                  fill: Colors.black,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                ),
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _PipControls(
                    title: _title(s, item),
                    onExpand: () => expandPip(s),
                    onClose: s.pip.close,
                    onFloat: AppWindow.canFloat ? () => s.pip.float(s.pip.session.value!) : null,
                  ),
                ),
                if (item != null && !item.isLive)
                  Positioned(left: 0, right: 0, bottom: 0, child: _PipProgress(player: s.player)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "TF1 · Le journal" or "Les Veilleurs · S01E02".
String _title(AppServices s, PlayItem? item) {
  if (item == null) return '';
  if (item.isLive) {
    final c = s.repo.channelByExt(item.sourceId, item.extId);
    final name = c == null ? item.title : s.channelName(c);
    final now = c == null ? null : s.epg.now(c);
    return now == null ? name : '$name · ${now.title}';
  }
  return item.subtitle == null ? item.title : '${item.title} · ${item.subtitle!.split(' · ').first}';
}

/// The whole (small, always on top) window shows the video. Dragging it
/// moves the window; double-click brings the app back.
class FloatingPlayerView extends StatefulWidget {
  const FloatingPlayerView({super.key});

  @override
  State<FloatingPlayerView> createState() => _FloatingPlayerViewState();
}

class _FloatingPlayerViewState extends State<FloatingPlayerView> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final item = s.player.current.value;
    return Material(
      color: Colors.black,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onPanStart: (_) => AppWindow.startDrag(),
          onDoubleTap: () => expandPip(s),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: s.player.video,
                controls: NoVideoControls,
                fill: Colors.black,
                subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
              ),
              AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: _PipControls(
                  title: _title(s, item),
                  onExpand: () => expandPip(s),
                  onClose: s.pip.close,
                  onDock: s.pip.unfloat,
                ),
              ),
              if (item != null && !item.isLive)
                Positioned(left: 0, right: 0, bottom: 0, child: _PipProgress(player: s.player)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipControls extends StatelessWidget {
  const _PipControls({required this.title, required this.onExpand, required this.onClose, this.onFloat, this.onDock});
  final String title;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  /// Mini-player → floating window (Windows).
  final VoidCallback? onFloat;

  /// Floating window → back into the app as a mini-player.
  final VoidCallback? onDock;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // Semantics, not Tooltip: the mini-player is drawn above the navigator,
    // outside any Overlay.
    Widget button(IconData icon, String label, VoidCallback? onTap, {double size = 34, double iconSize = 16}) =>
        Semantics(
          button: true,
          label: label,
          child: IconButton(
            onPressed: onTap,
            iconSize: iconSize,
            style:
                IconButton.styleFrom(
                  foregroundColor: AppColors.text,
                  fixedSize: Size(size, size),
                  minimumSize: Size(size, size),
                  shape: const CircleBorder(),
                ).copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.hovered) ? const Color(0xE60D0C0B) : const Color(0x990D0C0B),
                  ),
                ),
            icon: Icon(icon),
          ),
        );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xBF000000)],
          stops: [0, 0.4, 0.6, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 10,
            right: 10,
            child: Row(
              children: [
                if (onFloat != null) ...[
                  button(Icons.open_in_new_rounded, 'Fenêtre flottante', onFloat),
                  const SizedBox(width: 6),
                ],
                if (onDock != null) ...[
                  button(Icons.picture_in_picture_alt_rounded, "Revenir dans l'app", onDock),
                  const SizedBox(width: 6),
                ],
                button(Icons.open_in_full_rounded, 'Agrandir', onExpand),
                const SizedBox(width: 6),
                button(Icons.close_rounded, 'Fermer', onClose),
              ],
            ),
          ),
          Center(
            child: StreamBuilder<bool>(
              stream: s.player.player.stream.playing,
              initialData: s.player.player.state.playing,
              builder: (context, snap) => button(
                snap.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                snap.data == true ? 'Pause' : 'Lecture',
                s.player.player.playOrPause,
                size: 56,
                iconSize: 26,
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin progress line of a film or episode.
class _PipProgress extends StatelessWidget {
  const _PipProgress({required this.player});
  final PlayerService player;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: player.player.stream.position,
    builder: (context, snap) {
      final dur = player.player.state.duration.inMilliseconds;
      final pos = (snap.data ?? player.player.state.position).inMilliseconds;
      return ProgressLine(dur <= 0 ? 0 : pos / dur, height: 3, track: const Color(0x33FFFFFF));
    },
  );
}
