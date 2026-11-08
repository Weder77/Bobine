import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'settings_family.dart';
import 'settings_maintenance.dart';
import 'settings_recordings.dart';
import 'settings_tmdb.dart';
import 'source_form.dart';
import 'widgets/brand.dart';
import 'widgets/common.dart';

/// Page asked for when the settings open ("Gérer les profils" → 'profils').
final settingsPageRequest = ValueNotifier<String?>(null);

/// Paramètres: pages listed on the left, the chosen one on the right.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _Page {
  const _Page(this.id, this.title, this.lead, this.build);
  final String id;
  final String title;
  final String lead;
  final List<Widget> Function(BuildContext context) build;
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _page = 'sources';
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    settingsPageRequest.addListener(_onRequest);
    _onRequest();
  }

  @override
  void dispose() {
    settingsPageRequest.removeListener(_onRequest);
    _scroll.dispose();
    super.dispose();
  }

  void _onRequest() {
    final r = settingsPageRequest.value;
    if (r == null) return;
    settingsPageRequest.value = null;
    _open(r);
  }

  void _open(String id) {
    if (!mounted) return;
    setState(() => _page = id);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  List<_Page> _pages(AppServices s) {
    final st = s.settings;
    return [
      _Page(
        'profils',
        'Profils',
        'Chaque profil garde ses favoris, sa progression et ses rappels.',
        (context) => [
          const ProfileCards(),
          const SizedBox(height: 30),
          SettingsSection(
            title: 'Profils',
            children: [
              SettingsOption(
                title: 'Au démarrage',
                subtitle: "« Qui regarde ? » n'est proposé que s'il y a plusieurs profils.",
                child: SettingsSegments<bool>(
                  value: st.askProfileAtStart,
                  options: const {true: 'Demander', false: 'Dernier profil'},
                  onChanged: (v) => st.update((x) => x.askProfileAtStart = v),
                ),
              ),
            ],
          ),
        ],
      ),
      _Page(
        'sources',
        'Sources',
        'Les chaînes, films, séries et guides fournis par ton abonnement IPTV.',
        (context) => [
          for (final src in s.repo.sources()) ...[_SourceTile(source: src), const SizedBox(height: 12)],
          DashedAction(
            icon: Icons.add_rounded,
            label: 'Ajouter une source',
            hint: 'lien M3U ou Xtream Codes',
            onTap: () => showSourceDialog(context),
          ),
          const SizedBox(height: 30),
          SettingsSection(
            title: 'Sources',
            children: [
              SettingsOption(
                title: 'Actualisation',
                subtitle: 'Recharge les listes de chaînes, films et séries.',
                child: SettingsSegments<int>(
                  value: st.contentRefreshHours,
                  options: const {12: '12 h', 24: '24 h', 72: '3 jours', 100000: 'Manuelle'},
                  onChanged: (v) => st.update((x) => x.contentRefreshHours = v),
                ),
              ),
              SettingsSwitch(
                title: 'Nettoyer les noms',
                subtitle: '« |FR| TF1 FHD ★ » devient « TF1 ». Préfixes de pays, symboles et mentions de qualité sont masqués.',
                value: st.cleanNames,
                onChanged: (v) => st.update((x) => x.cleanNames = v),
              ),
              SettingsSwitch(
                title: 'Regrouper les qualités',
                subtitle: 'Une seule chaîne pour ses flux FHD, HD et SD. La qualité préférée (Lecture) est lancée.',
                value: st.groupQualities,
                onChanged: (v) => st.update((x) => x.groupQualities = v),
              ),
            ],
          ),
        ],
      ),
      _Page(
        'apparence',
        'Apparence',
        "Le thème de l'application. Le lecteur vidéo reste toujours sombre.",
        (context) => [
          SettingsSection(
            title: 'Apparence',
            children: [
              SettingsOption(
                title: 'Thème',
                subtitle: '« Système » suit le mode clair ou sombre choisi dans Windows, macOS ou Linux.',
                child: SettingsSegments<String>(
                  value: st.themeMode,
                  options: const {'dark': 'Sombre', 'light': 'Clair', 'system': 'Système'},
                  onChanged: (v) => st.update((x) => x.themeMode = v),
                ),
              ),
              SettingsSwitch(
                title: "Défilement de l'en-tête",
                subtitle: "Les visuels en haut de l'accueil, des films et des séries changent tout seuls.",
                value: st.heroAutoplay,
                onChanged: (v) => st.update((x) => x.heroAutoplay = v),
              ),
            ],
          ),
        ],
      ),
      _Page(
        'lecture',
        'Lecture',
        'Ces réglages valent pour tous les profils.',
        (context) => [
          SettingsSection(
            title: 'Lecture',
            children: [
              SettingsOption(
                title: 'Qualité préférée',
                subtitle: "Pour les chaînes proposées en plusieurs qualités. Auto lance la meilleure.",
                child: SettingsSegments<String>(
                  value: st.preferredQuality,
                  options: const {'Auto': 'Auto', 'FHD': 'FHD', 'HD': 'HD', 'SD': 'SD'},
                  onChanged: (v) => st.update((x) => x.preferredQuality = v),
                ),
              ),
              SettingsSwitch(
                title: 'Épisode suivant automatique',
                subtitle: "Lance l'épisode suivant à la fin du précédent.",
                value: st.autoNextEpisode,
                onChanged: (v) => st.update((x) => x.autoNextEpisode = v),
              ),
              SettingsSwitch(
                title: 'Plein écran automatique',
                subtitle: "Passe en plein écran au lancement d'une vidéo.",
                value: st.autoFullscreen,
                onChanged: (v) => st.update((x) => x.autoFullscreen = v),
              ),
              SettingsText(
                title: 'Langues audio préférées',
                subtitle: 'Codes séparés par des virgules (ex. fr,fre,fra,en).',
                value: st.audioLang,
                onChanged: (v) => st.update((x) => x.audioLang = v),
              ),
              SettingsText(
                title: 'Langues de sous-titres préférées',
                subtitle: 'Vide = seulement les sous-titres marqués « par défaut » dans le fichier (ex. forcés).',
                value: st.subtitleLang,
                onChanged: (v) => st.update((x) => x.subtitleLang = v),
              ),
              SettingsOption(
                title: 'Saut avec ← / →',
                subtitle: 'Maj + flèche = saut × 6.',
                child: SettingsSegments<int>(
                  value: st.seekStep,
                  options: const {5: '5 s', 10: '10 s', 15: '15 s', 30: '30 s'},
                  onChanged: (v) => st.update((x) => x.seekStep = v),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Vidéo',
            children: [
              SettingsOption(
                title: 'Décodage vidéo',
                subtitle: 'Passe en logiciel si certaines chaînes restent noires ou si l\'image est corrompue.',
                child: SettingsSegments<bool>(
                  value: st.hardwareDecoding,
                  options: const {true: 'Matériel', false: 'Logiciel'},
                  onChanged: (v) => st.update((x) => x.hardwareDecoding = v),
                ),
              ),
              SettingsOption(
                title: 'Désentrelacement',
                subtitle: "Supprime l'effet de peigne des chaînes TV en 1080i / 576i.",
                child: SettingsSegments<String>(
                  value: st.deinterlace,
                  options: const {'auto': 'Auto', 'yes': 'Toujours', 'no': 'Jamais'},
                  onChanged: (v) => st.update((x) => x.deinterlace = v),
                ),
              ),
            ],
          ),
        ],
      ),
      _Page(
        'cache',
        'Cache',
        'La vidéo gardée en réserve pour que les avances et les retours soient instantanés.',
        (context) => [
          SettingsSection(
            title: 'Cache',
            children: [
              SettingsOption(
                title: "Cache de lecture (vers l'avant)",
                subtitle:
                    "Quantité de vidéo téléchargée à l'avance. Plus il est grand, moins il y a de coupures et plus "
                    'les sauts en avant sont instantanés (1 Go ≈ 15 min de 1080p).',
                child: SettingsSegments<int>(
                  value: st.cacheMb,
                  options: const {256: '256 Mo', 512: '512 Mo', 1024: '1 Go', 2048: '2 Go'},
                  onChanged: (v) => st.update((x) => x.cacheMb = v),
                ),
              ),
              SettingsOption(
                title: 'Cache arrière',
                subtitle:
                    'Garde ce qui a déjà été vu : reculer est instantané, et on peut revenir en arrière sur le direct.',
                child: SettingsSegments<int>(
                  value: st.backCacheMb,
                  options: const {128: '128 Mo', 384: '384 Mo', 768: '768 Mo'},
                  onChanged: (v) => st.update((x) => x.backCacheMb = v),
                ),
              ),
              SettingsSwitch(
                title: 'Cache sur disque',
                subtitle: 'Stocke le cache sur le disque au lieu de la RAM. Recommandé, surtout avec un gros cache.',
                value: st.diskCache,
                onChanged: (v) => st.update((x) => x.diskCache = v),
              ),
            ],
          ),
        ],
      ),
      _Page('guide', 'Guide TV', 'Programmes affichés dans le guide et dans le lecteur.', (context) {
        final src = s.activeSource;
        return [
          SettingsSection(
            title: 'Guide TV',
            children: [
              if (src != null)
                SettingsOption(
                  title: 'Source du guide',
                  subtitle: src.effectiveEpgUrl == null
                      ? 'Aucun guide pour « ${src.name} ».'
                      : 'Mis à jour ${src.epgUpdatedAt == null ? 'jamais' : formatRelative(src.epgUpdatedAt)}.',
                  child: SettingsValue(
                    value: src.effectiveEpgUrl == null
                        ? 'Aucun'
                        : (src.epgUrl == null ? 'XMLTV · fourni par ${src.name}' : 'XMLTV · adresse personnalisée'),
                    action: 'Modifier',
                    onAction: () => showSourceDialog(context, initial: src),
                  ),
                ),
              SettingsOption(
                title: 'Actualiser le guide',
                child: SettingsSegments<int>(
                  value: st.epgRefreshHours,
                  options: const {6: '6 h', 12: '12 h', 24: '24 h', 0: 'Manuelle'},
                  onChanged: (v) => st.update((x) => x.epgRefreshHours = v),
                ),
              ),
              SettingsOption(
                title: 'Jours de programmes',
                subtitle: 'Nombre de jours affichés dans le guide.',
                child: SettingsSegments<int>(
                  value: st.epgDays,
                  options: const {1: '1 j', 3: '3 j', 7: '7 j'},
                  onChanged: (v) => st.update((x) => x.epgDays = v),
                ),
              ),
            ],
          ),
          RemindersSection(),
        ];
      }),
      _Page(
        'parental',
        'Contrôle parental',
        'Le code est commun à tous les profils.',
        (context) => [ParentalSection(), CategoriesSection()],
      ),
      _Page(
        'enregistrements',
        'Enregistrements',
        'Les émissions enregistrées et le dossier où elles sont rangées.',
        (context) => [RecordingsSection()],
      ),
      _Page(
        'tmdb',
        'Fiches TMDB',
        'Résumés, distributions et images en grand grâce à The Movie Database.',
        (context) => [TmdbSection()],
      ),
      _Page(
        'sauvegarde',
        'Sauvegarde',
        'Tes profils, favoris et réglages dans un fichier, et un diagnostic en cas de souci.',
        (context) => [BackupSection()],
      ),
      _Page(
        'raccourcis',
        'Raccourcis',
        'Clavier, télécommande et manette dans le lecteur.',
        (context) => [
          const SettingsSection(title: 'Raccourcis', children: [_Shortcuts()]),
        ],
      ),
      _Page('apropos', 'À propos', 'Bobine, lecteur IPTV.', (context) => [AboutSection()]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.library, s.imports]),
      builder: (context, _) {
        final pages = _pages(s);
        final page = pages.where((p) => p.id == _page).firstOrNull ?? pages[1];
        final width = MediaQuery.sizeOf(context).width;
        // Design: 48 px margins at 1440; on wide screens the block moves
        // towards the centre.
        final side = math.max(48.0, (width - 1600) / 2 + 48);
        final narrow = width < 900;
        final nav = SizedBox(
          width: narrow ? null : 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('PARAMÈTRES', style: posterStyle(44, height: 1)),
              const SizedBox(height: 22),
              for (final p in pages) _NavItem(label: p.title, selected: p.id == page.id, onTap: () => _open(p.id)),
            ],
          ),
        );
        final content = ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(0, narrow ? 0 : 66 + 40, 0, 120),
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: SettingsPageScope(
                  title: page.title,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(page.title.toUpperCase(), style: posterStyle(56, height: 0.9)),
                      const SizedBox(height: 10),
                      Text(page.lead, style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.faint)),
                      const SizedBox(height: 30),
                      ...page.build(context),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        if (narrow) {
          return Padding(
            padding: EdgeInsets.fromLTRB(side, 40, side, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final p in pages)
                        _NavItem(label: p.title, selected: p.id == page.id, onTap: () => _open(p.id)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 40), child: nav),
              const SizedBox(width: 64),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: HoverBuilder(
      onActivate: onTap,
      focusRingRadius: 6,
      builder: (context, hover) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1,
              color: selected || hover ? AppColors.text : AppColors.faint,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Title of the settings page shown: a section with the same title does
/// not repeat it.
class SettingsPageScope extends InheritedWidget {
  const SettingsPageScope({super.key, required this.title, required super.child});
  final String title;

  static String? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsPageScope>()?.title;

  @override
  bool updateShouldNotify(SettingsPageScope old) => old.title != title;
}

/// A group of setting rows separated by thin lines, with its title in small
/// capitals (hidden when it repeats the page title).
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final page = SettingsPageScope.of(context);
    final showTitle = page == null || page.toLowerCase() != title.toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  if (showTitle) Text(title.toUpperCase(), style: labelStyle(color: AppColors.faint, size: 12)),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderSoft)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in children)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
                    ),
                    child: c,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kept for the pages that centre a single column (diagnostic).
const kSettingsWidth = 1040.0;

/// Side padding that centres a [kSettingsWidth] column (48 px at least).
EdgeInsets settingsPadding(BuildContext context, {double top = 24, double bottom = 56}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = ((width - kSettingsWidth) / 2).clamp(48.0, double.infinity);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// One setting: label and explanation on the left, control on the right.
class SettingsOption extends StatelessWidget {
  const SettingsOption({super.key, required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.3)),
              if (subtitle != null) ...[
                const SizedBox(height: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Text(subtitle!, style: TextStyle(color: AppColors.faint, fontSize: 14, height: 1.45)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 32),
        Flexible(
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    ),
  );
}

/// Segmented choice: white pill on the chosen option.
class SettingsSegments<T> extends StatelessWidget {
  const SettingsSegments({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.borderInput),
    ),
    child: Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final e in options.entries)
          HoverBuilder(
            onActivate: () => onChanged(e.key),
            focusRingRadius: 4,
            builder: (context, hover) => Semantics(
              button: true,
              selected: e.key == value,
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: e.key == value
                        ? AppColors.action
                        : (hover ? AppColors.ink.withAlpha(0x14) : Colors.transparent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: e.key == value ? AppColors.onAction : AppColors.textSoft,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// 44 × 26 switch: vermilion when on.
class BobineSwitch extends StatelessWidget {
  const BobineSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: () => onChanged(!value),
    focusRingRadius: 13,
    builder: (context, hover) => Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? AppColors.accent : AppColors.borderStrong,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    ),
  );
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingsOption(
    title: title,
    subtitle: subtitle,
    child: BobineSwitch(value: value, onChanged: onChanged),
  );
}

/// A value in mono and an outlined action ("Modifier").
class SettingsValue extends StatelessWidget {
  const SettingsValue({super.key, this.value, this.action, this.onAction});
  final String? value;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (value != null) Text(value!, style: monoStyle(14, color: AppColors.textSoft, height: 1.2)),
      if (action != null) SmallOutlinedButton(label: action!, onTap: onAction),
    ],
  );
}

/// 36 px outlined button of the settings rows.
class SmallOutlinedButton extends StatelessWidget {
  const SmallOutlinedButton({super.key, required this.label, required this.onTap, this.icon, this.height = 36});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style =
        OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          backgroundColor: Colors.transparent,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 13, fontWeight: FontWeight.w600),
        ).copyWith(
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
                  ? AppColors.text
                  : AppColors.borderStrong,
            ),
          ),
        );
    return icon == null
        ? OutlinedButton(onPressed: onTap, style: style, child: Text(label))
        : OutlinedButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 16), label: Text(label));
  }
}

