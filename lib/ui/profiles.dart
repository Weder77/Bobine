import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'shell.dart';
import 'widgets/common.dart';
import 'widgets/pin_dialog.dart';

/// Colours offered for profiles.
const profileColors = [0xFFFFB547, 0xFF7FA6FF, 0xFFFF8FA8, 0xFF5FD3A1, 0xFFB39DFF, 0xFFFF7A59];

/// Round avatar with the profile's initial.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 40, this.round = false});
  final Profile profile;
  final double size;

  /// Circle (top bar) instead of a rounded square.
  final bool round;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Color(profile.color),
      borderRadius: BorderRadius.circular(round ? size : size * 0.3),
    ),
    child: profile.kids
        ? Icon(Icons.child_care_rounded, size: size * 0.55, color: const Color(0xFF15120A))
        : round
        ? Text(
            profile.initial,
            style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w800, color: const Color(0xFF1B1204)),
          )
        : Text(profile.initial, style: posterStyle(size * 0.62, color: const Color(0xFF15120A), height: 1.05)),
  );
}

/// Switches to [p], asking for the parental code when leaving a kids profile.
Future<bool> switchToProfile(BuildContext context, Profile p) async {
  final s = AppScope.of(context);
  if (p.id == s.profile.id) return true;
  if (s.profile.kids && s.settings.parentalEnabled) {
    final pin = await askPin(context, title: 'Quitter le profil enfant', message: 'Tape le code parental.');
    if (pin == null) return false;
    if (pin != s.settings.parentalPin) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code incorrect.')));
      }
      return false;
    }
  }
  s.switchProfile(p.id);
  // From the top bar or the settings: start again from Accueil, with the
  // new profile's favourites and progress ("Qui regarde ?" has no shell).
  if (context.mounted) ShellNavigation.of(context)?.goTo(ShellTab.home);
  return true;
}

