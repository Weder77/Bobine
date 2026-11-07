import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'epg_grid.dart';
import 'launch.dart';
import 'live_catalog.dart';
import 'program_actions.dart';
import 'widgets/billboard.dart' show RoundOutlineButton;
import 'widgets/cards.dart';
import 'widgets/chips.dart';
import 'widgets/common.dart';
import 'widgets/rows.dart' show PulseDot;

/// "Guide TV": the selected programme large at the top, days, groups and
/// "Maintenant", then the grid.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, required this.catalog});
  final LiveCatalog catalog;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  late final AppServices _s;
  final _grid = EpgGridController();

  /// Selected programme: row and programme.
  (int, Program)? _sel;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    widget.catalog.addListener(_onCatalog);
    _s.guideFocus.addListener(_onFocusRequest);
    _s.library.addListener(_onLibrary);
    _defaultSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFocusRequest());
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_onCatalog);
    _s.guideFocus.removeListener(_onFocusRequest);
    _s.library.removeListener(_onLibrary);
    super.dispose();
  }

  void _onCatalog() {
    if (!mounted) return;
    setState(_defaultSelection);
  }

  // Reminders and recordings change the blocks.
  void _onLibrary() {
    if (mounted) setState(() {});
  }

  List<ChannelTile> get _tiles => widget.catalog.tiles;

  /// What plays now on the first channel that has a guide.
  void _defaultSelection() {
    final sel = _sel;
    if (sel != null && sel.$1 < _tiles.length) {
      final t = _tiles[sel.$1];
      if (t.variants.any((c) => _s.epg.programs(c, sel.$2.start, sel.$2.stop).any((p) => p.start == sel.$2.start))) {
        return;
      }
    }
    _sel = null;
    for (var i = 0; i < math.min(_tiles.length, 40); i++) {
      final p = _s.epg.now(_tiles[i].channel);
      if (p != null) {
        _sel = (i, p);
        return;
      }
    }
  }

  /// "Voir dans le guide" from the search.
  void _onFocusRequest() {
    final f = _s.guideFocus.value;
    if (f == null || !mounted) return;
    final (channel, program) = f;
    _s.guideFocus.value = null;
    var i = _indexOf(channel);
    if (i < 0 && widget.catalog.cat != 'all') {
      widget.catalog.select('all');
      i = _indexOf(channel);
    }
    if (i < 0) return;
    setState(() => _sel = (i, program));
    WidgetsBinding.instance.addPostFrameCallback((_) => _grid.reveal(i, program));
  }

  int _indexOf(Channel c) => _tiles.indexWhere((t) => t.variants.any((v) => v.extId == c.extId));

  List<Channel> get _playList => widget.catalog.playList;

  void _play(int i) => Launch.channel(context, _tiles[i].channel, _playList);

  @override
  Widget build(BuildContext context) {
    final cat = widget.catalog;
    if (cat.source == null) return const SizedBox.shrink();
    final sel = _sel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sel != null && sel.$1 < _tiles.length) _detail(_tiles[sel.$1], sel.$2) else const SizedBox(height: 40),
        _toolbar(cat),
        Expanded(
          child: _tiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('AUCUNE CHAÎNE', style: posterStyle(36, height: 1).copyWith(letterSpacing: 36 * 0.04)),
                      const SizedBox(height: 12),
                      const Text('Rien dans ce groupe.', style: TextStyle(fontSize: 16, color: AppColors.faint)),
                    ],
                  ),
                )
              : EpgGrid(
                  controller: _grid,
                  channels: _tiles,
                  epgVersion: _s.library.epg,
                  selected: sel == null || sel.$1 >= _tiles.length
                      ? null
                      : (_tiles[sel.$1].channel.extId, sel.$2.start),
                  onPlay: _play,
                  onSelect: (i, p) => setState(() => _sel = (i, p)),
                  onMenu: (i, p, at) => showProgramActions(context, _tiles[i].channel, p, channels: _playList),
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- detail

  Widget _detail(ChannelTile t, Program p) {
    final c = t.channel;
    final now = DateTime.now();
    final live = p.isLiveAt(now);
    final past = !p.stop.isAfter(now);
    final future = !live && !past;
    final replay = canReplay(c, p, now);
    final reminded = _s.repo.hasReminder(c.sourceId, c.extId, p.start);
    final size = MediaQuery.sizeOf(context);
    final titleSize = (size.width * 0.046).clamp(40.0, 68.0);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(p.start.year, p.start.month, p.start.day);
    final status = live
        ? 'En cours · reste ${formatSpan(p.stop.difference(now))}'
        : past
        ? 'Terminé'
        : day == today || p.start.difference(now).inHours < 6
        ? 'Dans ${formatSpan(p.start.difference(now))}'
        : formatDay(p.start);
    final visualW = (size.width * 0.27).clamp(260.0, 380.0);
    final showVisual = size.width >= 980;
    final desc = p.description?.trim();

    final buttons = <Widget>[
      if (live)
        _GuideButton.primary(label: 'Regarder', icon: Icons.play_arrow_rounded, onTap: () => _play(_sel!.$1))
      else if (replay)
        _GuideButton.primary(label: 'Revoir', icon: Icons.replay_rounded, onTap: () => Launch.replay(context, c, p)),
      if (future)
        reminded
            ? _GuideButton.active(
                label: 'Rappel activé',
                icon: Icons.notifications_rounded,
                onTap: () => _toggleReminder(c, p),
              )
            : _GuideButton.primary(
                label: 'Me le rappeler',
                icon: Icons.notifications_none_rounded,
                onTap: () => _toggleReminder(c, p),
              ),
      if (live && replay) _GuideButton.secondary(label: 'Depuis le début', onTap: () => Launch.replay(context, c, p)),
      if (!live) _GuideButton.secondary(label: 'Voir la chaîne', onTap: () => _play(_sel!.$1)),
      RoundOutlineButton(
        icon: Icons.more_horiz_rounded,
        tooltip: 'Plus d’actions',
        size: 48,
        onTap: () => showProgramActions(context, c, p, channels: _playList),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(status, style: monoStyle(14, color: live ? AppColors.accent : AppColors.faint, height: 1)),
      ),
    ];

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChannelLogo(name: t.name, url: c.logo, size: 36),
            Text(t.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1)),
            Text(
              '${formatClock(p.start)} – ${formatClock(p.stop)}',
              style: monoStyle(14, color: AppColors.textSoft, height: 1),
            ),
            if (p.category != null)
              Text(p.category!.toUpperCase(), style: labelStyle(color: AppColors.accent, size: 12)),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) {
            // One line: a long title gets smaller (down to 40 px) before
            // being cut.
            final text = p.title.toUpperCase();
            final tp = TextPainter(
              text: TextSpan(text: text, style: posterStyle(titleSize, height: 0.9)),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout();
            final fitted = tp.width <= box.maxWidth ? titleSize : math.max(40.0, titleSize * box.maxWidth / tp.width);
            tp.dispose();
            return SizedBox(
              height: titleSize * 0.9,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: posterStyle(fitted, height: 0.9),
                ),
              ),
            );
          },
        ),
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.textSoft),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: buttons),
      ],
    );

    return SizedBox(
      // Fixed height: picking another programme does not move the grid.
      height: 24 + 22 + 36 + 14 + titleSize * 0.9 + 14 + 24 + 18 + 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 24, 48, 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: left),
            if (showVisual) ...[
              const SizedBox(width: 40),
              SizedBox(
                width: visualW,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(gradient: AppColors.placeholderGradient(hueOf(p.title))),
                        ),
                        Center(
                          child: ChannelLogo(name: t.name, url: c.logo, size: 72),
                        ),
                        if (live)
                          Positioned(
                            left: 12,
                            top: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const PulseDot(size: 6, color: AppColors.onAccent),
                                  const SizedBox(width: 7),
                                  Text(
                                    'EN DIRECT',
                                    style: monoStyle(
                                      11,
                                      weight: FontWeight.w700,
                                      color: AppColors.onAccent,
                                      height: 1,
                                    ).copyWith(letterSpacing: 11 * 0.08),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleReminder(Channel c, Program p) {
    final on = _s.repo.toggleReminder(c, p);
    _s.library.userChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          on ? 'Rappel le ${formatDay(p.start)} à ${formatClock(p.start)} pour « ${p.title} »' : 'Rappel retiré',
        ),
      ),
    );
  }

  // ------------------------------------------------------------- toolbar

  Widget _toolbar(LiveCatalog cat) {
    final days = _s.settings.epgDays.clamp(1, 7);
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 16),
      child: Row(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _grid.day,
            builder: (context, day, _) => Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderInput),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var d = -1; d < days; d++) ...[
                    if (d > -1) const SizedBox(width: 2),
                    _DayButton(
                      label: d == 0 ? "Aujourd'hui" : formatDayButton(DateTime(now.year, now.month, now.day + d)),
                      selected: d == day,
                      onTap: () => _grid.toDay(d),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ChipStrip(
              gap: 6,
              children: [
                for (final e in cat.entries)
                  GroupChip(
                    label: e.label,
                    locked: e.locked,
                    selected: e.id == cat.cat,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    onTap: () => cat.select(e.id),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: _grid.toNow,
            style:
                FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w700),
                ).copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.hovered) ? AppColors.accentHover : AppColors.accent,
                  ),
                ),
            icon: const Icon(Icons.schedule_rounded, size: 17),
            label: const Text('Maintenant'),
          ),
        ],
      ),
    );
  }
}

