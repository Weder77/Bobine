import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services.dart';
import 'common.dart';
import 'net_image.dart';

/// 16:9 channel card: the logo over a blurred copy of itself, the "DIRECT"
/// badge, the time slot and a red progress line; the programme underneath.
class LiveCard extends StatelessWidget {
  const LiveCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.width = 300,
    this.selected = false,
    this.favorite = false,
  });
  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  /// Right click: menu at the given screen position.
  final ValueChanged<Offset>? onContextMenu;
  final double width;
  final bool selected;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = channel;
    final now = s.epg.now(c);
    final next = s.epg.next(c);
    return RepaintBoundary(
      child: HoverBuilder(
        builder: (context, hover) => Semantics(
          button: true,
          label: c.name,
          child: GestureDetector(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onSecondaryTapUp: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
            onLongPressStart: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: focusRing(on: hover || selected, radius: 12),
                      padding: const EdgeInsets.all(2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: AppColors.surface),
                            if (c.logo != null)
                              ImageFiltered(
                                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                                child: Opacity(opacity: 0.45, child: NetImage(c.logo, decodeWidth: 96)),
                              ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x330A0A0C), Color(0xB30A0A0C)],
                                ),
                              ),
                            ),
                            Center(
                              child: ChannelLogo(name: c.name, url: c.logo, size: 76),
                            ),
                            const Positioned(left: 10, top: 10, child: LiveBadge()),
                            if (favorite)
                              const Positioned(
                                right: 10,
                                top: 10,
                                child: Icon(Icons.star_rounded, size: 20, color: AppColors.accent),
                              )
                            else if (c.number != null)
                              Positioned(
                                right: 12,
                                top: 10,
                                child: Text(
                                  '${c.number}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textSoft,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              ),
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (now != null)
                                    Text(
                                      '${formatClock(now.start)} – ${formatClock(now.stop)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSoft,
                                        fontFeatures: tabularFigures,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: ProgressLine(
                                now?.progressAt(DateTime.now()) ?? 0,
                                color: AppColors.live,
                                track: const Color(0x40FFFFFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    now?.title ?? 'Programme non disponible',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: now == null ? AppColors.muted : AppColors.text,
                    ),
                  ),
                  if (next != null)
                    Text(
                      'Ensuite ${formatClock(next.start)} · ${next.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
