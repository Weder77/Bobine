import 'package:flutter/material.dart';

import '../ui/widgets/net_image.dart';
import 'tv_rows.dart';
import 'tv_theme.dart';

const _lift = Duration(milliseconds: 180);

/// Picture of [item], or the design's soft glow with its title when there
/// is none (or while it loads).
class TvPicture extends StatelessWidget {
  const TvPicture({super.key, required this.url, required this.tintKey, this.label, this.decodeWidth = 480});
  final String? url;
  final String tintKey;
  final String? label;
  final double decodeWidth;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(gradient: tvTint(tintKey)),
      child: label == null
          ? null
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  label!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: tvText(22, weight: FontWeight.w600, color: TvColors.soft),
                ),
              ),
            ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return NetImage(url, decodeWidth: decodeWidth, placeholder: fallback);
  }
}

/// Logo of a channel on its cream square, or its initials.
class TvChannelBadge extends StatelessWidget {
  const TvChannelBadge({super.key, required this.name, this.logo, this.size = 52});
  final String name;
  final String? logo;
  final double size;

  static String mono(String name) {
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.length <= 4 ? words.first : words.first.substring(0, 3);
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * 0.12),
    decoration: BoxDecoration(color: TvColors.cream, borderRadius: BorderRadius.circular(size * 0.2)),
    alignment: Alignment.center,
    child: logo == null || logo!.isEmpty
        ? Text(mono(name), style: tvTitle(size * 0.4, color: TvColors.bg, height: 1))
        : NetImage(
            logo,
            fit: BoxFit.contain,
            decodeWidth: 120,
            placeholder: Text(mono(name), style: tvTitle(size * 0.4, color: TvColors.bg, height: 1)),
          ),
  );
}

/// Thin progress bar (vermilion on a light veil).
class TvBar extends StatelessWidget {
  const TvBar({super.key, required this.value, this.height = 6, this.radius = 3});
  final double value;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      height: height,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0x38FFFFFF))),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: const ColoredBox(color: TvColors.accent, child: SizedBox.expand()),
          ),
        ],
      ),
    ),
  );
}

class _Lifted extends StatelessWidget {
  const _Lifted({
    required this.on,
    required this.width,
    required this.height,
    required this.radius,
    required this.child,
    this.scale = 1.06,
  });
  final bool on;
  final double width;
  final double height;
  final double radius;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: on ? scale : 1,
    duration: _lift,
    curve: Curves.ease,
    child: AnimatedContainer(
      duration: _lift,
      width: width,
      height: height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: tvRing(on)),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
    ),
  );
}

/// "En direct maintenant" / Direct: a channel and its programme.
class TvLiveCard extends StatelessWidget {
  const TvLiveCard({super.key, required this.item, required this.on, this.width = 400, this.height = 225, this.next});
  final TvItem item;
  final bool on;
  final double width;
  final double height;

  /// Next programme, shown when selected (Direct).
  final String? next;

  @override
  Widget build(BuildContext context) => _Lifted(
    on: on,
    width: width,
    height: height,
    radius: 14,
    scale: 1.05,
    child: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: tvTint(item.key))),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xF20D0C0B), Color(0x8C0D0C0B), Color(0x330D0C0B)],
              stops: [0, 0.52, 1],
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          top: 18,
          child: Row(
            children: [
              TvChannelBadge(name: item.channelName ?? item.title, logo: item.image),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.channelName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tvText(24, weight: FontWeight.w600, height: 1.1),
                ),
              ),
              if (item.channelNumber != null) Text('${item.channelNumber}', style: tvMono(24)),
            ],
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tvText(28, weight: FontWeight.w600, height: 1.15),
              ),
              if (item.progress != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TvBar(value: item.progress!)),
                    const SizedBox(width: 14),
                    Text(item.end ?? '', style: tvMono(24)),
                  ],
                ),
              ],
              if (on && next != null) ...[
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    text: 'Ensuite ',
                    children: [
                      TextSpan(
                        text: next,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tvText(24, color: TvColors.muted, height: 1.1),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// "Reprendre": wide picture, title and progress at the bottom.
class TvWideCard extends StatelessWidget {
  const TvWideCard({super.key, required this.item, required this.on, this.width = 400, this.height = 225});
  final TvItem item;
  final bool on;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => _Lifted(
    on: on,
    width: width,
    height: height,
    radius: 14,
    child: Stack(
      fit: StackFit.expand,
      children: [
        TvPicture(url: item.image, tintKey: item.key),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 110,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xEB0D0C0B), Color(0x000D0C0B)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 24,
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tvText(24, weight: FontWeight.w600),
          ),
        ),
        if (item.progress != null)
          Positioned(left: 0, right: 0, bottom: 0, child: TvBar(value: item.progress!, radius: 0)),
      ],
    ),
  );
}

/// Poster 200 × 300.
class TvPosterCard extends StatelessWidget {
  const TvPosterCard({super.key, required this.item, required this.on});
  final TvItem item;
  final bool on;

  @override
  Widget build(BuildContext context) => _Lifted(
    on: on,
    width: 200,
    height: 300,
    radius: 12,
    child: TvPicture(url: item.image, tintKey: item.key, label: item.title, decodeWidth: 300),
  );
}

/// Top 10: the big outlined number behind the poster.
class TvTopCard extends StatelessWidget {
  const TvTopCard({super.key, required this.item, required this.on});
  final TvItem item;
  final bool on;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 310,
    height: 300,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -8,
          bottom: -40,
          child: Text(
            item.number ?? '',
            style: tvTitle(300, weight: FontWeight.w900, height: 1).copyWith(
              letterSpacing: -18,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..color = const Color(0xFF57514B),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: TvPosterCard(item: item, on: on),
        ),
      ],
    ),
  );
}
