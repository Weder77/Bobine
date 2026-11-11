import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../features/profile_photo.dart';
import '../services.dart';
import 'shell.dart';
import 'widgets/brand.dart';
import 'widgets/common.dart';
import 'widgets/pin_dialog.dart';

/// Colours offered for profiles.
const profileColors = [0xFFFF5A36, 0xFFE8C547, 0xFF6FB7A8, 0xFF7FA6FF, 0xFFC08BF0, 0xFFF3EEE8];

/// Pictures offered for profiles (name → label), stored as `preset:<name>`.
/// The files are `assets/avatars/<name>.png`, drawn by tool/make_avatars.py.
const profileAvatars = {
  'popcorn': 'Pop-corn',
  'clap': 'Clap',
  'chat': 'Chat',
  'renard': 'Renard',
  'robot': 'Robot',
  'panda': 'Panda',
};

/// `profiles.avatar` value of a bundled picture.
String presetAvatar(String name) => 'preset:$name';

/// Asset of a bundled picture; null for anything else, a picture this
/// version does not have included.
String? avatarAsset(String? avatar) {
  if (avatar == null || !avatar.startsWith('preset:')) return null;
  final name = avatar.substring('preset:'.length);
  return profileAvatars.containsKey(name) ? 'assets/avatars/$name.png' : null;
}

/// Longest profile name: with a photo, the profile must still fit in one
/// item of the sync account, or it would stop following the account.
const profileNameMaxLength = 40;

/// Shown when a profile cannot be added.
const profilesFullMessage = '${Profile.max} profils au maximum : supprime un profil pour en créer un autre.';

/// Avatar of a profile (rounded square).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.size = 40, this.round = false});
  final Profile profile;
  final double size;

  /// Kept for older call sites: avatars are rounded squares now.
  final bool round;

  @override
  Widget build(BuildContext context) => AvatarView(
    avatar: profile.avatar,
    color: profile.color,
    initial: profile.initial,
    kids: profile.kids,
    size: size,
  );
}