/// "Qui regarde ?": shown at start when there are several profiles.
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key, required this.onChosen});
  final VoidCallback onChosen;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final profiles = s.repo.profiles();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BobineMark(size: 48),
              const SizedBox(height: 28),
              Text('Qui regarde ?', style: displayStyle(44)),
              const SizedBox(height: 40),
              Wrap(
                spacing: 32,
                runSpacing: 32,
                alignment: WrapAlignment.center,
                children: [
                  for (final p in profiles)
                    _ProfileChoice(
                      profile: p,
                      onTap: () async {
                        if (await switchToProfile(context, p)) onChosen();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 44),
              OutlinedButton.icon(
                onPressed: () async {
                  await showProfileEditor(context);
                  (context as Element).markNeedsBuild();
                },
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('Ajouter un profil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileChoice extends StatefulWidget {
  const _ProfileChoice({required this.profile, required this.onTap});
  final Profile profile;
  final VoidCallback onTap;

  @override
  State<_ProfileChoice> createState() => _ProfileChoiceState();
}

class _ProfileChoiceState extends State<_ProfileChoice> {
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: widget.onTap,
      onHover: (v) => setState(() => _focus = v),
      onFocusChange: (v) => setState(() => _focus = v),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: _focus ? AppColors.text : Colors.transparent, width: 3),
              ),
              child: ProfileAvatar(profile: widget.profile, size: 128),
            ),
            const SizedBox(height: 14),
            Text(
              widget.profile.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _focus ? AppColors.text : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creates ([profile] null) or edits a profile.
Future<void> showProfileEditor(BuildContext context, {Profile? profile}) => showDialog<void>(
  context: context,
  builder: (_) => _ProfileEditor(profile: profile),
);

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({this.profile});
  final Profile? profile;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  late int _color = widget.profile?.color ?? profileColors[1];
  late bool _kids = widget.profile?.kids ?? false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final s = AppScope.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (widget.profile == null) {
      s.repo.createProfile(name: name, color: _color, kids: _kids);
    } else {
      s.repo.updateProfile(widget.profile!.id, name: name, color: _color, kids: _kids);
    }
    s.visibilityChanged();
    s.library.userChanged();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = widget.profile;
    final canDelete = p != null && s.repo.profiles().length > 1;
    return AlertDialog(
      title: Text(p == null ? 'Nouveau profil' : 'Modifier le profil', style: displayStyle(22)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Prénom'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 18),
            Text('COULEUR', style: labelStyle()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                for (final c in profileColors)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: _color == c ? AppColors.text : Colors.transparent, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _kids,
              onChanged: (v) => setState(() => _kids = v),
              title: const Text('Profil enfant'),
              subtitle: const Text(
                'Les catégories protégées ne sont jamais affichées, et il faut le code parental pour quitter ce profil.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (canDelete)
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Supprimer « ${p.name} » ?'),
                  content: const Text('Ses favoris, sa progression et ses rappels seront supprimés.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              if (s.profile.id == p.id) s.switchProfile(s.repo.profiles().firstWhere((x) => x.id != p.id).id);
              s.repo.deleteProfile(p.id);
              s.library.userChanged();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Supprimer', style: TextStyle(color: AppColors.live)),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

/// Profile avatar in the top bar: switch profile, unlock protected categories.
class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({super.key, required this.onManage});
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final current = s.profile;
    final profiles = s.repo.profiles();
    final sources = s.repo.sources();
    final active = s.activeSource;
    PopupMenuItem<String> header(String text) => PopupMenuItem<String>(
      enabled: false,
      height: 32,
      child: Text(text, style: labelStyle(color: AppColors.faint, size: 11)),
    );
    Future<void> open(BuildContext anchor) async {
      final box = anchor.findRenderObject() as RenderBox;
      final overlay = Navigator.of(anchor).overlay!.context.findRenderObject() as RenderBox;
      final rect = Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height + 10), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(const Offset(0, 10)), ancestor: overlay),
      );
      final v = await showMenu<String>(
        context: anchor,
        position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
        items: [
          header('PROFIL'),
          for (final p in profiles)
            PopupMenuItem(
              value: 'p:${p.id}',
              child: Row(
                children: [
                  ProfileAvatar(profile: p, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.name,
                      style: TextStyle(fontWeight: p.id == current.id ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                  if (p.id == current.id) const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            ),
          if (s.settings.parentalEnabled && !current.kids) ...[
            const PopupMenuDivider(),
            if (s.parentalUnlocked)
              const PopupMenuItem(value: 'lock', child: Text('Reverrouiller les catégories protégées'))
            else
              const PopupMenuItem(value: 'unlock', child: Text('Afficher les catégories protégées…')),
          ],
          if (sources.isNotEmpty) ...[
            const PopupMenuDivider(),
            header('SOURCE'),
            for (final src in sources)
              PopupMenuItem(
                value: 's:${src.id}',
                child: Row(
                  children: [
                    Icon(
                      src.id == active?.id ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 18,
                      color: src.id == active?.id ? AppColors.accent : AppColors.muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(src.name)),
                  ],
                ),
              ),
          ],
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'manage', child: Text('Gérer les profils et les sources…')),
        ],
      );
      if (v == null || !context.mounted) return;
      if (v.startsWith('p:')) {
        final p = profiles.firstWhere((x) => x.id == int.parse(v.substring(2)));
        await switchToProfile(context, p);
      } else if (v == 'unlock') {
        final pin = await askPin(context, title: 'Catégories protégées', message: 'Tape le code parental.');
        if (pin != null && !s.unlockParental(pin) && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code incorrect.')));
        }
      } else if (v == 'lock') {
        s.lockParental();
      } else if (v.startsWith('s:')) {
        s.selectSource(int.parse(v.substring(2)));
      } else if (v == 'manage') {
        onManage();
      }
    }

    return Tooltip(
      message: active == null ? 'Profil : ${current.name}' : 'Profil : ${current.name} · Source : ${active.name}',
      waitDuration: const Duration(milliseconds: 500),
      child: Builder(
        builder: (anchor) => HoverBuilder(
          onActivate: () => open(anchor),
          builder: (context, hover) => GestureDetector(
            onTap: () => open(anchor),
            // Hover: a white ring around the avatar.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: hover ? AppColors.text : const Color(0x00FFFFFF), width: 2),
              ),
              child: ProfileAvatar(profile: current, size: 42, round: true),
            ),
          ),
        ),
      ),
    );
  }
}
