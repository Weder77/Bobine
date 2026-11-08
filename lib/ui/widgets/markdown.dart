import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/open_url.dart';
import '../../core/theme.dart';

// A small Markdown renderer for the release notes shown in the app (titles,
// lists, quotes, separators, code, bold, italic and links). Enough for
// GitHub release notes, without a dependency.

enum MdBlockType { heading, paragraph, bullet, numbered, quote, code, rule }

class MdBlock {
  const MdBlock(this.type, this.text, {this.level = 0, this.number});
  final MdBlockType type;
  final String text;

  /// Heading level (1-6) or list indentation (0, 1, …).
  final int level;

  /// Number of a numbered list item.
  final int? number;

  @override
  String toString() => '$type($level${number == null ? '' : ', $number'}): $text';
}

final _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
final _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
final _quote = RegExp(r'^\s{0,3}>\s?(.*)$');
final _fence = RegExp(r'^\s{0,3}(```|~~~)');

/// Splits [source] into blocks.
List<MdBlock> parseMarkdown(String source) {
  final text = source.replaceAll('\r\n', '\n').replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final blocks = <MdBlock>[];
  final paragraph = <String>[];
  final quote = <String>[];

  void flushParagraph() {
    if (paragraph.isNotEmpty) blocks.add(MdBlock(MdBlockType.paragraph, paragraph.join(' ').trim()));
    paragraph.clear();
  }

  void flushQuote() {
    if (quote.isNotEmpty) blocks.add(MdBlock(MdBlockType.quote, quote.join(' ').trim()));
    quote.clear();
  }

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_fence.hasMatch(line)) {
      flushParagraph();
      flushQuote();
      final code = <String>[];
      for (i++; i < lines.length && !_fence.hasMatch(lines[i]); i++) {
        code.add(lines[i]);
      }
      blocks.add(MdBlock(MdBlockType.code, code.join('\n')));
      continue;
    }
    if (line.trim().isEmpty) {
      flushParagraph();
      flushQuote();
      continue;
    }
    final q = _quote.firstMatch(line);
    if (q != null) {
      flushParagraph();
      quote.add(q.group(1)!);
      continue;
    }
    flushQuote();
    final h = _heading.firstMatch(line);
    if (h != null) {
      flushParagraph();
      blocks.add(MdBlock(MdBlockType.heading, h.group(2)!, level: h.group(1)!.length));
      continue;
    }
    if (_rule.hasMatch(line)) {
      flushParagraph();
      blocks.add(const MdBlock(MdBlockType.rule, ''));
      continue;
    }
    final b = _bullet.firstMatch(line);
    if (b != null) {
      flushParagraph();
      blocks.add(MdBlock(MdBlockType.bullet, b.group(2)!.trim(), level: b.group(1)!.length ~/ 2));
      continue;
    }
    final n = _numbered.firstMatch(line);
    if (n != null) {
      flushParagraph();
      blocks.add(
        MdBlock(
          MdBlockType.numbered,
          n.group(3)!.trim(),
          level: n.group(1)!.length ~/ 2,
          number: int.parse(n.group(2)!),
        ),
      );
      continue;
    }
    // A line under a list item continues it.
    final last = blocks.isEmpty ? null : blocks.last;
    if (paragraph.isEmpty &&
        line.startsWith(' ') &&
        last != null &&
        (last.type == MdBlockType.bullet || last.type == MdBlockType.numbered)) {
      blocks[blocks.length - 1] = MdBlock(
        last.type,
        '${last.text} ${line.trim()}',
        level: last.level,
        number: last.number,
      );
      continue;
    }
    paragraph.add(line.trim());
  }
  flushParagraph();
  flushQuote();
  return blocks;
}

enum MdStyle { bold, italic, code }

/// A run of text with its styles, and the address it opens if any.
class MdSpan {
  const MdSpan(this.text, {this.styles = const {}, this.url});
  final String text;
  final Set<MdStyle> styles;
  final String? url;

  @override
  String toString() => '${styles.map((s) => s.name).join('+')}${url == null ? '' : '<$url>'}"$text"';
}

final _inline = RegExp(
  r'(`+)(.+?)\1' // code
  r'|\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)' // [text](url)
  r'|<(https?://[^>\s]+)>' // <url>
  r'|(https?://[^\s<>()]+[^\s<>().,;:!?])' // bare url
  r'|(\*\*|__)(.+?)\7' // bold
  r'|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])' // *italic*
  r'|(?<![\w_])_(?!\s)(.+?)(?<!\s)_(?![\w_])', // _italic_
);

