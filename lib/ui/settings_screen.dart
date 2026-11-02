import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'source_form.dart';
import 'widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.library, s.imports]),
      builder: (context, _) {
        final st = s.settings;
        return ListView(padding: const EdgeInsets.fromLTRB(40, 32, 40, 48), children: [
          const Text('Réglages', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 28),
          _Section(
            title: 'Sources',
            trailing: FilledButton.icon(
              onPressed: () => showSourceDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
            children: [for (final src in s.repo.sources()) _SourceTile(source: src)],
          ),
          _Section(title: 'Lecture', children: [
            _Option(
              title: 'Cache de lecture (vers l\'avant)',
              subtitle: 'Quantité de vidéo téléchargée à l\'avance. Plus il est grand, plus les sauts '
                  'en avant sont instantanés (1 Go ≈ 15 min de 1080p).',
              child: _Segments<int>(
                value: st.cacheMb,
                options: const {256: '256 Mo', 512: '512 Mo', 1024: '1 Go', 2048: '2 Go'},
                onChanged: (v) => st.update((x) => x.cacheMb = v),
              ),
            ),
            _Option(
              title: 'Cache arrière',
              subtitle: 'Garde ce qui a déjà été vu : reculer est instantané (et permet de revenir '
                  'en arrière sur le direct).',
              child: _Segments<int>(
                value: st.backCacheMb,
                options: const {128: '128 Mo', 384: '384 Mo', 768: '768 Mo'},
                onChanged: (v) => st.update((x) => x.backCacheMb = v),
              ),
            ),
            _Switch(
              title: 'Cache sur disque',
              subtitle: 'Stocke le cache sur le disque au lieu de la RAM. Recommandé, surtout avec un gros cache.',
              value: st.diskCache,
              onChanged: (v) => st.update((x) => x.diskCache = v),
            ),
            _Option(
              title: 'Saut avec ← / →',
              subtitle: 'Maj + flèche = saut × 6.',
              child: _Segments<int>(
                value: st.seekStep,
                options: const {5: '5 s', 10: '10 s', 15: '15 s', 30: '30 s'},
                onChanged: (v) => st.update((x) => x.seekStep = v),
              ),
            ),
            _Switch(
              title: 'Décodage matériel',
              subtitle: 'Utilise la carte graphique (D3D11 / NVDEC / VideoToolbox / VA-API) : '
                  'moins de CPU, 4K/HEVC fluides. À désactiver seulement en cas d\'image corrompue.',
              value: st.hardwareDecoding,
              onChanged: (v) => st.update((x) => x.hardwareDecoding = v),
            ),
            _Option(
              title: 'Désentrelacement',
              subtitle: 'Supprime l\'effet de peigne des chaînes TV en 1080i / 576i.',
              child: _Segments<String>(
                value: st.deinterlace,
                options: const {'auto': 'Auto', 'yes': 'Toujours', 'no': 'Jamais'},
                onChanged: (v) => st.update((x) => x.deinterlace = v),
              ),
            ),
            _Text(
              title: 'Langues audio préférées',
              subtitle: 'Codes séparés par des virgules (ex. fr,fre,fra,en).',
              value: st.audioLang,
              onChanged: (v) => st.update((x) => x.audioLang = v),
            ),
            _Text(
              title: 'Langues de sous-titres préférées',
              subtitle: 'Vide = seulement les sous-titres marqués « par défaut » dans le fichier (ex. forcés).',
              value: st.subtitleLang,
              onChanged: (v) => st.update((x) => x.subtitleLang = v),
            ),
            _Switch(
              title: 'Plein écran automatique',
              subtitle: 'Passe en plein écran au lancement d\'une vidéo.',
              value: st.autoFullscreen,
              onChanged: (v) => st.update((x) => x.autoFullscreen = v),
            ),
            _Switch(
              title: 'Épisode suivant automatique',
              value: st.autoNextEpisode,
              onChanged: (v) => st.update((x) => x.autoNextEpisode = v),
            ),
          ]),
          _Section(title: 'Guide TV et mises à jour', children: [
            _Option(
              title: 'Actualiser le guide TV',
              child: _Segments<int>(
                value: st.epgRefreshHours,
                options: const {6: '6 h', 12: '12 h', 24: '24 h', 0: 'Manuel'},
                onChanged: (v) => st.update((x) => x.epgRefreshHours = v),
              ),
            ),
            _Option(
              title: 'Jours de programmes conservés',
              child: _Segments<int>(
                value: st.epgDays,
                options: const {1: '1 j', 3: '3 j', 7: '7 j'},
                onChanged: (v) => st.update((x) => x.epgDays = v),
              ),
            ),
            _Option(
              title: 'Actualiser les chaînes / films / séries',
              child: _Segments<int>(
                value: st.contentRefreshHours,
                options: const {12: '12 h', 24: '24 h', 72: '3 j', 100000: 'Manuel'},
                onChanged: (v) => st.update((x) => x.contentRefreshHours = v),
              ),
            ),
          ]),
          const _Section(title: 'Raccourcis du lecteur', children: [_Shortcuts()]),
          const _Section(title: 'À propos', children: [
            Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Lumen 1.0 — lecteur IPTV basé sur libmpv (FFmpeg) via media_kit.\n'
                'Toutes les données (sources, favoris, progression) sont stockées localement.',
                style: TextStyle(color: AppColors.muted, height: 1.5),
              ),
            ),
          ]),
        ]);
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Row(children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              ?trailing,
            ]),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(indent: 18, endIndent: 18),
                  children[i],
                ],
              ]),
            ),
          ),
        ]),
      );
}

