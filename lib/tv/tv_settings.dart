import 'package:flutter/material.dart';

import '../core/version.dart';
import '../data/settings.dart';
import '../services.dart';
import '../ui/onboarding_screen.dart';
import '../ui/widgets/pin_dialog.dart';
import 'tv_focus.dart';
import 'tv_rows.dart';
import 'tv_theme.dart';

/// One line of Réglages: ← → change its value, OK runs [ok] (actions).
class TvSetting {
  TvSetting({required this.label, required this.help, required this.value, this.change, this.ok, this.okLabel});

  final String label;
  final String help;
  final String Function() value;

  /// ← (-1) or → (+1).
  final void Function(int delta)? change;

  /// OK on the line (its value changes by +1 when there is no action).
  final void Function()? ok;
  final String? okLabel;
}

/// Next index of a list of [n] values, going round.
int _step(int i, int delta, int n) => ((i + delta) % n + n) % n;

/// A setting stored in [AppSettings] as one of fixed [codes].
TvSetting _choice(
  AppSettings st, {
  required String label,
  required String help,
  required List<(String, String)> options,
  required String Function() read,
  required void Function(String) write,
}) {
  int index() {
    final v = read();
    final i = options.indexWhere((o) => o.$1 == v);
    if (i >= 0) return i;
    // A value typed on a computer ("fr,en"): the option it starts like.
    final j = options.indexWhere((o) => o.$1.isNotEmpty && v.startsWith(o.$1.split(',').first));
    return j < 0 ? 0 : j;
  }

  return TvSetting(
    label: label,
    help: help,
    value: () => options[index()].$2,
    change: (d) => st.update((_) => write(options[_step(index(), d, options.length)].$1)),
  );
}

/// The playback lines of Réglages (only [AppSettings]).
List<TvSetting> tvPlaybackSettings(AppSettings st) => [
  _choice(
    st,
    label: 'Qualité vidéo',
    help: 'Pour une chaîne proposée en plusieurs qualités. Automatique choisit la meilleure.',
    options: const [('Auto', 'Automatique'), ('FHD', 'Full HD'), ('HD', 'HD'), ('SD', 'SD')],
    read: () => st.preferredQuality,
    write: (v) => st.preferredQuality = v,
  ),
  _choice(
    st,
    label: 'Langue audio',
    help: 'Utilisée quand le film ou la chaîne la propose.',
    options: const [('fr,fre,fra', 'Français'), ('', 'Version originale'), ('en,eng', 'Anglais')],
    read: () => st.audioLang,
    write: (v) => st.audioLang = v,
  ),
  _choice(
    st,
    label: 'Sous-titres',
    help: 'Affichés dans cette langue quand le film les propose.',
    options: const [('', 'Désactivés'), ('fr,fre,fra', 'Français'), ('en,eng', 'Anglais')],
    read: () => st.subtitleLang,
    write: (v) => st.subtitleLang = v,
  ),
  TvSetting(
    label: 'Épisode suivant automatique',
    help: 'Lance l’épisode suivant à la fin du générique.',
    value: () => st.autoNextEpisode ? 'Activé' : 'Désactivé',
    change: (_) => st.update((x) => x.autoNextEpisode = !x.autoNextEpisode),
  ),
];

/// Réglages: a few big lines, ← → to change a value; help and the source
/// on the right.
class TvSettingsPage extends StatefulWidget {
  const TvSettingsPage({super.key, required this.setEntry});
  final void Function(String? Function()) setEntry;

  @override
  State<TvSettingsPage> createState() => _TvSettingsPageState();
}

