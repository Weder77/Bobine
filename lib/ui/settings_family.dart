import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'profiles.dart';
import 'settings_screen.dart';
import 'widgets/common.dart';
import 'widgets/pin_dialog.dart';

/// Réglages → Profils.
class ProfilesSection extends StatelessWidget {
  const ProfilesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final current = s.profile;
    return SettingsSection(
      title: 'Profils',
      trailing: OutlinedButton.icon(
        onPressed: () => showProfileEditor(context),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Ajouter'),
      ),
      children: [
        for (final p in s.repo.profiles())
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            leading: ProfileAvatar(profile: p, size: 40),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [if (p.id == current.id) 'Profil actuel', if (p.kids) 'Enfant'].join(' · '),
              style: const TextStyle(color: AppColors.muted),
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (p.id != current.id)
                  TextButton(onPressed: () => switchToProfile(context, p), child: const Text('Utiliser')),
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: () => showProfileEditor(context, profile: p),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
        SettingsSwitch(
          title: 'Demander « Qui regarde ? » au démarrage',
          subtitle: "Seulement s'il y a plusieurs profils. Chacun a ses favoris, sa progression et ses rappels.",
          value: s.settings.askProfileAtStart,
          onChanged: (v) => s.settings.update((x) => x.askProfileAtStart = v),
        ),
      ],
    );
  }
}

