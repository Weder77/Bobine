/// Text helpers shared by importers (isolates) and UI.
library;

const Map<String, String> _accentMap = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ę': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ı': 'i',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ś': 's',
  'š': 's',
  'ș': 's',
  'ş': 's',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'ł': 'l',
  'ř': 'r',
  'ť': 't',
  'ț': 't',
  'ď': 'd',
  'ğ': 'g',
  'œ': 'oe',
  'æ': 'ae',
  'ß': 'ss',
};

/// Lower-cases and removes diacritics: "Écran Télé" -> "ecran tele".
String foldText(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_accentMap[ch] ?? ch);
  }
  return buffer.toString();
}

/// Search key stored in DB: folded text, single spaces.
String searchKey(String input) => foldText(input).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Words of a user query, normalised like [searchKey].
List<String> searchWords(String query) => searchKey(query).split(' ').where((w) => w.isNotEmpty).toList();

/// True when every word of the query appears in [key] (any order), the same
/// rule as the global search: "hd tf1" matches "fr: tf1 hd".
bool matchesWords(String key, List<String> words) {
  for (final w in words) {
    if (!key.contains(w)) return false;
  }
  return true;
}

final RegExp _secretQuery = RegExp(r'((?:password|pass|pwd|token)=)[^&\s]+', caseSensitive: false);
final RegExp _secretPath = RegExp(r'(/(?:live|movie|series|timeshift)/[^/\s]+/)[^/\s]+/', caseSensitive: false);

/// Masks credentials in URLs / messages before they are shown or stored
/// ("…?username=bob&password=***", "/live/bob/***/123.ts").
String redactCredentials(String text) => text
    .replaceAllMapped(_secretQuery, (m) => '${m.group(1)}***')
    .replaceAllMapped(_secretPath, (m) => '${m.group(1)}***/');

final RegExp _countryPrefix = RegExp(
  r'^\s*(\|?[a-z]{2,3}\|?\s*[:|\-]\s*|\[[a-z]{2,3}\]\s*|\([a-z]{2,3}\)\s*)',
  caseSensitive: false,
);
final RegExp _qualityTokens = RegExp(
  r'\b(uhd|fhd|hd|sd|hq|lq|4k|8k|hevc|h265|h264|1080p?|720p?|2160p?|50fps|60fps|backup|vip|\+1)\b',
  caseSensitive: false,
);

/// Normalizes a channel name for EPG matching:
/// "FR: TF1 HD" -> "tf1", "|FR| France 2 FHD" -> "france2".
String channelMatchKey(String name) {
  var s = foldText(name);
  s = s.replaceFirst(_countryPrefix, '');
  s = s.replaceAll(RegExp(r'[\[\(][^\]\)]*[\]\)]'), ' ');
  s = s.replaceAll(_qualityTokens, ' ');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return s;
}

/// Fast, stable 64-bit FNV-1a hash rendered as hex (used for ids / file names).
String stableHash(String input) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = hash * prime; // wraps around on 64-bit native ints
  }
  final hi = (hash >> 32) & 0xFFFFFFFF;
  final lo = hash & 0xFFFFFFFF;
  return hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
}

/// Extracts a plausible release year from a title like "Dune (2021)" or "Dune - 2021".
int? yearFromTitle(String title) {
  final m = RegExp(r'[\(\[\s\-](19[2-9]\d|20[0-4]\d)[\)\]]?\s*$').firstMatch(title.trim());
  return m == null ? null : int.parse(m.group(1)!);
}

/// Best effort conversion of loosely-typed JSON values (Xtream APIs mix strings and numbers).
int? asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t) ?? double.tryParse(t)?.round();
  }
  if (v is bool) return v ? 1 : 0;
  return null;
}

double? asDouble(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

String? asString(Object? v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  if (v is List) return v.isEmpty ? null : asString(v.first);
  return v.toString();
}

/// A file name safe on Windows, macOS and Linux (at most 120 characters).
String safeFileName(String name) {
  var s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'[. ]+$'), '');
  if (s.length > 120) s = s.substring(0, 120).trim();
  return s.isEmpty ? 'Bobine' : s;
}

/// Picture quality written in a title ("4K", "FHD", "HD"), or null.
String? qualityOf(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'\b(4k|uhd|2160p?)\b').hasMatch(n)) return '4K';
  if (RegExp(r'\b(fhd|1080p?)\b').hasMatch(n)) return 'FHD';
  if (RegExp(r'\b(hd|720p?)\b').hasMatch(n)) return 'HD';
  return null;
}
