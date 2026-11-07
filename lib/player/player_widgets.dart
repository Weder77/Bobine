import 'package:media_kit/media_kit.dart';

import '../core/format.dart';

const Map<String, String> _languages = {
  'fr': 'Français',
  'fre': 'Français',
  'fra': 'Français',
  'en': 'Anglais',
  'eng': 'Anglais',
  'es': 'Espagnol',
  'spa': 'Espagnol',
  'de': 'Allemand',
  'ger': 'Allemand',
  'deu': 'Allemand',
  'it': 'Italien',
  'ita': 'Italien',
  'pt': 'Portugais',
  'por': 'Portugais',
  'ar': 'Arabe',
  'ara': 'Arabe',
  'tr': 'Turc',
  'tur': 'Turc',
  'nl': 'Néerlandais',
  'dut': 'Néerlandais',
  'nld': 'Néerlandais',
  'ja': 'Japonais',
  'jpn': 'Japonais',
  'ko': 'Coréen',
  'kor': 'Coréen',
  'zh': 'Chinois',
  'chi': 'Chinois',
  'zho': 'Chinois',
  'ru': 'Russe',
  'rus': 'Russe',
  'pl': 'Polonais',
  'pol': 'Polonais',
  'und': 'Indéterminée',
  'qaa': 'VO',
  'mul': 'Multiple',
};

String languageName(String? code) {
  if (code == null || code.isEmpty) return '';
  return _languages[code.toLowerCase()] ?? code.toUpperCase();
}

/// Main line of an audio track: "Français (VF)".
String audioTrackTitle(AudioTrack t, int index) {
  final lang = languageName(t.language);
  final title = t.title?.trim();
  if (lang.isNotEmpty && title != null && title.isNotEmpty && title.toLowerCase() != lang.toLowerCase()) {
    return '$lang ($title)';
  }
  if (lang.isNotEmpty) return lang;
  if (title != null && title.isNotEmpty) return title;
  return 'Piste ${index + 1}';
}

/// Second line of an audio track: "E-AC3 · 5.1".
String audioTrackDetail(AudioTrack t) => [
  if (t.codec != null) codecLabel(t.codec!),
  if (t.channelscount != null) channelLayoutLabel(t.channelscount!),
].join(' · ');

String subtitleTrackTitle(SubtitleTrack t, int index) {
  final lang = languageName(t.language);
  final title = t.title?.trim();
  if (lang.isNotEmpty && title != null && title.isNotEmpty && title.toLowerCase() != lang.toLowerCase()) {
    return '$lang ($title)';
  }
  if (lang.isNotEmpty) return lang;
  if (title != null && title.isNotEmpty) return title;
  return 'Sous-titres ${index + 1}';
}

String subtitleTrackDetail(SubtitleTrack t) => t.codec == null ? '' : codecLabel(t.codec!);

/// One-line labels (used by the on-screen messages).
String audioTrackLabel(AudioTrack t, int index) {
  final d = audioTrackDetail(t);
  return d.isEmpty ? audioTrackTitle(t, index) : '${audioTrackTitle(t, index)} · $d';
}

String subtitleTrackLabel(SubtitleTrack t, int index) {
  if (t.id == 'no') return 'Désactivés';
  final d = subtitleTrackDetail(t);
  return d.isEmpty ? subtitleTrackTitle(t, index) : '${subtitleTrackTitle(t, index)} · $d';
}
