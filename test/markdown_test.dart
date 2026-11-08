import 'package:bobine/ui/widgets/markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub release notes', () {
    const notes =
        "## What's Changed\n"
        '* Bobine 1.2.0 : nouveau nom et nouvelle interface by @Weder77 in https://github.com/Weder77/IpiTivi/pull/4\n'
        '\n\n'
        '**Full Changelog**: https://github.com/Weder77/IpiTivi/compare/v1.1.1...v1.2.0';
    final b = parseMarkdown(notes);
    expect(b.map((x) => x.type), [MdBlockType.heading, MdBlockType.bullet, MdBlockType.paragraph]);
    expect(b[0].level, 2);
    expect(b[0].text, "What's Changed");

    final item = parseInline(b[1].text);
    expect(item.last.text, '#4');
    expect(item.last.url, 'https://github.com/Weder77/IpiTivi/pull/4');

    final changelog = parseInline(b[2].text);
    expect(changelog.first.text, 'Full Changelog');
    expect(changelog.first.styles, {MdStyle.bold});
    expect(changelog.last.text, 'v1.1.1...v1.2.0');
  });

  test('blocks', () {
    final b = parseMarkdown('# Titre\nune ligne\nsuite\n\n- a\n  - b\n1. un\n> cité\n---\n```\ncode\n```');
    expect(b.map((x) => x.type), [
      MdBlockType.heading,
      MdBlockType.paragraph,
      MdBlockType.bullet,
      MdBlockType.bullet,
      MdBlockType.numbered,
      MdBlockType.quote,
      MdBlockType.rule,
      MdBlockType.code,
    ]);
    expect(b[1].text, 'une ligne suite');
    expect(b[3].level, 1);
    expect(b[4].number, 1);
    expect(b[7].text, 'code');
  });

  test('inline styles and links', () {
    final s = parseInline('du **gras**, de l\'*italique*, du `code` et [un lien](https://x.fr) ; snake_case_name');
    expect(s.where((x) => x.styles.contains(MdStyle.bold)).single.text, 'gras');
    expect(s.where((x) => x.styles.contains(MdStyle.italic)).single.text, 'italique');
    expect(s.where((x) => x.styles.contains(MdStyle.code)).single.text, 'code');
    expect(s.where((x) => x.url != null).single.text, 'un lien');
    expect(s.last.text, ' ; snake_case_name');
  });

  testWidgets('renders without markup characters', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MarkdownText("## What's Changed\n* **Nouveau** : interface\n\n---"))),
    );
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining("What's Changed"), findsOneWidget);
  });
}
