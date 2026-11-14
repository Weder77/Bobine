import 'tv_sheet.dart';

/// The tracks of a kind as choices of a sheet, the one in use ([selectedId])
/// checked.
List<TvSheetOption> tvTrackOptions<T>(
  List<T> tracks, {
  required String selectedId,
  required String Function(T track) id,
  required String Function(T track, int index) label,
  required void Function(T track) onPick,
}) => [
  for (final (i, t) in tracks.indexed)
    TvSheetOption(label(t, i), selected: id(t) == selectedId, onPick: () => onPick(t)),
];
