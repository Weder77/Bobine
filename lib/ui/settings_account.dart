import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../services.dart';
import '../sync/supabase_api.dart';
import '../sync/sync_service.dart';
import 'widgets/common.dart' show HoverBuilder;
import 'widgets/pin_dialog.dart';

/// Digits of the codes sent by e-mail: Supabase → Authentication → Sign In /
/// Providers → Email → "Email OTP length".
const kEmailCodeLength = 8;

/// Seconds before the confirmation e-mail can be sent again.
const _resendDelay = 60;

const _synced = [
  'Sources et identifiants',
  'Profils',
  'Favoris',
  'Reprises et épisodes vus',
  'Chaînes récentes',
  'Catégories et chaînes masquées',
  'Catégories verrouillées',
  'Rappels',
  'Code parental',
  'Clé TMDB',
  'Réglages de lecture',
];

const _local = ['Cache', 'Décodage vidéo', 'Volume', 'Enregistrements', 'Thème'];

/// Paramètres → Compte: sign in, and the synchronisation between devices.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key, this.sync});

  /// The app's by default.
  final SyncService? sync;

  @override
  Widget build(BuildContext context) {
    final sync = this.sync ?? AppScope.of(context).sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => switch (sync.status) {
        SyncStatus.signedOut => _SignedOut(sync),
        SyncStatus.confirming => _Confirm(sync),
        _ => _SignedIn(sync),
      },
    );
  }
}

// ------------------------------------------------------------------ pieces

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(24), this.danger = false});
  final Widget child;
  final EdgeInsets padding;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: danger ? AppColors.accent.withValues(alpha: 0.03) : AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: danger ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border),
    ),
    child: child,
  );
}

/// Icon on a tinted square (vermilion, or green for a good state).
class _Badge extends StatelessWidget {
  const _Badge(this.icon, {this.size = 56, this.success = false, this.child});
  final IconData icon;
  final double size;
  final bool success;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: success ? AppColors.successTint : AppColors.accentTint,
      borderRadius: BorderRadius.circular(size * 0.22),
    ),
    child: child ?? Icon(icon, size: size * 0.4, color: success ? AppColors.success : AppColors.accent),
  );
}

/// "Se connecter | Créer un compte", the full width of the card.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.signUp, required this.onChanged});
  final bool signUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        for (final (value, label) in const [(false, 'Se connecter'), (true, 'Créer un compte')])
          Expanded(
            child: HoverBuilder(
              onActivate: () => onChanged(value),
              focusRingRadius: 8,
              builder: (context, hover) => Semantics(
                button: true,
                selected: value == signUp,
                child: GestureDetector(
                  onTap: () => onChanged(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == signUp
                          ? AppColors.action
                          : (hover ? AppColors.ink.withAlpha(0x12) : Colors.transparent),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: value == signUp ? AppColors.onAction : AppColors.textSoft,
                      ),
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

OutlineInputBorder _border(Color color, [double width = 1]) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(8),
  borderSide: BorderSide(color: color, width: width),
);

/// Label above, optional link on its right, and the field.
class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.password = false,
    this.trailing,
    this.keyboard,
    this.autofill,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool password;
  final Widget? trailing;
  final TextInputType? keyboard;
  final Iterable<String>? autofill;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            widget.label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSoft),
          ),
          const Spacer(),
          ?widget.trailing,
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: widget.controller,
        obscureText: widget.password && _hidden,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: widget.keyboard,
        autofillHints: widget.autofill,
        onSubmitted: widget.onSubmitted,
        style: TextStyle(fontSize: 15, color: AppColors.text),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: AppColors.placeholder, fontSize: 15),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: _border(AppColors.borderInput),
          enabledBorder: _border(AppColors.borderInput),
          focusedBorder: _border(AppColors.accent, 1.2),
          suffixIcon: widget.password
              ? IconButton(
                  tooltip: _hidden ? 'Afficher' : 'Masquer',
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(
                    _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 20,
                    color: AppColors.faint,
                  ),
                )
              : null,
        ),
      ),
    ],
  );
}

/// Tinted box with an icon: what to know before going on.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35, color: AppColors.text),
              ),
              const SizedBox(height: 4),
              Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSoft)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One line of feedback: an error (vermilion) or a confirmation (green).
