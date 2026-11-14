import 'package:flutter/material.dart';

import '../services.dart';
import '../sync/supabase_api.dart';
import '../sync/sync_service.dart';
import '../ui/settings_account.dart' show kEmailCodeLength;
import '../ui/widgets/pin_dialog.dart';
import 'tv_focus.dart';
import 'tv_form.dart';
import 'tv_rows.dart';
import 'tv_theme.dart';

enum TvAccountMode { signIn, signUp, forgot, reset }

/// What is wrong in the account form, or null (as on a computer).
String? tvAccountError(
  TvAccountMode mode, {
  required String email,
  String password = '',
  String confirm = '',
  String code = '',
}) {
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) return 'Adresse e-mail invalide.';
  if (mode == TvAccountMode.forgot) return null;
  if (mode == TvAccountMode.reset && code.trim().length != kEmailCodeLength) {
    return 'Saisis les $kEmailCodeLength chiffres du code reçu par e-mail.';
  }
  final creating = mode == TvAccountMode.signUp || mode == TvAccountMode.reset;
  if (password.isEmpty) return 'Saisis ton mot de passe.';
  if (creating && password.length < 8) return 'Le mot de passe doit faire au moins 8 caractères.';
  if (creating && password != confirm) return 'Les deux mots de passe ne sont pas identiques.';
  return null;
}

/// Compte Bobine on the TV: sign in (or create the account, or a new
/// password), the code received by e-mail, then who is signed in, the sync
/// and Se déconnecter.
class TvAccountView extends StatefulWidget {
  const TvAccountView({super.key, required this.onBack, this.onAddSource, this.backLabel = 'Réglages'});

  final VoidCallback onBack;

  /// First launch: signed in to an account without any source yet.
  final VoidCallback? onAddSource;
  final String backLabel;

  /// Réglages → Compte Bobine.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (ctx) => TvAccountView(onBack: () => Navigator.of(ctx).pop())));

  @override
  State<TvAccountView> createState() => _TvAccountViewState();
}

class _TvAccountViewState extends State<TvAccountView> {
  final _c = TvFocusController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  TvAccountMode _mode = TvAccountMode.signIn;
  String? _busy;
  String? _error;
  String? _info;
  SyncStatus? _status;