/// Splits a line into styled runs.
List<MdSpan> parseInline(String text, {Set<MdStyle> styles = const {}}) {
  final out = <MdSpan>[];
  var pos = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > pos) out.add(MdSpan(text.substring(pos, m.start), styles: styles));
    if (m.group(2) != null) {
      out.add(MdSpan(m.group(2)!.trim(), styles: {...styles, MdStyle.code}));
    } else if (m.group(3) != null) {
      for (final s in parseInline(m.group(3)!, styles: styles)) {
        out.add(MdSpan(s.text, styles: s.styles, url: m.group(4)));
      }
    } else if (m.group(5) != null || m.group(6) != null) {
      final url = m.group(5) ?? m.group(6)!;
      out.add(MdSpan(shortLink(url), styles: styles, url: url));
    } else if (m.group(8) != null) {
      out.addAll(parseInline(m.group(8)!, styles: {...styles, MdStyle.bold}));
    } else {
      out.addAll(parseInline(m.group(9) ?? m.group(10)!, styles: {...styles, MdStyle.italic}));
    }
    pos = m.end;
  }
  if (pos < text.length) out.add(MdSpan(text.substring(pos), styles: styles));
  return out;
}

/// GitHub addresses written the way GitHub shows them: a pull request as
/// "#4", a comparison as "v1.1.1...v1.2.0"; other addresses unchanged.
String shortLink(String url) {
  final pr = RegExp(r'^https?://github\.com/[^/]+/[^/]+/(?:pull|issues)/(\d+)/?$').firstMatch(url);
  if (pr != null) return '#${pr.group(1)}';
  final cmp = RegExp(r'^https?://github\.com/[^/]+/[^/]+/compare/([^/\s]+)$').firstMatch(url);
  if (cmp != null) return cmp.group(1)!;
  return url;
}

/// Renders Markdown [data] (release notes) with the app's styles; links
/// open in the browser.
class MarkdownText extends StatefulWidget {
  const MarkdownText(this.data, {super.key, this.style});
  final String data;

  /// Style of the body text.
  final TextStyle? style;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    _clearTaps();
    super.dispose();
  }

  void _clearTaps() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  TapGestureRecognizer _tap(String url) {
    final r = TapGestureRecognizer()..onTap = () => openExternal(url);
    _taps.add(r);
    return r;
  }

  TextSpan _spans(String text, TextStyle base) => TextSpan(
    children: [
      for (final s in parseInline(text))
        TextSpan(
          text: s.text,
          style: base.copyWith(
            fontWeight: s.styles.contains(MdStyle.bold) ? FontWeight.w700 : null,
            fontStyle: s.styles.contains(MdStyle.italic) ? FontStyle.italic : null,
            fontFamily: s.styles.contains(MdStyle.code) ? AppFonts.mono : null,
            fontSize: s.styles.contains(MdStyle.code) ? (base.fontSize ?? 14) * 0.92 : null,
            backgroundColor: s.styles.contains(MdStyle.code) ? AppColors.surface : null,
            color: s.url != null ? AppColors.accent : null,
            decoration: s.url != null ? TextDecoration.underline : null,
            decorationColor: s.url != null ? AppColors.accent.withValues(alpha: 0.5) : null,
          ),
          mouseCursor: s.url != null ? SystemMouseCursors.click : null,
          recognizer: s.url == null ? null : _tap(s.url!),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    _clearTaps();
    final base = DefaultTextStyle.of(context).style
        .merge(widget.style ?? const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSoft));
    final blocks = parseMarkdown(widget.data);
    final children = <Widget>[];
    MdBlockType? previous;
    for (final b in blocks) {
      final gap = switch (b.type) {
        MdBlockType.heading => previous == null ? 0.0 : 16.0,
        MdBlockType.bullet ||
        MdBlockType.numbered => previous == MdBlockType.bullet || previous == MdBlockType.numbered ? 4.0 : 8.0,
        _ => previous == null ? 0.0 : 10.0,
      };
      if (gap > 0) children.add(SizedBox(height: gap));
      children.add(switch (b.type) {
        MdBlockType.heading => Text.rich(
          _spans(
            b.text,
            base.copyWith(
              fontSize: switch (b.level) {
                1 => 20.0,
                2 => 17.0,
                _ => 15.0,
              },
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: AppColors.text,
            ),
          ),
        ),
        MdBlockType.paragraph => Text.rich(_spans(b.text, base)),
        MdBlockType.bullet || MdBlockType.numbered => Padding(
          padding: EdgeInsets.only(left: 4 + b.level * 18.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: b.type == MdBlockType.numbered ? 24 : 16,
                child: Text(
                  b.type == MdBlockType.numbered ? '${b.number}.' : '•',
                  style: base.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(child: Text.rich(_spans(b.text, base))),
            ],
          ),
        ),
        MdBlockType.quote => Container(
          padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
          ),
          child: Text.rich(_spans(b.text, base.copyWith(color: AppColors.faint))),
        ),
        MdBlockType.code => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
          child: Text(
            b.text,
            style: base.copyWith(fontFamily: AppFonts.mono, fontSize: (base.fontSize ?? 14) * 0.9),
          ),
        ),
        MdBlockType.rule => const Divider(height: 1, color: AppColors.borderSoft),
      });
      previous = b.type;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }
}
