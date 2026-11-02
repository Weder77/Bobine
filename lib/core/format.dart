String formatDuration(Duration d, {bool forceHours = false}) {
  final neg = d.isNegative;
  d = d.abs();
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final body = (h > 0 || forceHours) ? '$h:$m:$s' : '$m:$s';
  return neg ? '-$body' : body;
}

String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String formatRuntime(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return '$m min';
  return '${h}h${m.toString().padLeft(2, '0')}';
}

const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];

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
  if (bytes < 1024) return '${bytes.toInt()} o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} Go';
}