class _Feedback extends StatelessWidget {
  const _Feedback(this.text, {this.ok = false});
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.accent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: color)),
        ),
      ],
    );
  }
}

/// White (ink in the light theme) button the full width of the card; shows
/// [busy] with a spinner while something runs.
class _Primary extends StatelessWidget {
  const _Primary(this.label, {required this.onTap, this.busy});
  final String label;
  final VoidCallback? onTap;
  final String? busy;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      onPressed: busy == null ? onTap : null,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        disabledForegroundColor: AppColors.textSoft,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: busy == null
          ? Text(label)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSoft),
                ),
                const SizedBox(width: 12),
                Text(busy!),
              ],
            ),
    ),
  );
}

/// Small text action ("Mot de passe oublié ?", "Changer d'adresse").
class _Link extends StatelessWidget {
  const _Link(this.label, {required this.onTap, this.accent = false, this.size = 13});
  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final double size;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: accent ? AppColors.accent : AppColors.textSoft,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(fontFamily: AppFonts.body, fontSize: size, fontWeight: FontWeight.w600),
    ),
    child: Text(label),
  );
}

ButtonStyle _outlined({Color? color, double height = 42}) => OutlinedButton.styleFrom(
  foregroundColor: color ?? AppColors.text,
  backgroundColor: Colors.transparent,
  minimumSize: Size(0, height),
  padding: const EdgeInsets.symmetric(horizontal: 18),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  side: BorderSide(color: color?.withValues(alpha: 0.6) ?? AppColors.borderStrong),
  textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w600),
);

/// Dashed outline: what stays on this computer.
class _DashedOutline extends CustomPainter {
  _DashedOutline(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)).deflate(0.5);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 4, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) => old.color != color;
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.local = false});
  final String label;
  final bool local;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(11, 7, 13, 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            local ? Icons.desktop_windows_outlined : Icons.check_rounded,
            size: 14,
            color: local ? AppColors.faint : AppColors.success,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: local ? AppColors.faint : AppColors.text,
            ),
          ),
        ],
      ),
    );
    if (local) return CustomPaint(painter: _DashedOutline(AppColors.borderStrong), child: content);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderInput),
      ),
      child: content,
    );
  }
}

/// One box per digit over an invisible field (typing, pasting and erasing
/// work as in any field).
class _CodeInput extends StatefulWidget {
  const _CodeInput({required this.controller, required this.onCompleted});
  final TextEditingController controller;
  final VoidCallback onCompleted;

  @override
  State<_CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<_CodeInput> {
  final _focus = FocusNode();

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const n = kEmailCodeLength;
      var gap = 10.0;
      var width = math.min(54.0, (constraints.maxWidth - gap * (n - 1)) / n);
      if (width < 40) {
        gap = 6;
        width = (constraints.maxWidth - gap * (n - 1)) / n;
      }
      final text = widget.controller.text;
      final current = math.min(text.length, n - 1);
      return SizedBox(
        height: width * 1.18,
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: width,
                    height: width * 1.18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.field,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _focus.hasFocus && i == current ? AppColors.accent : AppColors.borderInput,
                        width: _focus.hasFocus && i == current ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      i < text.length ? text[i] : '',
                      style: monoStyle(width * 0.44, weight: FontWeight.w600, color: AppColors.text),
                    ),
                  ),
                ],
              ],
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: n,
                  showCursor: false,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (v) {
                    if (v.length == n) widget.onCompleted();
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// -------------------------------------------------------------- signed out

/// The selling points next to the form.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Badge(Icons.lock_outline_rounded, size: 48),
      const SizedBox(height: 20),
      Text('TA BOBINE SUR TOUS\nTES ORDINATEURS', style: posterStyle(40, height: 0.95)),
      const SizedBox(height: 16),
      Text(
        "Tout est chiffré sur l'appareil avec ton mot de passe. Le serveur ne voit ni tes identifiants IPTV, "
        'ni ce que tu regardes.',
        style: TextStyle(fontSize: 15, height: 1.55, color: AppColors.textSoft),
      ),
      const SizedBox(height: 26),
      Text('SYNCHRONISÉ', style: labelStyle(color: AppColors.faint)),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final s in _synced) _Chip(s)]),
      const SizedBox(height: 24),
      Text('RESTE SUR CET ORDINATEUR', style: labelStyle(color: AppColors.faint)),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final s in _local) _Chip(s, local: true)]),
    ],
  );
}