/// Dashed "add" tile ("Ajouter une source", "Ajouter un profil").
class DashedAction extends StatelessWidget {
  const DashedAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.vertical = false,
  });
  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: onTap,
    focusRingRadius: 12,
    builder: (context, hover) {
      final color = hover ? AppColors.text : AppColors.faint;
      final children = <Widget>[
        Icon(icon, size: vertical ? 32 : 20, color: color),
        SizedBox(width: vertical ? 0 : 12, height: vertical ? 12 : 0),
        Text(
          label,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1, color: color),
        ),
        if (hint != null) ...[
          const SizedBox(width: 12),
          Text(hint!, style: monoStyle(13, color: AppColors.disabled, height: 1)),
        ],
      ];
      return GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedPainter(color: hover ? AppColors.text : AppColors.borderStrong),
          child: Padding(
            padding: vertical
                ? const EdgeInsets.fromLTRB(12, 24, 12, 20)
                : const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: vertical
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: children)
                : Row(children: children),
          ),
        ),
      );
    },
  );
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)).deflate(0.75));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}

class SettingsText extends StatefulWidget {
  const SettingsText({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<SettingsText> createState() => _SettingsTextState();
}

class _SettingsTextState extends State<SettingsText> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsOption(
    title: widget.title,
    subtitle: widget.subtitle,
    child: SizedBox(
      width: 220,
      height: 40,
      child: TextField(
        controller: _c,
        style: const TextStyle(fontSize: 14),
        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onSubmitted: widget.onChanged,
        onTapOutside: (_) {
          if (_c.text != widget.value) widget.onChanged(_c.text.trim());
        },
      ),
    ),
  );
}

/// "line.••••••.tv:8080": the server of a source, partly hidden.
String maskedHost(String url) {
  final uri = Uri.tryParse(url.contains('://') ? url : 'http://$url');
  if (uri == null || uri.host.isEmpty) return '';
  final parts = uri.host.split('.');
  final host = parts.length >= 3
      ? '${parts.first}.••••••.${parts.last}'
      : parts.length == 2
      ? '••••••.${parts.last}'
      : uri.host;
  return uri.hasPort ? '$host:${uri.port}' : host;
}

/// Card of a source: name, server, state, figures and actions.
class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});
  final Source source;

  Future<void> _delete(BuildContext context, AppServices s) async {
    final src = source;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer « ${src.name} » ?'),
        content: const Text('Les chaînes, favoris et la progression de lecture de cette source seront supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) s.deleteSource(src.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final src = source;
    final active = s.settings.activeSourceId == src.id;
    final status = s.imports.status(src.id);
    final info = src.accountInfo;
    final exp = int.tryParse('${info?['exp_date'] ?? ''}');
    final cons = info?['active_cons'];
    final maxCons = info?['max_connections'];
    final figures = <(String, String)>[
      ('Chaînes', formatCount(s.repo.count(src.id, ContentKind.live))),
      ('Films', formatCount(s.repo.count(src.id, ContentKind.movie))),
      ('Séries', formatCount(s.repo.count(src.id, ContentKind.series))),
      if (maxCons != null) ('Connexions', '${cons ?? 0} / $maxCons'),
      if (exp != null && exp > 0) ('Expire le', formatDate(DateTime.fromMillisecondsSinceEpoch(exp * 1000))),
    ];
    final (chip, chipBg, chipInk) = status != null
        ? ('Actualisation…', AppColors.accentTint, AppColors.accent)
        : src.lastError != null
        ? ('Erreur', AppColors.accentTint, AppColors.accent)
        : ('Connectée', AppColors.successTint, AppColors.success);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? AppColors.borderStrong : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                child: const BobineReel(height: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            src.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1),
                          ),
                        ),
                        if (active) ...[
                          const SizedBox(width: 10),
                          Text('ACTIVE', style: labelStyle(color: AppColors.accent, size: 11)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      [
                        src.isXtream ? 'Xtream Codes' : 'Playlist M3U',
                        maskedHost(src.url),
                      ].where((x) => x.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(13, height: 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: chipInk, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      chip,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1, color: chipInk),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border),
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                const gap = 16.0;
                final cols = math.max(1, math.min(figures.length, ((box.maxWidth + gap) / (130 + gap)).floor()));
                final w = (box.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: 16,
                  children: [
                    for (final (k, v) in figures)
                      SizedBox(
                        width: w,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k, style: monoStyle(12, height: 1)),
                            const SizedBox(height: 8),
                            Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (status != null || src.lastError != null) ...[
            const SizedBox(height: 14),
            Text(
              status?.label ?? 'Dernière erreur : ${src.lastError}',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: status != null ? AppColors.textSoft : AppColors.accent,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton(
                onPressed: status != null ? null : () => s.refresh(src).catchError((Object _) {}),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.action,
                  foregroundColor: AppColors.onAction,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                child: Text(status != null ? 'Actualisation…' : 'Actualiser'),
              ),
              const SizedBox(width: 10),
              SmallOutlinedButton(
                label: 'Modifier',
                onTap: () => showSourceDialog(context, initial: src),
              ),
              if (!active) ...[
                const SizedBox(width: 10),
                SmallOutlinedButton(label: 'Utiliser', height: 40, onTap: () => s.selectSource(src.id)),
              ],
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Supprimer la source',
                onPressed: () => _delete(context, s),
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.faint),
              ),
              Expanded(
                child: Text(
                  'Mise à jour ${formatRelative(src.contentUpdatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: monoStyle(13, height: 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  static const _rows = [
    ('Espace / K', 'Lecture / pause'),
    ('← / →', 'Reculer / avancer (Maj = ×6)'),
    ('↑ / ↓', 'Chaîne précédente / suivante (direct), volume (films)'),
    ('Pg↑ / Pg↓', 'Chaîne précédente / suivante'),
    ('0-9', 'Aller au numéro de chaîne'),
    ('C · G', 'Liste des chaînes · mini-guide (direct)'),
    ('E', 'Épisodes de la série'),
    ('F / F11 / double-clic', 'Plein écran'),
    ('M · molette', 'Muet · volume'),
    ('A / S', 'Piste audio / sous-titres suivants'),
    ('R', "Format d'image"),
    ('N', 'Épisode suivant'),
    ('I', 'Statistiques (codec, décodage, cache, débit)'),
    ('P', 'Mini-lecteur (continuer à regarder en naviguant)'),
    ('O', 'Fenêtre flottante par-dessus les autres apps (Windows)'),
    ('Clic droit / touche Menu', 'Actions rapides sur une vignette (favori, saison, vu, bande-annonce…)'),
    (
      'Manette',
      'Croix / stick : se déplacer · A : valider · B : retour · X : pause · Y : actions rapides (plein écran dans le lecteur)',
    ),
    ('Échap', 'Quitter le plein écran / retour'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(
      children: [
        for (final (k, v) in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  child: Text(k, style: monoStyle(13, color: AppColors.accent, height: 1.4)),
                ),
                Expanded(
                  child: Text(v, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSoft)),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
