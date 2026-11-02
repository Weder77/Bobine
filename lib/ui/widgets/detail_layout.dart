import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'common.dart';
import 'net_image.dart';

/// Shared layout of the movie / series detail pages.
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
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final hasBackdrop = backdrop != null;
    return Scaffold(
      body: Stack(children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 560,
          child: Stack(fit: StackFit.expand, children: [
            if (hasBackdrop)
              Opacity(opacity: 0.6, child: NetImage(backdrop, decodeWidth: 1400, alignment: Alignment.topCenter))
            else
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Opacity(opacity: 0.45, child: NetImage(poster, decodeWidth: 300)),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x660A0C11), AppColors.bg],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.bg, Colors.transparent],
                  begin: Alignment.centerLeft,
                  end: Alignment(0.3, 0),
                ),
              ),
            ),
          ]),
        ),
        CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 70, 40, 24),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 240,
                    height: 360,
                    child: NetImage(poster, decodeWidth: 240,
                        placeholder: const ColoredBox(
                          color: AppColors.surface2,
                          child: Icon(Icons.movie_outlined, size: 48, color: AppColors.faint),
                        )),
                  ),
                ),
                const SizedBox(width: 36),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 12),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -0.8, height: 1.1)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (rating != null && rating! > 0) RatingBadge(rating!),
                      for (final m in meta.where((m) => m.isNotEmpty))
                        Text(m, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                      if (loading)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ]),
                    const SizedBox(height: 22),
                    Wrap(spacing: 12, runSpacing: 12, children: actions),
                    if (progress != null) ...[
                      const SizedBox(height: 14),
                      SizedBox(width: 320, child: ProgressLine(progress!, height: 4)),
                    ],
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          if (bottom != null) SliverToBoxAdapter(child: bottom!),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ]),
        Positioned(
          top: 16,
          left: 16,
          child: IconButton.filledTonal(
            tooltip: 'Retour',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
      ]),
    );
  }
}

class DetailParagraph extends StatelessWidget {
  const DetailParagraph(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text, style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFFD3D9E2))),
      );
}

class DetailField extends StatelessWidget {
  const DetailField(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$label  ', style: const TextStyle(color: AppColors.muted)),
          TextSpan(text: value),
        ]), maxLines: 3, overflow: TextOverflow.ellipsis),
      );
}