class _TvSettingsPageState extends State<TvSettingsPage> {
  TvFocusController? _c;
  bool _refreshing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = TvFocusScope.maybeOf(context);
    if (c != _c) {
      _c?.removeListener(_changed);
      _c = c?..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _parental(AppServices s) async {
    if (s.settings.parentalEnabled) {
      final pin = await askPin(context, title: 'Contrôle parental', message: 'Tape le code pour le couper.');
      if (pin == null || !mounted) return;
      if (!s.checkParentalPin(pin)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.parentalRefusal)));
        return;
      }
      s.setParentalPin(null);
    } else {
      final pin = await askPin(
        context,
        title: 'Contrôle parental',
        message: 'Choisis un code à 4 chiffres.',
        confirm: true,
      );
      if (pin != null) s.setParentalPin(pin);
    }
    _changed();
  }

  Future<void> _profile(AppServices s, int delta) async {
    final all = s.repo.profiles();
    if (all.length < 2) return;
    final i = all.indexWhere((p) => p.id == s.profile.id);
    final next = all[_step(i < 0 ? 0 : i, delta, all.length)];
    // Leaving a kids profile asks the parental code, as on a computer.
    if (s.profile.kids && !await confirmParent(context, title: 'Changer de profil')) return;
    s.switchProfile(next.id);
  }

  Future<void> _refresh(AppServices s) async {
    final src = s.activeSource;
    if (src == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await s.refresh(src);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _addSource(AppServices s) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => OnboardingScreen(
          onSourceAdded: (id) {
            s.selectSource(id);
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  List<TvSetting> _rows(AppServices s) {
    final sources = s.repo.sources();
    final src = s.activeSource;
    final updated = src?.contentUpdatedAt;
    return [
      TvSetting(
        label: 'Profil',
        help: 'Chaque profil garde ses favoris, sa liste et ses reprises.',
        value: () => s.profile.name,
        change: (d) => _profile(s, d),
      ),
      ...tvPlaybackSettings(s.settings),
      TvSetting(
        label: 'Contrôle parental',
        help: 'Demande le code pour les catégories verrouillées et pour quitter un profil Enfants.',
        value: () => s.settings.parentalEnabled ? 'Activé' : 'Désactivé',
        change: (_) => _parental(s),
      ),
      TvSetting(
        label: 'Source',
        help: '← → passe d’une source à l’autre. OK pour en ajouter une ou te connecter à ton compte Bobine.',
        value: () => src?.name ?? 'Aucune',
        change: sources.length < 2
            ? null
            : (d) {
                final i = sources.indexWhere((x) => x.id == src?.id);
                s.selectSource(sources[_step(i < 0 ? 0 : i, d, sources.length)].id);
              },
        ok: () => _addSource(s),
        okLabel: 'Ajouter une source',
      ),
      TvSetting(
        label: 'Actualiser les chaînes',
        help: 'Recharge la liste des chaînes, des films, des séries et le guide TV depuis ta source.',
        value: () => _refreshing
            ? 'Actualisation…'
            : updated == null
            ? 'Jamais'
            : 'Il y a ${tvDuration(DateTime.now().difference(updated))}',
        ok: () => _refresh(s),
        okLabel: 'Actualiser',
      ),
    ];
  }

  Widget _line(int i, TvSetting r) => TvFocusable(
    id: 'set-$i',
    revealAxes: const {Axis.vertical},
    onOk: r.ok ?? (r.change == null ? null : () => r.change!(1)),
    onSide: r.change == null
        ? null
        : (d) {
            r.change!(d == TvDir.left ? -1 : 1);
            _changed();
            return true;
          },
    builder: (context, on) => AnimatedScale(
      scale: on ? 1.02 : 1,
      duration: const Duration(milliseconds: 150),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 88,
        padding: const EdgeInsets.only(left: 32, right: 28),
        decoration: BoxDecoration(color: on ? Colors.white : TvColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                r.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tvText(30, weight: FontWeight.w600, height: 1, color: on ? TvColors.bg : Colors.white),
              ),
            ),
            Opacity(
              opacity: on && r.change != null ? 1 : 0,
              child: const Icon(Icons.chevron_left_rounded, size: 34, color: TvColors.bg),
            ),
            SizedBox(
              width: 260,
              child: Text(
                r.value(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tvText(28, height: 1, color: on ? TvColors.bg : TvColors.muted),
              ),
            ),
            Opacity(
              opacity: on && r.change != null ? 1 : 0,
              child: const Icon(Icons.chevron_right_rounded, size: 34, color: TvColors.bg),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final rows = _rows(s);
    widget.setEntry(() => 'set-0');
    final id = _c?.id;
    final fi = id != null && id.startsWith('set-') ? int.tryParse(id.substring(4)) : null;
    final help = fi != null && fi < rows.length ? rows[fi] : null;
    final src = s.activeSource;
    final updated = src?.contentUpdatedAt;
    return Stack(
      children: [
        Positioned(left: 96, top: 158, child: Text('RÉGLAGES', style: tvTitle(84))),
        Positioned(
          left: 96,
          top: 280,
          width: 1040,
          bottom: 0,
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 12, bottom: 64),
            clipBehavior: Clip.none,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _line(i, rows[i]),
          ),
        ),
        Positioned(
          left: 1216,
          right: 96,
          top: 300,
          bottom: 64,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((help?.label ?? 'Réglages').toUpperCase(), style: tvKicker()),
              const SizedBox(height: 22),
              Text(
                help?.help ?? 'Choisis un réglage avec ↑ ↓, puis change sa valeur avec ← →.',
                style: tvText(30, weight: FontWeight.w400, height: 1.45, color: TvColors.soft),
              ),
              const SizedBox(height: 28),
              if (help == null)
                const TvKeyHint('↓', 'Entrer dans la liste', color: TvColors.muted)
              else ...[
                if (help.change != null) const TvKeyHint('◀ ▶', 'Changer la valeur', color: TvColors.muted),
                if (help.ok != null) ...[
                  if (help.change != null) const SizedBox(height: 14),
                  TvKeyHint('OK', help.okLabel ?? 'Valider', color: TvColors.muted),
                ],
              ],
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 28),
                decoration: BoxDecoration(color: TvColors.surface, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            src?.name ?? 'Aucune source',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tvText(28, weight: FontWeight.w600, height: 1),
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: src?.lastError == null ? TvColors.ok : TvColors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          src?.lastError == null ? 'Connectée' : 'Erreur',
                          style: tvText(24, height: 1, color: src?.lastError == null ? TvColors.ok : TvColors.accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      updated == null
                          ? 'Chaînes jamais mises à jour'
                          : 'Chaînes mises à jour il y a ${tvDuration(DateTime.now().difference(updated))}',
                      style: tvMono(24, height: 1.3, color: TvColors.faint),
                    ),
                    const SizedBox(height: 16),
                    Text('Bobine $kAppVersion', style: tvMono(24, color: TvColors.dim)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