/// What a profile looks like: its picture or photo, else its initial (a
/// child for a kids profile) on its colour.
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.avatar,
    required this.color,
    required this.initial,
    this.kids = false,
    this.size = 40,
  });

  /// `profiles.avatar`: null, `preset:<name>` or a photo.
  final String? avatar;
  final int color;
  final String initial;
  final bool kids;
  final double size;

  /// Photos already decoded: the same image object keeps Flutter's cache
  /// (a new one at each build would decode it again and flicker).
  static final _photos = <String, MemoryImage>{};

  static ImageProvider? _image(String? avatar) {
    final asset = avatarAsset(avatar);
    if (asset != null) return AssetImage(asset);
    // Least recently used first: a photo used again goes to the end.
    final cached = _photos.remove(avatar);
    if (cached != null) return _photos[avatar!] = cached;
    final bytes = ProfilePhoto.bytesOf(avatar);
    if (bytes == null) return null;
    if (_photos.length >= 2 * Profile.max) _photos.remove(_photos.keys.first);
    return _photos[avatar!] = MemoryImage(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color(color);
    // Dark initial on light colours, light on dark ones.
    final ink = bg.computeLuminance() > 0.35 ? const Color(0xFF1A1503) : const Color(0xFF1A0A05);
    final letter = kids
        ? Icon(Icons.child_care_rounded, size: size * 0.55, color: ink)
        : Text(
            initial,
            style: TextStyle(fontFamily: AppFonts.body, fontSize: size * 0.44, fontWeight: FontWeight.w700, color: ink),
          );
    final image = _image(avatar);
    final square = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: image == null ? Clip.none : Clip.antiAlias,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * (size >= 60 ? 0.19 : 0.23))),
      child: image == null
          ? letter
          : Image(
              image: image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => letter,
            ),
    );
    if (!kids || image == null) return square;
    // A picture hides the child of a kids profile: a badge keeps it in sight.
    final badge = math.max(14.0, size * 0.34);
    return Stack(
      children: [
        square,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: badge,
            height: badge,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cream,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF1A1503), width: math.max(1, badge * 0.07)),
            ),
            child: Icon(Icons.child_care_rounded, size: badge * 0.7, color: const Color(0xFF1A1503)),
          ),
        ),
      ],
    );
  }
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
              const BobineLogo(height: 60),
              const SizedBox(height: 36),
              Text('QUI REGARDE ?', style: posterStyle(64, height: 0.9)),
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
              if (s.repo.canAddProfile)
                OutlinedButton.icon(
                  onPressed: () async {
                    await showProfileEditor(context);
                    if (context.mounted) (context as Element).markNeedsBuild();
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
      mouseCursor: SystemMouseCursors.click,
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

/// Creates ([profile] null) or edits a profile. From a kids profile the
/// parental code is asked first: the editor can turn "Profil enfant" off,
/// delete the profile or create an unrestricted one.
Future<void> showProfileEditor(BuildContext context, {Profile? profile}) async {
  final s = AppScope.of(context);
  if (profile == null && !s.repo.canAddProfile) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(profilesFullMessage)));
    return;
  }
  if (s.profile.kids && s.settings.parentalEnabled) {
    final pin = await askPin(context, title: 'Modifier les profils', message: 'Tape le code parental.');
    if (pin == null || !context.mounted) return;
    if (pin != s.settings.parentalPin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code incorrect.')));
      return;
    }
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ProfileEditor(profile: profile),
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({this.profile});
  final Profile? profile;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  // A longer name (older version, another device) is cut here, in sight,
  // rather than at the first key typed.
  late final _name = TextEditingController(
    text: (widget.profile?.name ?? '').characters.take(profileNameMaxLength).toString(),
  )..addListener(_nameChanged);
  late int _color = widget.profile?.color ?? profileColors[1];
  late bool _kids = widget.profile?.kids ?? false;

  /// Chosen picture: null (initial), `preset:<name>` or [_photo].
  late String? _avatar = widget.profile?.avatar;

  /// Pictures chosen so far: a photo that finishes processing is selected
  /// only if nothing was chosen meanwhile.
  int _choices = 0;

  /// Photo of the profile, kept while the other pictures are tried.
  late String? _photo = ProfilePhoto.isPhoto(widget.profile?.avatar) ? widget.profile!.avatar : null;
  bool _importing = false;

  void _nameChanged() => setState(() {}); // the initial in the preview

  void _choose(String? avatar) => setState(() {
    _avatar = avatar;
    _choices++;
  });

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _importPhoto() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp']),
      ],
    );
    if (file == null || !mounted) return;
    // What is chosen while the photo is processed stays chosen.
    final choices = _choices;
    setState(() => _importing = true);
    String? photo;
    try {
      if (await file.length() <= ProfilePhoto.maxInputBytes) {
        photo = await ProfilePhoto.fromFile(await file.readAsBytes(), background: _color);
      }
    } catch (_) {
      photo = null;
    }
    if (!mounted) return;
    setState(() {
      _importing = false;
      if (photo != null) {
        _photo = photo;
        if (_choices == choices) _avatar = photo;
      }
    });
    if (photo == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Cette image n'a pas pu être lue : essaie une photo JPEG ou PNG.")));
    }
  }

  void _save() {
    if (_importing) return;
    final s = AppScope.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (widget.profile == null) {
      // Profiles may have arrived from the account while the editor was open.
      if (!s.repo.canAddProfile) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(profilesFullMessage)));
        return;
      }
      s.repo.createProfile(name: name, color: _color, kids: _kids, avatar: _avatar);
    } else {
      s.repo.updateProfile(widget.profile!.id, name: name, color: _color, kids: _kids, avatar: _avatar);
    }
    s.visibilityChanged();
    s.library.userChanged();
    Navigator.of(context).pop();
  }

  /// [avatar] as this profile would look; [kids] off for the tiles of
  /// pictures, which would all carry the child badge.
  Widget _avatarOf(String? avatar, double size, {bool? kids}) => AvatarView(
    avatar: avatar,
    color: _color,
    initial: Profile.initialOf(_name.text),
    kids: kids ?? _kids,
    size: size,
  );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = widget.profile;
    final canDelete = p != null && s.repo.profiles().length > 1;
    const tile = 44.0;
    return AlertDialog(
      title: Text(p == null ? 'Nouveau profil' : 'Modifier le profil', style: displayStyle(22)),
      content: SizedBox(
        width: 470,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatarOf(_avatar, 76),
                const SizedBox(width: 20),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Prénom'),
                    inputFormatters: [LengthLimitingTextInputFormatter(profileNameMaxLength)],
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Text('AVATAR', style: labelStyle())),
                TextButton.icon(
                  onPressed: _importing ? null : _importPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(_photo == null ? 'Importer une photo…' : 'Changer de photo…'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _AvatarChoice(
                  tooltip: 'Initiale',
                  selected: _avatar == null,
                  onTap: () => _choose(null),
                  child: _avatarOf(null, tile),
                ),
                for (final e in profileAvatars.entries)
                  _AvatarChoice(
                    tooltip: e.value,
                    selected: _avatar == presetAvatar(e.key),
                    onTap: () => _choose(presetAvatar(e.key)),
                    child: _avatarOf(presetAvatar(e.key), tile, kids: false),
                  ),
                _AvatarChoice(
                  tooltip: _photo == null ? 'Importer une photo' : 'Ta photo',
                  selected: _photo != null && _avatar == _photo,
                  onTap: _importing ? null : (_photo == null ? _importPhoto : () => _choose(_photo)),
                  child: _importing
                      ? const SizedBox(
                          width: tile,
                          height: tile,
                          child: Center(
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        )
                      : _photo == null
                      ? Container(
                          width: tile,
                          height: tile,
                          decoration: BoxDecoration(
                            color: AppColors.surface3,
                            borderRadius: BorderRadius.circular(tile * 0.23),
                          ),
                          child: Icon(Icons.add_photo_alternate_outlined, size: 22, color: AppColors.muted),
                        )
                      : _avatarOf(_photo, tile, kids: false),
                ),
              ],
            ),
            if (_avatar == null) ...[
              const SizedBox(height: 18),
              Text('COULEUR', style: labelStyle()),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [
                  for (final c in profileColors)
                    InkWell(
                      mouseCursor: SystemMouseCursors.click,
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
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _kids,
              onChanged: (v) => setState(() => _kids = v),
              title: const Text('Profil enfant'),
              subtitle: Text(
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
            child: Text('Supprimer', style: TextStyle(color: AppColors.live)),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _importing ? null : _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

/// One of the pictures offered in the profile editor.
class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({required this.tooltip, required this.selected, required this.onTap, required this.child});
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 400),
    child: Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      child: HoverBuilder(
        onActivate: onTap,
        focusRingRadius: 14,
        builder: (context, hover) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.text
                    : hover && onTap != null
                    ? AppColors.borderStrong
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Profile avatar in the top bar: switch profile, unlock protected categories.
class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({super.key, required this.onManage});

  /// Opens the settings, on the profiles page when [profiles].
  final void Function({bool profiles}) onManage;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final current = s.profile;
    final profiles = s.repo.profiles();
    final sources = s.repo.sources();
    final active = s.activeSource;
    PopupMenuItem<String> row(String value, String label) => PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Text(
        label,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textSoft),
      ),
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
        constraints: const BoxConstraints.tightFor(width: 280),
        items: [
          for (final p in profiles)
            PopupMenuItem(
              value: 'p:${p.id}',
              height: 48,
              child: Row(
                children: [
                  ProfileAvatar(profile: p, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                  if (p.id == current.id) Icon(Icons.check_rounded, size: 20, color: AppColors.accent),
                ],
              ),
            ),
          if (sources.length > 1)
            for (final src in sources)
              PopupMenuItem(
                value: 's:${src.id}',
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    const BobineReel(height: 14),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        src.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: src.id == active?.id ? AppColors.text : AppColors.muted,
                          fontWeight: src.id == active?.id ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (src.id == active?.id) Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                  ],
                ),
              ),
          const PopupMenuDivider(height: 13),
          if (s.settings.parentalEnabled && !current.kids)
            s.parentalUnlocked
                ? row('lock', 'Reverrouiller les catégories protégées')
                : row('unlock', 'Afficher les catégories protégées…'),
          row('manage', 'Gérer les profils'),
          row('settings', 'Paramètres'),
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
      } else if (v == 'manage' || v == 'settings') {
        onManage(profiles: v == 'manage');
      }
    }

    return Tooltip(
      message: 'Profil : ${current.name}',
      waitDuration: const Duration(milliseconds: 500),
      child: Builder(
        builder: (anchor) => HoverBuilder(
          onActivate: () => open(anchor),
          focusRingRadius: 8,
          builder: (context, hover) => GestureDetector(
            onTap: () => open(anchor),
            child: AnimatedScale(
              scale: hover ? 1.06 : 1,
              duration: const Duration(milliseconds: 140),
              child: ProfileAvatar(profile: current, size: 34),
            ),
          ),
        ),
      ),
    );
  }
}
