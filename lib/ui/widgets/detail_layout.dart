import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'common.dart';
import 'net_image.dart';

/// Shared layout of the movie / series pages: the image across the whole
/// width fading into the background, the title in poster capitals and the
/// actions over it, then the synopsis and credits in two columns.
class DetailLayout extends StatelessWidget {
  const DetailLayout({
    super.key,
    required this.title,
    required this.meta,
    required this.actions,
    this.backdrop,
    this.poster,
    this.rating,
    this.loading = false,
    this.progress,
    this.progressLabel,
    this.breadcrumb,
    this.tags = const [],
    this.fields = const [],
    this.children = const [],
    this.bottom,
  });

  final String title;
  final String? backdrop;
  final String? poster;
  final double? rating;
  final List<String> meta;
  final bool loading;
  final List<Widget> actions;
  final double? progress;
  final String? progressLabel;
  final String? breadcrumb;

  /// Quality tags ("4K", "HDR", "5.1").
  final List<String> tags;

  /// Credits shown on the right of the synopsis ("Distribution", "Genres").
  final List<(String, String)> fields;

  /// Synopsis and notes, left column.
  final List<Widget> children;

  /// Sections below (episodes, related titles).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final heroHeight = (size.height * 0.7).clamp(500.0, 700.0);
    final titleSize = (size.width * 0.08).clamp(64.0, 132.0);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.backspace): () => Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: heroHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _Backdrop(backdrop: backdrop, poster: poster),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xEB111114), Color(0x8C111114), Color(0x00111114)],
                                stops: [0, 0.4, 0.72],
                              ),
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment(0, -0.2),
                                colors: [AppColors.bg, Color(0x00111114)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 48,
                            right: 48,
                            bottom: 36,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 720),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (breadcrumb != null) ...[
                                      Text(
                                        breadcrumb!.toUpperCase(),
                                        style: labelStyle(color: AppColors.textSoft, size: 13),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: posterStyle(
                                        titleSize,
                                        height: 0.86,
                                        shadows: const [
                                          Shadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 4)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (rating != null && rating! > 0) _Rating(rating!),
                                        for (final m in meta.where((m) => m.isNotEmpty))
                                          Text(
                                            m,
                                            style: const TextStyle(
                                              color: AppColors.textSoft,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        for (final t in tags) QualityTag(t),
                                        if (loading)
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 22),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: actions,
                                    ),
                                    if (progress != null) ...[
                                      const SizedBox(height: 18),
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 260,
                                            child: ProgressLine(progress!, track: const Color(0x40FFFFFF)),
                                          ),
                                          const SizedBox(width: 12),
                                          if (progressLabel != null)
                                            Text(
                                              progressLabel!,
                                              style: const TextStyle(fontSize: 14, color: AppColors.textSoft),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (children.isNotEmpty || fields.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
                        child: Wrap(
                          spacing: 64,
                          runSpacing: 24,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                            ),
                            if (fields.isNotEmpty)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 420),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [for (final (k, v) in fields) DetailField(k, v)],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (bottom != null) SliverToBoxAdapter(child: bottom!),
                  const SliverToBoxAdapter(child: SizedBox(height: 64)),
                ],
              ),
              Positioned(
                left: 48,
                top: 28,
                child: Tooltip(
                  message: 'Retour (Échap)',
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Glass(
                        height: 50,
                        padding: EdgeInsets.symmetric(horizontal: 13),
                        child: Icon(Icons.arrow_back_rounded, size: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.backdrop, required this.poster});
  final String? backdrop;
  final String? poster;

  @override
  Widget build(BuildContext context) {
    if (backdrop != null) {
      return NetImage(
        backdrop,
        decodeWidth: 1800,
        alignment: const Alignment(0, -0.35),
        placeholder: const ColoredBox(color: AppColors.surface),
      );
    }
    // No wide image: blurred poster behind, the poster itself on the right.
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Opacity(
            opacity: 0.55,
            child: NetImage(poster, decodeWidth: 300, placeholder: const ColoredBox(color: AppColors.surface)),
          ),
        ),
        Align(
          alignment: const Alignment(0.8, 0.1),
          child: Container(
            width: 300,
            height: 450,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 24))],
            ),
            clipBehavior: Clip.antiAlias,
            child: NetImage(poster, decodeWidth: 300),
          ),
        ),
      ],
    );
  }
}

class _Rating extends StatelessWidget {
  const _Rating(this.rating);
  final double rating;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.star_rounded, size: 18, color: AppColors.accent),
      const SizedBox(width: 4),
      Text(
        rating.toStringAsFixed(1).replaceAll('.', ','),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ],
  );
}

class DetailParagraph extends StatelessWidget {
  const DetailParagraph(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(text, style: const TextStyle(fontSize: 18, height: 1.6, color: AppColors.textSoft)),
  );
}

class DetailField extends StatelessWidget {
  const DetailField(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: AppColors.textSoft),
          ),
        ),
      ],
    ),
  );
}

/// Section title + content.
class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(48, 44, 48, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: displayStyle(26))),
            ?trailing,
          ],
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );
}

/// Small info card ("AUDIO", "VIDÉO").
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.label, required this.lines});
  final String label;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle()),
        const SizedBox(height: 8),
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              lines[i],
              style: TextStyle(
                fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                color: i == 0 ? AppColors.text : AppColors.textSoft,
              ),
            ),
          ),
      ],
    ),
  );
}