class _Option extends StatelessWidget {
  const _Option({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.35)),
              ],
            ]),
          ),
          const SizedBox(width: 24),
          child,
        ]),
      );
}

class _Segments<T> extends StatelessWidget {
  const _Segments({required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<T>(
        segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
        selected: options.containsKey(value) ? {value} : {},
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        onSelectionChanged: (v) {
          if (v.isNotEmpty) onChanged(v.first);
        },
      );
}

class _Switch extends StatelessWidget {
  const _Switch({required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) =>
      _Option(title: title, subtitle: subtitle, child: Switch(value: value, onChanged: onChanged));
}

class _Text extends StatefulWidget {
  const _Text({required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_Text> createState() => _TextState();
}

class _TextState extends State<_Text> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Option(
        title: widget.title,
        subtitle: widget.subtitle,
        child: SizedBox(
          width: 220,
          child: TextField(
            controller: _c,
            onSubmitted: widget.onChanged,
            onTapOutside: (_) {
              if (_c.text != widget.value) widget.onChanged(_c.text.trim());
            },
          ),
        ),
      );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});
  final Source source;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final src = source;
    final active = s.settings.activeSourceId == src.id;
    final status = s.imports.status(src.id);
    final info = src.accountInfo;
    final exp = info?['exp_date'] as int?;
    final details = <String>[
      src.isXtream ? 'Xtream Codes' : 'Playlist M3U',
      '${formatCount(s.repo.count(src.id, ContentKind.live))} chaînes',
      '${formatCount(s.repo.count(src.id, ContentKind.movie))} films',
      '${formatCount(s.repo.count(src.id, ContentKind.series))} séries',
      'contenu ${formatRelative(src.contentUpdatedAt)}',
      'guide ${src.epgUpdatedAt == null ? (src.effectiveEpgUrl == null ? 'non configuré' : 'jamais') : formatRelative(src.epgUpdatedAt)}',
      if (exp != null && exp > 0) 'expire le ${formatDate(DateTime.fromMillisecondsSinceEpoch(exp * 1000))}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(children: [
        Icon(src.isXtream ? Icons.dns_rounded : Icons.playlist_play_rounded,
            color: active ? AppColors.accent : AppColors.muted),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(src.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (active) ...[
                const SizedBox(width: 8),
                const Pill('Active', color: Color(0x33FFB547), textColor: AppColors.accent),
              ],
            ]),
            const SizedBox(height: 4),
            Text(details.join(' · '), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(status.label, style: const TextStyle(color: AppColors.accent, fontSize: 12.5)),
              )
            else if (src.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Dernière erreur : ${src.lastError}',
                    style: const TextStyle(color: AppColors.live, fontSize: 12.5)),
              ),
          ]),
        ),
        if (!active)
          TextButton(onPressed: () => s.selectSource(src.id), child: const Text('Utiliser')),
        IconButton(
          tooltip: 'Actualiser maintenant',
          onPressed: status != null ? null : () => s.refresh(src).catchError((Object _) {}),
          icon: status != null
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Modifier',
          onPressed: () => showSourceDialog(context, initial: src),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Supprimer',
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Supprimer « ${src.name} » ?'),
                content: const Text('Les chaînes, favoris et la progression de lecture de cette source seront supprimés.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.live),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Supprimer'),
                  ),
                ],
              ),
            );
            if (ok == true) s.deleteSource(src.id);
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ]),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  static const _rows = [
    ('Espace / K', 'Lecture / pause'),
    ('← / →', 'Reculer / avancer (Maj = ×6)'),
    ('↑ / ↓', 'Chaîne précédente / suivante (direct) — volume (films)'),
    ('Pg↑ / Pg↓', 'Chaîne précédente / suivante'),
    ('0-9', 'Aller au numéro de chaîne'),
    ('C', 'Liste des chaînes (direct)'),
    ('F / F11 / double-clic', 'Plein écran'),
    ('M · molette', 'Muet · volume'),
    ('A / S', 'Piste audio / sous-titres suivants'),
    ('R', "Format d'image"),
    ('N', 'Épisode suivant'),
    ('I', 'Statistiques (codec, décodage, cache, débit)'),
    ('Échap', 'Quitter le plein écran / retour'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          for (final (k, v) in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                  width: 200,
                  child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
                ),
                Expanded(child: Text(v, style: const TextStyle(color: Color(0xFFCFD5DE)))),
              ]),
            ),
        ]),
      );
}

