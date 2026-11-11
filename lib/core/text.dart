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

/// "password=…", "play_token=…", "auth_key=…", "wmsAuthSign=…", also
/// percent-encoded ("password%3D…") in an address nested in another one.
/// A word is a whole name or a part of it between "_" / "-": "monkey" is
/// not a key.
final RegExp _secretQuery = RegExp(
  r'((?:^|(?<=[?&;\s"'
  "'"
  r'{,/]|%3F|%26))(?:[A-Za-z0-9]+[_\-])*'
  r'(?:password|passwd|pass|pwd|token|key|apikey|auth|authsign|wmsauthsign|secret|signature|sig|sign|hash|mac|hdnea|hdnts)'
  r'(?:[_\-][A-Za-z0-9]+)*(?:=|%3D))[^&\s"'
  "'"
  r']+?(?=&|%26|\s|"|'
  "'"
  r'|$)',
  caseSensitive: false,
);

/// "/live/user/password/…", and the other places panels put them.
final RegExp _secretPath = RegExp(
  r'(/(?:live|movie|series|timeshift|timeshifts|hls|vod|play|streaming|playlist|xmltv)/[^/\s]+/)[^/\s]+/',
  caseSensitive: false,
);

/// `/hlsr/<token>/<user>/<password>/…`.
final RegExp _secretHlsr = RegExp(r'(/hlsr/)[^/\s]+/[^/\s]+/[^/\s]+/', caseSensitive: false);

/// A token alone in the path: `/play/<token>/ts`, `/hls/<token>/123_45.ts`.
final RegExp _secretToken = RegExp(r'(/(?:play|hls|token|auth)/)[A-Za-z0-9_\-.~%]{8,}(?=/)', caseSensitive: false);

/// "http://user:password@host".
final RegExp _secretUserInfo = RegExp(r'(://[^/\s:@]*:)[^/\s@]+@');

/// "http://host:8080/user/password/1234.ts": the addresses of an M3U
/// playlist exported by an Xtream panel, without "/live/".
final RegExp _secretShortPath = RegExp(
  r'''(https?://[^/\s]+/[^/\s?#]+/)[^/\s?#]+(/\d+(?:\.[A-Za-z0-9]{1,5})?)(?=$|[\s?#"'),;.:|\]])''',
  caseSensitive: false,
);

/// "Authorization: Bearer …" / "Basic …".
final RegExp _secretBearer = RegExp(r'\b((?:Bearer|Basic)\s+)[A-Za-z0-9._~+/=\-]{6,}', caseSensitive: false);

/// A secret in JSON: "password":"…".
final RegExp _secretJson = RegExp(
  r'("(?:[A-Za-z0-9]+_)*(?:password|passwd|pass|pwd|token|key|apikey|secret|auth)"\s*:\s*")(?:[^"\\]|\\.)*"',
  caseSensitive: false,
);

/// Values bound to a failed SQL statement (sqlite3 prints them: a source's
/// address and password, the parental code…), to the end of the message.
final RegExp _sqlParameters = RegExp(r', parameters: .*', dotAll: true);

/// Masks credentials in URLs / messages before they are shown or stored
/// ("…?username=bob&password=***", "/live/bob/***/123.ts",
/// "http://bob:***@host", "http://host/bob/***/123.ts").
String redactCredentials(String text) => text
    .replaceAll(_sqlParameters, ', parameters: ***')
    .replaceAllMapped(_secretQuery, (m) => '${m.group(1)}***')
    .replaceAllMapped(_secretHlsr, (m) => '${m.group(1)}***/')
    .replaceAllMapped(_secretPath, (m) => '${m.group(1)}***/')
    .replaceAllMapped(_secretToken, (m) => '${m.group(1)}***')
    .replaceAllMapped(_secretUserInfo, (m) => '${m.group(1)}***@')
    .replaceAllMapped(_secretShortPath, (m) => '${m.group(1)}***${m.group(2)}')
    .replaceAllMapped(_secretBearer, (m) => '${m.group(1)}***')
    .replaceAllMapped(_secretJson, (m) => '${m.group(1)}***"');

// "FR: ", "|FR| ", "FR | ", "FR - ", "[FR]", "(FR)". A dash right after
// the letters is part of the name: "BBC-One", "RMC-Sport 1".
final RegExp _countryPrefix = RegExp(
  r'^\s*(\|?[a-z]{2,3}\|?\s*[:|]\s*|\|[a-z]{2,3}\|\s*|[a-z]{2,3}\s+-\s+|\[[a-z]{2,3}\]\s*|\([a-z]{2,3}\)\s*)',
  caseSensitive: false,
);
final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _onlyDigits = RegExp(r'^\d*$');
final RegExp _qualityTokens = RegExp(
  r'\b(uhd|fhd|hd|sd|hq|lq|4k|8k|hevc|h265|h264|1080p?|720p?|2160p?|50fps|60fps|backup|vip|\+1)\b',
  caseSensitive: false,
);