enum _Mode { signIn, signUp, forgot, reset }

class _SignedOut extends StatefulWidget {
  const _SignedOut(this.sync);
  final SyncService sync;

  @override
  State<_SignedOut> createState() => _SignedOutState();
}

class _SignedOutState extends State<_SignedOut> {
  SyncService get _sync => widget.sync;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  _Mode _mode = _Mode.signIn;
  String? _busy;
  String? _error;
  String? _info;

  @override
  void dispose() {
    for (final c in [_email, _password, _confirm, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  void _switch(_Mode m) => setState(() {
    _mode = m;
    _error = null;
    _info = null;
    _password.clear();
    _confirm.clear();
    _code.clear();
  });

  String? _check() {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) return 'Adresse e-mail invalide.';
    if (_mode == _Mode.forgot) return null;
    if (_mode == _Mode.reset && _code.text.length != kEmailCodeLength) {
      return 'Saisis les $kEmailCodeLength chiffres du code reçu par e-mail.';
    }
    final creating = _mode == _Mode.signUp || _mode == _Mode.reset;
    if (_password.text.isEmpty) return 'Saisis ton mot de passe.';
    if (creating && _password.text.length < 8) return 'Le mot de passe doit faire au moins 8 caractères.';
    if (creating && _password.text != _confirm.text) return 'Les deux mots de passe ne sont pas identiques.';
    return null;
  }

  Future<void> _submit() async {
    if (_busy != null) return;
    final error = _check();
    if (error != null) return setState(() => _error = error);
    // Another account brings its own parental code, locks and kids profiles
    // (and receives this computer's sources): not without the code here.
    if (_mode != _Mode.forgot && !await confirmParent(context, title: 'Compte Bobine')) return;
    if (!mounted) return;
    setState(() {
      _error = null;
      _info = null;
      _busy = switch (_mode) {
        _Mode.signIn => 'Connexion…',
        _Mode.signUp => 'Création du compte…',
        _Mode.forgot => 'Envoi du code…',
        _Mode.reset => 'Changement du mot de passe…',
      };
    });
    final email = _email.text.trim();
    try {
      switch (_mode) {
        case _Mode.signIn:
          await _sync.signIn(email, _password.text);
        case _Mode.signUp:
          await _sync.signUp(email, _password.text);
        case _Mode.forgot:
          await _sync.forgotPassword(email);
          if (!mounted) return;
          _switch(_Mode.reset);
          _info = 'Code envoyé à $email.';
        case _Mode.reset:
          await _sync.resetPassword(email, _code.text, _password.text);
      }
    } on SyncApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _form() {
    final creating = _mode == _Mode.signUp;
    final forgot = _mode == _Mode.forgot || _mode == _Mode.reset;
    final children = <Widget>[
      if (forgot)
        Row(
          children: [
            IconButton(
              tooltip: 'Retour',
              onPressed: () => _switch(_Mode.signIn),
              icon: Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.textSoft),
            ),
            const SizedBox(width: 4),
            Text(
              'Mot de passe oublié',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
          ],
        )
      else
        _Tabs(signUp: creating, onChanged: (v) => _switch(v ? _Mode.signUp : _Mode.signIn)),
      if (_sync.message != null && !forgot) _Feedback(_sync.message!),
      if (_mode == _Mode.forgot)
        Text(
          'Indique ton adresse : un code te sera envoyé pour choisir un nouveau mot de passe.',
          style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSoft),
        ),
      _Field(
        label: 'Adresse e-mail',
        controller: _email,
        hint: 'toi@exemple.fr',
        keyboard: TextInputType.emailAddress,
        autofill: const [AutofillHints.email],
        onSubmitted: (_) => _submit(),
      ),
      if (_mode == _Mode.reset) ...[
        if (_info != null) _Feedback(_info!, ok: true),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Code reçu par e-mail',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSoft),
            ),
            const SizedBox(height: 8),
            _CodeInput(controller: _code, onCompleted: () {}),
          ],
        ),
      ],
      if (_mode != _Mode.forgot)
        _Field(
          label: _mode == _Mode.reset ? 'Nouveau mot de passe' : 'Mot de passe',
          controller: _password,
          password: true,
          hint: _mode == _Mode.signIn ? 'Ton mot de passe' : 'Au moins 8 caractères',
          autofill: [_mode == _Mode.signIn ? AutofillHints.password : AutofillHints.newPassword],
          trailing: _mode == _Mode.signIn
              ? _Link('Mot de passe oublié ?', accent: true, onTap: () => _switch(_Mode.forgot))
              : null,
          onSubmitted: (_) => _submit(),
        ),
      if (creating || _mode == _Mode.reset)
        _Field(
          label: 'Confirme le mot de passe',
          controller: _confirm,
          password: true,
          hint: 'Le même, une seconde fois',
          onSubmitted: (_) => _submit(),
        ),
      if (creating)
        const _Notice(
          icon: Icons.key_outlined,
          title: 'Ce mot de passe est aussi ta clé de chiffrement',
          text:
              "Personne ne peut lire tes données sans lui. En cas d'oubli, tu pourras en choisir un autre, "
              'mais les données repartiront de cet ordinateur.',
        ),
      if (_mode == _Mode.reset)
        const _Notice(
          icon: Icons.key_outlined,
          title: 'Le compte repartira de cet ordinateur',
          text:
              "Ce qui est sur le compte était chiffré avec l'ancien mot de passe : il sera remplacé par les "
              'données de cet ordinateur, et tes autres appareils devront se reconnecter.',
        ),
      if (_error != null) _Feedback(_error!),
      _Primary(
        switch (_mode) {
          _Mode.signIn => 'Se connecter',
          _Mode.signUp => 'Créer le compte',
          _Mode.forgot => 'Recevoir un code',
          _Mode.reset => 'Changer le mot de passe',
        },
        busy: _busy,
        onTap: _submit,
      ),
    ];
    return _Card(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: i == 1 && !forgot ? 22 : 18),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 720) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_form(), const SizedBox(height: 36), const _Intro()],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 380, child: _form()),
          const SizedBox(width: 26),
          const Expanded(child: _Intro()),
        ],
      );
    },
  );
}

