/// Fast streaming XMLTV parser.
///
/// XMLTV guides are often 50–300 MB. A generic DOM/event XML parser is slow
/// for that, so this scanner only looks for `<channel>` and `<programme>`
/// blocks and extracts the few fields we need.
library;

typedef ProgrammeCallback = void Function(
    String channel, int start, int stop, String title, String? description);
typedef ChannelCallback = void Function(String id, List<String> displayNames);

class XmltvParser {
  XmltvParser({required this.onProgramme, required this.onChannel, this.preferredLang = 'fr'});

  final ProgrammeCallback onProgramme;
  final ChannelCallback onChannel;
  final String preferredLang;

  String _buf = '';

  void add(String chunk) {
    _buf = _buf.isEmpty ? chunk : _buf + chunk;
    _process();
  }

  void close() {
    _process();
    _buf = '';
  }

  void _process() {
    var pos = 0;
    final s = _buf;
    // Next occurrence of each tag. A tag that is absent from the buffer is not
    // searched again (re-scanning the whole buffer for "<channel" after every
    // programme made parsing quadratic on large guides).
    var p = s.indexOf('<programme');
    var c = s.indexOf('<channel');
    while (true) {
      if (p >= 0 && p < pos) p = s.indexOf('<programme', pos);
      if (c >= 0 && c < pos) c = s.indexOf('<channel', pos);
      int start;
      bool isProgramme;
      if (p < 0 && c < 0) {
        // Keep a small tail in case a tag name is split between chunks.
        final keep = s.length - pos > 16 ? s.length - 16 : pos;
        _buf = s.substring(keep);
        return;
      } else if (p >= 0 && (c < 0 || p < c)) {
        start = p;
        isProgramme = true;
      } else {
        start = c;
        isProgramme = false;
      }
      final closeTag = isProgramme ? '</programme>' : '</channel>';
      final openEnd = s.indexOf('>', start);
      if (openEnd < 0) {
        _buf = s.substring(start);
        return;
      }
      // Self-closing element: nothing useful inside.
      if (s.codeUnitAt(openEnd - 1) == 0x2F /* / */) {
        pos = openEnd + 1;
        continue;
      }
      final end = s.indexOf(closeTag, openEnd);
      if (end < 0) {
        _buf = s.substring(start);
        return;
      }
      final openTag = s.substring(start, openEnd);
      final inner = s.substring(openEnd + 1, end);
      if (isProgramme) {
        _handleProgramme(openTag, inner);
      } else {
        _handleChannel(openTag, inner);
      }
      pos = end + closeTag.length;
    }
  }

  void _handleProgramme(String openTag, String inner) {
    final attrs = _attributes(openTag);
    final channel = attrs['channel'];
    final start = parseXmltvTime(attrs['start']);
    final stop = parseXmltvTime(attrs['stop']);
    if (channel == null || start == null) return;
    final title = _pickText(inner, 'title');
    if (title == null) return;
    final desc = _pickText(inner, 'desc');
    onProgramme(decodeEntities(channel), start, stop ?? start + 3600, title, desc);
  }

  void _handleChannel(String openTag, String inner) {
    final id = _attributes(openTag)['id'];
    if (id == null) return;
    final names = _allTexts(inner, 'display-name').map((e) => e.text).toList();
    onChannel(decodeEntities(id), names);
  }

  String? _pickText(String inner, String tag) {
    final all = _allTexts(inner, tag);
    if (all.isEmpty) return null;
    for (final t in all) {
      if (t.lang != null && t.lang!.toLowerCase().startsWith(preferredLang)) return t.text;
    }
    return all.first.text;
  }

  static final _attrRe = RegExp(r'''([\w\-:]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');

  static Map<String, String> _attributes(String tag) {
    final out = <String, String>{};
    for (final m in _attrRe.allMatches(tag)) {
      out[m.group(1)!] = m.group(2) ?? m.group(3) ?? '';
    }
    return out;
  }

  static List<_Text> _allTexts(String inner, String tag) {
    final out = <_Text>[];
    var pos = 0;
    final open = '<$tag';
    final close = '</$tag>';
    while (true) {
      final s = inner.indexOf(open, pos);
      if (s < 0) break;
      final after = s + open.length;
      if (after < inner.length) {
        final ch = inner.codeUnitAt(after);
        // Make sure we matched the full tag name (e.g. not <title-extra>).
        if (ch != 0x3E && ch != 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D && ch != 0x2F) {
          pos = after;
          continue;
        }
      }
      final gt = inner.indexOf('>', s);
      if (gt < 0) break;
      if (inner.codeUnitAt(gt - 1) == 0x2F) {
        pos = gt + 1;
        continue;
      }
      final e = inner.indexOf(close, gt);
      if (e < 0) break;
      final lang = _attributes(inner.substring(s, gt))['lang'];
      final text = _decodeContent(inner.substring(gt + 1, e)).trim();
      if (text.isNotEmpty) out.add(_Text(text, lang));
      pos = e + close.length;
    }
    return out;
  }

  static String _decodeContent(String raw) {
    if (raw.contains('<![CDATA[')) {
      final b = StringBuffer();
      var pos = 0;
      while (true) {
        final s = raw.indexOf('<![CDATA[', pos);
        if (s < 0) {
          b.write(decodeEntities(raw.substring(pos)));
          break;
        }
        b.write(decodeEntities(raw.substring(pos, s)));
        final e = raw.indexOf(']]>', s);
        if (e < 0) {
          b.write(raw.substring(s + 9));
          break;
        }
        b.write(raw.substring(s + 9, e));
        pos = e + 3;
      }
      return b.toString();
    }
    return decodeEntities(raw);
  }
}

class _Text {
  _Text(this.text, this.lang);
  final String text;
  final String? lang;
}

final RegExp _entityRe = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);');

String decodeEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entityRe, (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
      case 'nbsp':
        return ' ';
    }
    final code = e.startsWith('#x')
        ? int.tryParse(e.substring(2), radix: 16)
        : int.tryParse(e.substring(1));
    if (code == null || code > 0x10FFFF) return m.group(0)!;
    return String.fromCharCode(code);
  });
}

/// Parses "20240131203000 +0100" (or without seconds / offset) to epoch seconds.
int? parseXmltvTime(String? v) {
  if (v == null) return null;
  final s = v.trim();
  if (s.length < 12) return null;
  int? n(int a, int b) => b <= s.length ? int.tryParse(s.substring(a, b)) : null;
  final year = n(0, 4), month = n(4, 6), day = n(6, 8), hour = n(8, 10), minute = n(10, 12);
  if (year == null || month == null || day == null || hour == null || minute == null) return null;
  final hasSeconds = s.length >= 14 && int.tryParse(s.substring(12, 14)) != null;
  final second = hasSeconds ? n(12, 14)! : 0;
  var offsetSec = 0;
  final rest = s.substring(hasSeconds ? 14 : 12).trim();
  final m = RegExp(r'^([+-])(\d{2}):?(\d{2})').firstMatch(rest);
  if (m != null) {
    offsetSec = (int.parse(m.group(2)!) * 3600 + int.parse(m.group(3)!) * 60) *
        (m.group(1) == '-' ? -1 : 1);
  }
  final utc = DateTime.utc(year, month, day, hour, minute, second);
  return utc.millisecondsSinceEpoch ~/ 1000 - offsetSec;
}
