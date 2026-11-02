import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'common.dart';
import 'net_image.dart';

/// Shared layout of the movie / series detail pages: a header card with the
/// backdrop, the poster and the main actions, then free sections below.
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

  /// Synopsis, credits… shown under the actions.
  final List<Widget> children;

  /// Sections below the header card.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.backspace): () => Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 20, 48, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Retour',
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          minimumSize: const Size(48, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
                      ),
                      const SizedBox(width: 16),
                      if (breadcrumb != null)
                        Text(
                          breadcrumb!,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 18, 48, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _Backdrop(backdrop: backdrop, poster: poster),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xF207080B), Color(0xBF07080B), Color(0x3307080B)],
                                stops: [0, 0.5, 1],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(48),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 260,
                                height: 390,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: AppColors.surface3,
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 30)),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: NetImage(
                                  poster,
                                  decodeWidth: 260,
                                  placeholder: const ColoredBox(
                                    color: AppColors.surface3,
                                    child: Icon(Icons.movie_outlined, size: 48, color: AppColors.faint),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 40),
                              Expanded(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 780),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 8),
                                      Text(title, style: displayStyle(60, weight: FontWeight.w800, height: 1.02)),
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 14,
                                        runSpacing: 10,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          if (rating != null && rating! > 0) _RatingChip(rating!),
                                          for (final m in meta.where((m) => m.isNotEmpty))
                                            Text(m, style: const TextStyle(color: AppColors.textSoft, fontSize: 15)),
                                          for (final t in tags) QualityTag(t),
                                          if (loading)
                                            const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 26),
                                      Wrap(spacing: 12, runSpacing: 12, children: actions),
                                      if (progress != null) ...[
                                        const SizedBox(height: 18),
                                        Row(
                                          children: [
                                            SizedBox(width: 320, child: ProgressLine(progress!, height: 5)),
                                            const SizedBox(width: 12),
                                            if (progressLabel != null)
                                              Text(
                                                progressLabel!,
                                                style: const TextStyle(fontSize: 14, color: AppColors.muted),
                                              ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 20),
                                      ...children,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (bottom != null) SliverToBoxAdapter(child: bottom!),
              const SliverToBoxAdapter(child: SizedBox(height: 56)),
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
        decodeWidth: 1400,
        alignment: Alignment.topCenter,
        placeholder: const ColoredBox(color: Color(0xFF16202E)),
      );
    }
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
      child: Opacity(
        opacity: 0.5,
        child: NetImage(poster, decodeWidth: 300, placeholder: const ColoredBox(color: Color(0xFF16202E))),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip(this.rating);
  final double rating;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: AppColors.accent),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1).replaceAll('.', ','),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ],
    ),
  );
}

class DetailParagraph extends StatelessWidget {
  const DetailParagraph(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(text, style: const TextStyle(fontSize: 17, height: 1.6, color: Color(0xFFD5D9E0))),
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
          width: 120,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(child: Text(value, maxLines: 3, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// Section title + content, aligned with the header card.
class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(48, 40, 48, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: displayStyle(24))),
            ?trailing,
          ],
        ),
        const SizedBox(height: 16),
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
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
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
