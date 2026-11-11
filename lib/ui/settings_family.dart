import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'profiles.dart';
import 'settings_screen.dart';
import 'widgets/cards.dart';
import 'widgets/common.dart';
import 'widgets/pin_dialog.dart';

/// Réglages → Profils: one card per profile (click: use it, pencil: edit)
/// and a dashed card to add one.
class ProfileCards extends StatelessWidget {
  const ProfileCards({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final current = s.profile;
    return AutoGrid(
      minWidth: 160,
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final p in s.repo.profiles())
          _ProfileCard(
            profile: p,
            active: p.id == current.id,
            onTap: () => p.id == current.id ? showProfileEditor(context, profile: p) : switchToProfile(context, p),
            onEdit: () => showProfileEditor(context, profile: p),
          ),
        if (s.repo.canAddProfile)
          SizedBox(
            height: 200,
            child: DashedAction(
              icon: Icons.add_rounded,
              label: 'Ajouter un profil',
              vertical: true,
              onTap: () => showProfileEditor(context),
            ),
          )
        else
          Container(
            height: 200,
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderFaint),
            ),
            child: Text(
              '${Profile.max} profils au maximum',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.faint),
            ),
          ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.active, required this.onTap, required this.onEdit});
  final Profile profile;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return HoverBuilder(
      onActivate: onTap,
      focusRingRadius: 12,
      builder: (context, hover) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: hover ? AppColors.surface : AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? AppColors.accent : AppColors.border, width: active ? 2 : 1),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProfileAvatar(profile: p, size: 84),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      active ? 'Profil actif' : (p.kids ? 'Profil enfant' : 'Utiliser'),
                      style: monoStyle(12, height: 1),
                    ),
                  ],
                ),
              ),
              if (hover)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Modifier',
                    onPressed: onEdit,
                    iconSize: 18,
                    style: IconButton.styleFrom(foregroundColor: AppColors.textSoft),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
            ],
          ),
        ),
      ),
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
          Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Aucune chaîne masquée. Clic droit sur une chaîne en Live TV → « Masquer ».',
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          for (final c in hidden)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              leading: ChannelLogo(name: c.name, url: c.logo, size: 36),
              title: Text(c.name),
              subtitle: Text('Masquée', style: TextStyle(color: AppColors.muted)),
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
            Text(
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
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(Icons.drag_indicator_rounded, color: AppColors.muted),
                      ),
                    ),
                    title: Text(
                      c.name,
                      style: TextStyle(color: c.hidden ? AppColors.faint : AppColors.text, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${c.count}', style: TextStyle(color: AppColors.faint, fontSize: 12)),
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