/// Réglages → Contrôle parental.
class ParentalSection extends StatelessWidget {
  const ParentalSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final on = s.settings.parentalEnabled;
    Future<bool> check() async {
      final pin = await askPin(context, title: 'Code parental', message: 'Tape le code actuel.');
      if (pin == null) return false;
      if (pin != s.settings.parentalPin) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code incorrect.')));
        }
        return false;
      }
      return true;
    }

    return SettingsSection(
      title: 'Contrôle parental',
      children: [
        SettingsOption(
          title: on ? 'Activé' : 'Désactivé',
          subtitle: on
              ? 'Les catégories verrouillées sont cachées partout (accueil, recherche, guide) tant que le code '
                    "n'est pas tapé (menu du profil → « Afficher les catégories protégées »)."
              : 'Choisis un code à 4 chiffres pour cacher les catégories adultes (repérées automatiquement) '
                    'et celles que tu verrouilles.',
          child: Wrap(
            spacing: 8,
            children: [
              if (!on)
                FilledButton(
                  onPressed: () async {
                    final pin = await askPin(
                      context,
                      title: 'Nouveau code parental',
                      message: 'Choisis 4 chiffres.',
                      confirm: true,
                    );
                    if (pin != null) s.setParentalPin(pin);
                  },
                  child: const Text('Activer'),
                )
              else ...[
                OutlinedButton(
                  onPressed: () async {
                    if (!await check() || !context.mounted) return;
                    final pin = await askPin(context, title: 'Nouveau code parental', confirm: true);
                    if (pin != null) s.setParentalPin(pin);
                  },
                  child: const Text('Changer le code'),
                ),
                TextButton(
                  onPressed: () async {
                    if (await check()) s.setParentalPin(null);
                  },
                  child: const Text('Désactiver'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Réglages → Catégories et chaînes.
class CategoriesSection extends StatelessWidget {
  const CategoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final src = s.activeSource;
    if (src == null) return const SizedBox.shrink();
    final hidden = s.repo.hiddenChannels(src.id);
    return SettingsSection(
      title: 'Catégories et chaînes',
      children: [
        SettingsOption(
          title: 'Ranger les catégories',
          subtitle: 'Masquer, verrouiller ou changer l\'ordre des catégories de « ${src.name} ».',
          child: Wrap(
            spacing: 8,
            children: [
              for (final (kind, label) in [
                (ContentKind.live, 'Live TV'),
                (ContentKind.movie, 'Films'),
                (ContentKind.series, 'Séries'),
              ])
                OutlinedButton(onPressed: () => showCategoryManager(context, kind), child: Text(label)),
            ],
          ),
        ),
        if (hidden.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Text(
              'Aucune chaîne masquée. Clic droit sur une chaîne en Live TV → « Masquer ».',
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          for (final c in hidden)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              leading: ChannelLogo(name: c.name, url: c.logo, size: 36),
              title: Text(c.name),
              subtitle: const Text('Masquée', style: TextStyle(color: AppColors.muted)),
              trailing: TextButton(
                onPressed: () {
                  s.repo.setChannelHidden(c.sourceId, c.extId, false);
                  s.visibilityChanged();
                },
                child: const Text('Afficher'),
              ),
            ),
      ],
    );
  }
}

/// Dialog to hide, lock and reorder the categories of one kind.
Future<void> showCategoryManager(BuildContext context, ContentKind kind) => showDialog<void>(
  context: context,
  builder: (_) => _CategoryManager(kind: kind),
);

class _CategoryManager extends StatefulWidget {
  const _CategoryManager({required this.kind});
  final ContentKind kind;

  @override
  State<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends State<_CategoryManager> {
  late final AppServices _s = AppScope.of(context);
  late List<ContentCategory> _list = _load();
  bool _changed = false;

  List<ContentCategory> _load() {
    final src = _s.activeSource;
    return src == null ? [] : _s.repo.categories(src.id, widget.kind, includeHidden: true);
  }

  int get _sourceId => _s.activeSource!.id;

  @override
  void dispose() {
    if (_changed) _s.visibilityChanged();
    super.dispose();
  }

  void _reload() => setState(() {
    _list = _load();
    _changed = true;
  });

  Future<void> _toggleLock(ContentCategory c) async {
    // Unlocking needs the code when parental control is on.
    if (c.locked && _s.settings.parentalEnabled) {
      final pin = await askPin(context, title: 'Code parental', message: 'Tape le code pour déverrouiller.');
      if (pin != _s.settings.parentalPin) return;
    }
    _s.repo.setCategoryLocked(_sourceId, widget.kind, c.extId, !c.locked);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      ContentKind.live => 'Catégories Live TV',
      ContentKind.movie => 'Catégories de films',
      _ => 'Catégories de séries',
    };
    return AlertDialog(
      title: Text(title, style: displayStyle(22)),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            const Text(
              "Glisse pour changer l'ordre. L'œil masque une catégorie, le cadenas la cache derrière le code parental.",
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _list.length,
                onReorderItem: (from, to) {
                  setState(() {
                    final item = _list.removeAt(from);
                    _list.insert(to, item);
                  });
                  _s.repo.setCategoryOrder(_sourceId, widget.kind, [for (final c in _list) c.extId]);
                  _changed = true;
                },
                itemBuilder: (context, i) {
                  final c = _list[i];
                  return ListTile(
                    key: ValueKey(c.extId),
                    contentPadding: const EdgeInsets.only(left: 4, right: 4),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(Icons.drag_indicator_rounded, color: AppColors.muted),
                      ),
                    ),
                    title: Text(
                      c.name,
                      style: TextStyle(color: c.hidden ? AppColors.faint : AppColors.text, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${c.count}', style: const TextStyle(color: AppColors.faint, fontSize: 12)),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: c.hidden ? 'Afficher' : 'Masquer',
                          onPressed: () {
                            _s.repo.setCategoryHidden(_sourceId, widget.kind, c.extId, !c.hidden);
                            _reload();
                          },
                          icon: Icon(c.hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                        IconButton(
                          tooltip: c.locked ? 'Déverrouiller' : 'Verrouiller',
                          onPressed: () => _toggleLock(c),
                          icon: Icon(
                            c.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                            color: c.locked ? AppColors.accent : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _s.repo.resetCategoryOrder(_sourceId, widget.kind);
            _reload();
          },
          child: const Text("Ordre du fournisseur"),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Terminé')),
      ],
    );
  }
}
