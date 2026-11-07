String formatDuration(Duration d, {bool forceHours = false}) {
  final neg = d.isNegative;
  d = d.abs();
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final body = (h > 0 || forceHours) ? '$h:$m:$s' : '$m:$s';
  return neg ? '-$body' : body;
}

String formatClock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String formatRuntime(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return '$m min';
  return '${h}h${m.toString().padLeft(2, '0')}';
}

/// "2 h 30", "1 h 02", "45 min" (the design's way of writing a length).
String formatSpan(Duration d) {
  final total = d.inMinutes < 1 && d.inSeconds > 0 ? 1 : d.inMinutes;
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  return '$h h ${m.toString().padLeft(2, '0')}';
}

const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String formatDay(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return "Aujourd'hui";
  if (diff == 1) return 'Demain';
  if (diff == -1) return 'Hier';
  return '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
}

/// "Sam. 7 nov." (capital initial, as in the design's kickers and guide).
String formatShortDate(DateTime t) {
  final d = _days[t.weekday - 1];
  return '${d[0].toUpperCase()}${d.substring(1)} ${t.day} ${_months[t.month - 1]}';
}

/// "Ven. 6": a day button of the guide.
String formatDayButton(DateTime t) {
  final d = _days[t.weekday - 1];
  return '${d[0].toUpperCase()}${d.substring(1)} ${t.day}';
}

String formatDate(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';

String formatRelative(DateTime? t) {
  if (t == null) return 'jamais';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return "à l'instant";
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

String formatCount(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

String formatBytes(num bytes) {
  String n(double v, int digits) => v.toStringAsFixed(digits).replaceAll('.', ',');
  if (bytes < 1024) return '${bytes.toInt()} o';
  if (bytes < 1024 * 1024) return '${n(bytes / 1024, 0)} Ko';
  if (bytes < 1024 * 1024 * 1024) return '${n(bytes / (1024 * 1024), 1)} Mo';
  return '${n(bytes / (1024 * 1024 * 1024), 2)} Go';
}

/// "5.1", "7.1", "Stéréo"… from a channel count.
String channelLayoutLabel(int n) => switch (n) {
  1 => 'Mono',
  2 => 'Stéréo',
  6 => '5.1',
  8 => '7.1',
  _ => '$n canaux',
};

/// Display name of an audio / subtitle codec ("eac3" → "E-AC3").
String codecLabel(String c) => switch (c.toLowerCase()) {
  'eac3' => 'E-AC3',
  'ac3' => 'AC3',
  'aac' => 'AAC',
  'dts' => 'DTS',
  'truehd' => 'TrueHD',
  'opus' => 'Opus',
  'mp3' => 'MP3',
  'flac' => 'FLAC',
  'subrip' || 'srt' => 'SRT',
  'ass' || 'ssa' => 'ASS',
  'hdmv_pgs_subtitle' || 'pgs' => 'PGS',
  'dvb_subtitle' => 'DVB',
  'mov_text' => 'Texte',
  'webvtt' => 'WebVTT',
  final other => other.toUpperCase(),
};