  SyncService get _sync => AppScope.of(context).sync;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _c.fallback = () => _first;
  }

  @override
  void dispose() {
    _c.dispose();
    for (final t in [_email, _password, _confirm, _code]) {
      t.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String get _first => switch (_sync.status) {
    SyncStatus.signedOut => 'a-email',
    SyncStatus.confirming => 'a-code',
    _ => 'a-sync',
  };

  void _switch(TvAccountMode m) {
    setState(() {
      _mode = m;
      _error = null;
      _info = null;
      _password.clear();
      _confirm.clear();
      _code.clear();
    });
    _c.focus('a-email');
  }

  Future<void> _run(String busy, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() {
      _busy = busy;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on SyncApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _submit() async {
    final error = tvAccountError(
      _mode,
      email: _email.text,
      password: _password.text,
      confirm: _confirm.text,
      code: _code.text,
    );
    if (error != null) return setState(() => _error = error);
    // Another account brings its own parental code and kids profiles: not
    // without the code here (as on a computer).
    if (_mode != TvAccountMode.forgot && !await confirmParent(context, title: 'Compte Bobine')) return;
    if (!mounted) return;
    final email = _email.text.trim();
    switch (_mode) {
      case TvAccountMode.signIn:
        await _run('Connexion…', () => _sync.signIn(email, _password.text));
      case TvAccountMode.signUp:
        await _run('Création du compte…', () => _sync.signUp(email, _password.text));
      case TvAccountMode.forgot:
        await _run('Envoi du code…', () async {
          await _sync.forgotPassword(email);
          if (!mounted) return;
          _switch(TvAccountMode.reset);
          _info = 'Code envoyé à $email.';
          _c.focus('a-code');
        });
      case TvAccountMode.reset:
        await _run('Changement du mot de passe…', () => _sync.resetPassword(email, _code.text.trim(), _password.text));
    }
  }

  Future<void> _signOut() async {
    if (!await confirmParent(context, title: 'Se déconnecter')) return;
    await _run('Déconnexion…', _sync.signOut);
  }

  Widget? _message() {
    if (_busy != null) return TvFormMessage(_busy!);
    if (_error != null) return TvFormMessage(_error!, error: true);
    if (_info != null) return TvFormMessage(_info!);
    final m = _sync.message;
    if (m != null && _sync.status == SyncStatus.signedOut) return TvFormMessage(m);
    return null;
  }

  Widget _buttons(List<Widget> buttons) => Wrap(spacing: 20, runSpacing: 20, children: buttons);

  List<Widget> _signedOut() {
    final (submit, others) = switch (_mode) {
      TvAccountMode.signIn => (
        'Se connecter',
        [
          TvButton(id: 'a-signup', label: 'Créer un compte', onOk: () => _switch(TvAccountMode.signUp)),
          TvButton(id: 'a-forgot', label: 'Mot de passe oublié', onOk: () => _switch(TvAccountMode.forgot)),
        ],
      ),
      TvAccountMode.signUp => (
        'Créer le compte',
        [TvButton(id: 'a-signin', label: 'J’ai déjà un compte', onOk: () => _switch(TvAccountMode.signIn))],
      ),
      TvAccountMode.forgot => (
        'Envoyer le code',
        [TvButton(id: 'a-signin', label: 'Retour à la connexion', onOk: () => _switch(TvAccountMode.signIn))],
      ),
      TvAccountMode.reset => (
        'Changer le mot de passe',
        [TvButton(id: 'a-signin', label: 'Retour à la connexion', onOk: () => _switch(TvAccountMode.signIn))],
      ),
    };
    final creating = _mode == TvAccountMode.signUp || _mode == TvAccountMode.reset;
    return [
      TvTextField(
        id: 'a-email',
        label: 'Adresse e-mail',
        hint: 'toi@exemple.fr',
        controller: _email,
        keyboard: TextInputType.emailAddress,
      ),
      if (_mode == TvAccountMode.reset)
        TvTextField(id: 'a-code', label: 'Code reçu par e-mail', controller: _code, keyboard: TextInputType.number),
      if (_mode != TvAccountMode.forgot)
        TvTextField(
          id: 'a-password',
          label: creating ? 'Nouveau mot de passe (8 caractères au moins)' : 'Mot de passe',
          controller: _password,
          obscure: true,
        ),
      if (creating) TvTextField(id: 'a-confirm', label: 'Le même mot de passe', controller: _confirm, obscure: true),
      ?_message(),
      _buttons([TvButton(id: 'a-submit', label: submit, primary: true, onOk: _submit), ...others]),
    ];
  }

  List<Widget> _confirming() => [
    TvFormMessage('Un code a été envoyé à ${_sync.email ?? 'ton adresse'}. Saisis-le pour activer le compte.'),
    TvTextField(id: 'a-code', label: 'Code reçu par e-mail', controller: _code, keyboard: TextInputType.number),
    ?_message(),
    _buttons([
      TvButton(
        id: 'a-confirm',
        label: 'Valider',
        primary: true,
        onOk: () => _run('Vérification…', () => _sync.confirm(_code.text.trim())),
      ),
      TvButton(
        id: 'a-resend',
        label: 'Renvoyer le code',
        onOk: () => _run('Envoi…', () async {
          await _sync.resendCode();
          if (mounted) setState(() => _info = 'Nouveau code envoyé.');
        }),
      ),
      TvButton(id: 'a-cancel', label: 'Annuler', onOk: _sync.cancelConfirmation),
    ]),
  ];

  List<Widget> _signedIn(AppServices s) {
    final last = _sync.lastSync;
    final (state, color) = switch (_sync.status) {
      SyncStatus.syncing => ('Synchronisation…', TvColors.soft),
      SyncStatus.error => (
        'La synchronisation a échoué. ${_sync.message ?? 'Nouvel essai dans quelques minutes.'}',
        TvColors.accent,
      ),
      _ => (
        last == null ? 'Pas encore synchronisé' : 'Synchronisé il y a ${tvDuration(DateTime.now().difference(last))}',
        TvColors.ok,
      ),
    };
    final noSource = s.repo.sources().isEmpty;
    return [
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 28),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: TvColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CONNECTÉ', style: tvKicker(TvColors.ok)),
            const SizedBox(height: 16),
            Text(_sync.email ?? 'Compte Bobine', style: tvText(34, weight: FontWeight.w600, height: 1.1)),
            const SizedBox(height: 14),
            Text(state, style: tvText(26, height: 1.35, color: color)),
          ],
        ),
      ),
      ?_message(),
      _buttons([
        if (widget.onAddSource != null && noSource && _sync.status != SyncStatus.syncing)
          TvButton(
            id: 'a-add',
            label: 'Ajouter une source',
            icon: Icons.add_rounded,
            primary: true,
            onOk: widget.onAddSource,
          ),
        TvButton(
          id: 'a-sync',
          label: 'Synchroniser maintenant',
          icon: Icons.sync_rounded,
          onOk: () => _run('Synchronisation…', _sync.syncNow),
        ),
        TvButton(id: 'a-signout', label: 'Se déconnecter', icon: Icons.logout_rounded, onOk: _signOut),
      ]),
    ];
  }

  Widget _help() => switch (_sync.status) {
    SyncStatus.signedOut => TvFormHelp(
      title: switch (_mode) {
        TvAccountMode.signIn => 'Ta Bobine sur tous tes appareils',
        TvAccountMode.signUp => 'Nouveau compte',
        TvAccountMode.forgot || TvAccountMode.reset => 'Mot de passe oublié',
      },
      text: switch (_mode) {
        TvAccountMode.forgot || TvAccountMode.reset =>
          'Un code arrive par e-mail. Ce que ton compte gardait était chiffré avec l’ancien mot de passe : '
              'il est remplacé par ce qui est sur cette télé.',
        _ =>
          'Tes sources, profils, favoris et reprises suivent ton compte. Tout est chiffré avec ton mot de passe : '
              'le serveur ne voit ni tes identifiants IPTV, ni ce que tu regardes.',
      },
    ),
    SyncStatus.confirming => const TvFormHelp(
      title: 'Presque fini',
      text: 'Le code est dans l’e-mail envoyé par Bobine. Pense à regarder dans les courriers indésirables.',
    ),
    _ => const TvFormHelp(
      title: 'Synchronisation',
      text:
          'Bobine garde cette télé en phase avec tes autres appareils, toute seule. Pour supprimer le compte, '
          'passe par Bobine sur ordinateur.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: _sync,
      builder: (context, _) {
        final status = _sync.status;
        final moved = _status != null && (status == SyncStatus.signedOut) != (_status == SyncStatus.signedOut);
        _status = status;
        if (moved || _c.id == null || !_c.isRegistered(_c.id!)) {
          // Signed in or out, or the line focused went away: the first one.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (moved || _c.id == null || !_c.isRegistered(_c.id!)) _c.focus(_first);
          });
        }
        return TvFormFrame(
          controller: _c,
          onBack: widget.onBack,
          title: 'Compte Bobine',
          subtitle: switch (status) {
            SyncStatus.signedOut => switch (_mode) {
              TvAccountMode.signIn => 'Connecte-toi pour retrouver tes sources, profils, favoris et reprises.',
              TvAccountMode.signUp => 'Crée ton compte : tout ce qui est sur cette télé y sera gardé.',
              _ => 'Choisis un nouveau mot de passe avec le code reçu par e-mail.',
            },
            SyncStatus.confirming => 'Active ton compte.',
            _ => 'Ta Bobine est synchronisée avec tes autres appareils.',
          },
          backLabel: widget.backLabel,
          side: _help(),
          children: switch (status) {
            SyncStatus.signedOut => _signedOut(),
            SyncStatus.confirming => _confirming(),
            _ => _signedIn(s),
          },
        );
      },
    );
  }
}