class _DayButton extends StatelessWidget {
  const _DayButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: onTap,
    focusRingRadius: 4,
    builder: (context, hover) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.action : (hover ? const Color(0x14FFFFFF) : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1,
            color: selected ? AppColors.onAction : AppColors.textSoft,
          ),
        ),
      ),
    ),
  );
}

/// 48 px buttons of the guide: white, frosted, or vermilion outline
/// ("Rappel activé").
class _GuideButton extends StatelessWidget {
  const _GuideButton._({required this.label, this.icon, required this.onTap, required this.kind});
  const _GuideButton.primary({required String label, required IconData icon, required VoidCallback onTap})
    : this._(label: label, icon: icon, onTap: onTap, kind: 0);
  const _GuideButton.secondary({required String label, required VoidCallback onTap})
    : this._(label: label, onTap: onTap, kind: 1);
  const _GuideButton.active({required String label, required IconData icon, required VoidCallback onTap})
    : this._(label: label, icon: icon, onTap: onTap, kind: 2);
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final int kind;

  @override
  Widget build(BuildContext context) {
    final style =
        switch (kind) {
          0 => FilledButton.styleFrom(
            backgroundColor: AppColors.action,
            foregroundColor: AppColors.onAction,
            padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
          ),
          1 =>
            FilledButton.styleFrom(
              backgroundColor: const Color(0x66787068),
              foregroundColor: AppColors.text,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 16, fontWeight: FontWeight.w600),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.hovered) ? const Color(0x99787068) : const Color(0x66787068),
              ),
            ),
          _ => FilledButton.styleFrom(
            backgroundColor: AppColors.accent.withValues(alpha: 0.12),
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
            side: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
        }.merge(
          FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 16, fontWeight: FontWeight.w700),
          ),
        );
    if (icon == null) return FilledButton(onPressed: onTap, style: style, child: Text(label));
    return FilledButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 20), label: Text(label));
  }
}