// --------------------------------------------------------------- confirming

class _Confirm extends StatefulWidget {
  const _Confirm(this.sync);
  final SyncService sync;

  @override
  State<_Confirm> createState() => _ConfirmState();
}

class _ConfirmState extends State<_Confirm> {
  SyncService get _sync => widget.sync;
  final _code = TextEditingController();
  Timer? _timer;
  int _wait = _resendDelay;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _countdown();
  }

  void _countdown() {
    _timer?.cancel();
    _wait = _resendDelay;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (mounted && done != null) setState(() => _info = done);
    } on SyncApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _validate() {
    if (_code.text.length == kEmailCodeLength) _do(() => _sync.confirm(_code.text));
  }

  @override
  Widget build(BuildContext context) {
    final complete = _code.text.length == kEmailCodeLength;
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: _Card(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Badge(Icons.mail_outline_rounded),
              const SizedBox(height: 22),
              Text('VÉRIFIE TA BOÎTE MAIL', style: posterStyle(44, height: 0.95)),
              const SizedBox(height: 14),
              Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: 15, height: 1.55, color: AppColors.textSoft),
                  children: [
                    const TextSpan(text: 'Un code a été envoyé à '),
                    TextSpan(
                      text: _sync.pendingEmail ?? '',
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: '. Saisis-le ci-dessous.'),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              _CodeInput(controller: _code, onCompleted: _validate),
              const SizedBox(height: 26),
              FilledButton(
                onPressed: complete && !_busy ? _validate : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(104, 48),
                  shape: buttonShape,
                  // Faded until the code is complete.
                  disabledBackgroundColor: AppColors.action.withValues(alpha: 0.45),
                  disabledForegroundColor: AppColors.onAction,
                ),
                child: _busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAction),
                      )
                    : const Text('Valider'),
              ),
              if (_error != null) ...[const SizedBox(height: 16), _Feedback(_error!)],
              if (_info != null) ...[const SizedBox(height: 16), _Feedback(_info!, ok: true)],
              const SizedBox(height: 26),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_wait > 0)
                    Text(
                      "Renvoyer l'e-mail dans 0:${_wait.toString().padLeft(2, '0')}",
                      style: TextStyle(fontSize: 14, color: AppColors.faint),
                    )
                  else
                    _Link(
                      "Renvoyer l'e-mail",
                      size: 14,
                      onTap: _busy
                          ? null
                          : () => _do(() async {
                              await _sync.resendCode();
                              _countdown();
                            }, done: 'Nouvel e-mail envoyé.'),
                    ),
                  const SizedBox(width: 24),
                  _Link("Changer d'adresse", size: 14, onTap: _sync.cancelConfirmation),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- signed in