/// Normalizes a channel name for EPG matching:
/// "FR: TF1 HD" -> "tf1", "|FR| France 2 FHD" -> "france2",
/// "Россия 1 HD" -> "россия1". Empty when nothing is left to tell the
/// channel by (no letters, or only a number): such a key would put the
/// guide of one channel on others.
String channelMatchKey(String name) {
  var s = foldText(name.length > 200 ? name.substring(0, 200) : name);
  s = s.replaceFirst(_countryPrefix, '');
  // An opening bracket ends a group too: many unclosed ones made this
  // expression slow (each of them read to the end of the name).
  s = s.replaceAll(RegExp(r'[\[\(][^\]\)\[\(]*[\]\)]'), ' ');
  s = s.replaceAll(_qualityTokens, ' ');
  s = s.replaceAll(_notLetterOrDigit, '');
  return _onlyDigits.hasMatch(s) ? '' : s;
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

/// Extracts a plausible release year from a title like "Dune (2021)" or
/// "Dune - 2021" (not "Blade Runner 2049": too far ahead to be one).
int? yearFromTitle(String title) {
  final m = RegExp(r'[\(\[\s\-](19[2-9]\d|20[0-4]\d)[\)\]]?\s*$').firstMatch(title.trim());
  final y = m == null ? null : int.parse(m.group(1)!);
  return y == null || y > DateTime.now().year + 2 ? null : y;
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

final RegExp _cleanPrefix = RegExp(
  r'^\s*(\|[^|]{1,6}\|\s*|\[[^\]]{1,6}\]\s*|[A-Za-z]{2,3}\s*[:|\-]\s+|[A-Za-z]{2,3}:\s*)',
);
final RegExp _cleanQuality = RegExp(
  r'(?<![\w])(uhd|fhd|hd|sd|hq|lq|4k|8k|hevc|h\.?26[45]|1080[pi]?|720p?|2160p?|50fps|60fps|backup|vip|raw)(?![\w])',
  caseSensitive: false,
);
final RegExp _superscripts = RegExp('[ᴬ-ᵡ⁰-⁹ⁱ-ⁿ]+');

/// Channel name without country prefix, quality and decorations:
/// "|FR| TF1 FHD ★" → "TF1", "FR: FRANCE 2 HD" → "France 2".
String cleanChannelName(String name) {
  var s = name.replaceFirst(_cleanPrefix, '');
  s = s.replaceAll(_superscripts, ' ');
  // Short bracketed tags: "(FR)", "[HD]", "(1080p)".
  s = s.replaceAll(RegExp(r'[\[\(][^\]\)]{0,8}[\]\)]'), ' ');
  s = s.replaceAll(_cleanQuality, ' ');
  // Symbols (stars, dots, emoji…) but not letters, digits and + & ' ! . -
  s = s.replaceAll(RegExp(r"[^\p{L}\p{N}\s+&'!.\-]", unicode: true), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'^[\-.|:]+|[\-.|:]+$'), '').trim();
  if (s.isEmpty) return name.trim();
  // All capitals ("FRANCE 2"): words of 4 letters or more with a vowel get a
  // capital initial only; acronyms (TF1, BFMTV, LCI) stay as they are.
  if (s == s.toUpperCase() && s != s.toLowerCase()) {
    s = s
        .split(' ')
        .map((w) {
          final letters = w.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
          if (letters.length < 4 || !RegExp('[AEIOUYÀÂÉÈÊËÎÏÔÛÙÜ]').hasMatch(letters)) return w;
          return w[0] + w.substring(1).toLowerCase();
        })
        .join(' ');
  }
  return s;
}

/// Quality of a channel stream from its name ("4K", "FHD", "HD", "SD").
String? channelQuality(String name) {
  final q = qualityOf(name);
  if (q != null) return q;
  if (RegExp('ᴴᴰ').hasMatch(name)) return 'HD';
  if (RegExp(r'(?<![\w])sd(?![\w])', caseSensitive: false).hasMatch(name)) return 'SD';
  return null;
}

/// Rank of a quality, best first when sorted descending.
int qualityRank(String? q) => switch (q) {
  '4K' => 4,
  'FHD' => 3,
  'HD' => 2,
  'SD' => 0,
  _ => 1,
};