class _SignedIn extends StatelessWidget {
  const _SignedIn(this.sync);
  final SyncService sync;

  Future<void> _signOut(BuildContext context) async {
    if (await confirmParent(context, title: 'Se déconnecter')) await sync.signOut();
  }

  Future<void> _delete(BuildContext context) async {
    if (!await confirmParent(context, title: 'Supprimer le compte') || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le compte ?'),
        content: const Text(
          'Le compte et tout ce qu’il contient sur le serveur sont effacés. Les données de cet ordinateur '
          'sont conservées ; tes autres appareils arrêtent de se synchroniser.',
        ),
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
    if (ok != true) return;
    try {
      await sync.deleteAccount();
    } on SyncApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _account() {
    final email = sync.email ?? '';
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: Text(
              email.isEmpty ? '?' : email.characters.first.toUpperCase(),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.onAccent),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Connecté sur cet ordinateur · synchro chiffrée de bout en bout',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.textSoft),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Builder(
            builder: (context) => OutlinedButton(
              onPressed: () => _signOut(context),
              style: _outlined(),
              child: const Text('Se déconnecter'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _status() {
    final syncing = sync.status == SyncStatus.syncing;
    final failed = sync.status == SyncStatus.error;
    final (title, detail) = syncing
        ? ('Synchronisation…', 'Dernière synchronisation : ${formatRelative(sync.lastSync)}')
        : failed
        ? ('La synchronisation a échoué', sync.message ?? 'Nouvel essai dans quelques minutes.')
        : ('Tout est synchronisé', 'Dernière synchronisation : ${formatRelative(sync.lastSync)}');
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(
                failed ? Icons.error_outline_rounded : Icons.check_rounded,
                size: 44,
                success: !failed,
                child: syncing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.success),
                      )
                    : null,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      style: failed
                          ? TextStyle(fontSize: 13, height: 1.4, color: AppColors.accent)
                          : monoStyle(13, weight: FontWeight.w400),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: syncing ? null : sync.syncNow,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                child: const Text('Synchroniser'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Automatique au démarrage, après chaque changement et toutes les quelques minutes.',
            style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.faint),
          ),
        ],
      ),
    );
  }

  Widget _lists() {
    Widget column(String title, List<String> items, {bool local = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: labelStyle(color: AppColors.faint)),
        const SizedBox(height: 10),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  local ? Icons.desktop_windows_outlined : Icons.check_rounded,
                  size: 16,
                  color: local ? AppColors.faint : AppColors.success,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: local ? FontWeight.w400 : FontWeight.w500,
                      color: local ? AppColors.faint : AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final synced = column('SYNCHRONISÉ', _synced);
    final local = column('RESTE SUR CET ORDINATEUR', _local, local: true);
    return _Card(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < 520
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [synced, const SizedBox(height: 18), local],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: synced),
                  const SizedBox(width: 24),
                  Expanded(child: local),
                ],
              ),
      ),
    );
  }

  Widget _danger(BuildContext context) => _Card(
    danger: true,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supprimer le compte',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
              const SizedBox(height: 6),
              Text(
                'Efface le compte et ses données sur le serveur. Cet ordinateur garde les siennes.',
                style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.faint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        OutlinedButton(
          onPressed: () => _delete(context),
          style: _outlined(color: AppColors.accent),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _account(),
      const SizedBox(height: 12),
      _status(),
      const SizedBox(height: 12),
      _lists(),
      const SizedBox(height: 12),
      _danger(context),
    ],
  );
}
