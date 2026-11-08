import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../services.dart';
import '../sync/supabase_api.dart';
import '../sync/sync_service.dart';
import 'settings_screen.dart';

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
        SyncStatus.signedOut => _SignInForm(sync),
        SyncStatus.confirming => _ConfirmForm(sync),
        _ => _AccountStatus(sync),
      },
    );
  }
}

const _what =
    'Sources (identifiants compris), profils, favoris, reprises et épisodes vus, chaînes récentes, '
    'catégories masquées ou verrouillées, chaînes masquées, rappels, code parental, clé TMDB et '
    "réglages de lecture. Le cache, le décodage, le volume et les enregistrements restent propres à l'ordinateur.";

/// Error / information line under a form.
class _Message extends StatelessWidget {
  const _Message(this.text, {this.ok = false});
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Text(text, style: TextStyle(color: ok ? AppColors.success : AppColors.live, fontSize: 14, height: 1.4)),
  );
}

class _Busy extends StatelessWidget {
  const _Busy(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text)),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: AppColors.faint, fontSize: 14)),
    ],
  );
}

Widget _field(
  TextEditingController c, {
  required String label,
  bool obscure = false,
  TextInputType? type,
  ValueChanged<String>? onSubmitted,
  List<String>? autofill,
}) => Padding(
  padding: const EdgeInsets.only(top: 14),
  child: SizedBox(
    width: 360,
    child: TextField(
      controller: c,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: type,
      autofillHints: autofill,
      decoration: InputDecoration(labelText: label),
      onSubmitted: onSubmitted,
    ),
  ),
);

enum _Mode { signIn, signUp, forgot, reset }

class _SignInForm extends StatefulWidget {
  const _SignInForm(this.sync);
  final SyncService sync;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
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
  });

  String? _check({bool newPassword = false}) {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return 'Adresse e-mail invalide.';
    if (_mode == _Mode.forgot) return null;
    if (_mode == _Mode.reset && _code.text.trim().length < 6) return 'Saisis le code reçu par e-mail.';
    if (newPassword && _password.text.length < 8) return 'Le mot de passe doit faire au moins 8 caractères.';
    if (_password.text.isEmpty) return 'Saisis ton mot de passe.';
    if (newPassword && _password.text != _confirm.text) return 'Les deux mots de passe ne sont pas identiques.';
    return null;
  }

  Future<void> _submit() async {
    if (_busy != null) return;
    final error = _check(newPassword: _mode == _Mode.signUp || _mode == _Mode.reset);
    if (error != null) return setState(() => _error = error);
    setState(() {
      _error = null;
      _info = null;
      _busy = switch (_mode) {
        _Mode.forgot => 'Envoi du code…',
        _ => 'Calcul des clés de chiffrement…',
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
          _info = 'Un code a été envoyé à $email.';
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

  @override
  Widget build(BuildContext context) {
    final creating = _mode == _Mode.signUp;
    final title = switch (_mode) {
      _Mode.signIn || _Mode.signUp => 'Compte Bobine',
      _Mode.forgot || _Mode.reset => 'Mot de passe oublié',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Synchronisation',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Retrouve tes sources, profils, favoris et reprises sur tous tes ordinateurs. '
                    'Tout est chiffré sur l’appareil avec ton mot de passe : le serveur ne voit ni tes '
                    'identifiants IPTV ni ce que tu regardes.',
                    style: TextStyle(fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Text(_what, style: const TextStyle(color: AppColors.faint, fontSize: 14, height: 1.45)),
                  if (_sync.message != null) _Message(_sync.message!),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: title,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_mode == _Mode.signIn || _mode == _Mode.signUp)
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: SettingsSegments<_Mode>(
                          value: _mode,
                          options: const {_Mode.signIn: 'Se connecter', _Mode.signUp: 'Créer un compte'},
                          onChanged: _switch,
                        ),
                      ),
                    if (_mode == _Mode.forgot || _mode == _Mode.reset)
                      const Padding(
                        padding: EdgeInsets.only(top: 22),
                        child: Text(
                          'Un code est envoyé par e-mail pour choisir un nouveau mot de passe. Ce qui est '
                          'sur le compte était chiffré avec l’ancien : il sera remplacé par les données de '
                          'cet ordinateur, et tes autres appareils devront se reconnecter.',
                          style: TextStyle(color: AppColors.faint, fontSize: 14, height: 1.45),
                        ),
                      ),
                    _field(
                      _email,
                      label: 'Adresse e-mail',
                      type: TextInputType.emailAddress,
                      autofill: const [AutofillHints.email],
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_mode == _Mode.reset) _field(_code, label: 'Code reçu par e-mail', type: TextInputType.number),
                    if (_mode != _Mode.forgot)
                      _field(
                        _password,
                        label: _mode == _Mode.reset ? 'Nouveau mot de passe' : 'Mot de passe',
                        obscure: true,
                        autofill: [creating ? AutofillHints.newPassword : AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                      ),
                    if (creating || _mode == _Mode.reset)
                      _field(_confirm, label: 'Confirme le mot de passe', obscure: true, onSubmitted: (_) => _submit()),
                    if (creating)
                      const Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: SizedBox(
                          width: 460,
                          child: Text(
                            'Garde bien ce mot de passe : il sert aussi à chiffrer tes données, personne ne peut '
                            'les lire sans lui. En cas d’oubli, tu pourras en choisir un autre et les données '
                            'repartiront de cet ordinateur.',
                            style: TextStyle(color: AppColors.faint, fontSize: 13, height: 1.45),
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_busy != null)
                          _Busy(_busy!)
                        else ...[
                          FilledButton(
                            onPressed: _submit,
                            child: Text(switch (_mode) {
                              _Mode.signIn => 'Se connecter',
                              _Mode.signUp => 'Créer le compte',
                              _Mode.forgot => 'Recevoir un code',
                              _Mode.reset => 'Changer le mot de passe',
                            }),
                          ),
                          if (_mode == _Mode.signIn)
                            TextButton(
                              onPressed: () => _switch(_Mode.forgot),
                              child: const Text('Mot de passe oublié ?'),
                            ),
                          if (_mode == _Mode.forgot || _mode == _Mode.reset)
                            TextButton(onPressed: () => _switch(_Mode.signIn), child: const Text('Retour')),
                        ],
                      ],
                    ),
                    if (_error != null) _Message(_error!),
                    if (_info != null) _Message(_info!, ok: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfirmForm extends StatefulWidget {
  const _ConfirmForm(this.sync);
  final SyncService sync;

  @override
  State<_ConfirmForm> createState() => _ConfirmFormState();
}

class _ConfirmFormState extends State<_ConfirmForm> {
  SyncService get _sync => widget.sync;
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'Confirme ton adresse',
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Un e-mail a été envoyé à ${_sync.pendingEmail}. Saisis le code qu’il contient, ou clique sur '
              'son lien puis reviens ici.',
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            _field(
              _code,
              label: 'Code reçu par e-mail',
              type: TextInputType.number,
              onSubmitted: (_) => _do(() => _sync.confirm(_code.text)),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_busy)
                  const _Busy('Vérification…')
                else ...[
                  FilledButton(onPressed: () => _do(() => _sync.confirm(_code.text)), child: const Text('Valider')),
                  OutlinedButton(
                    onPressed: () => _do(_sync.confirmedByLink),
                    child: const Text('J’ai cliqué sur le lien'),
                  ),
                  TextButton(
                    onPressed: () => _do(_sync.resendCode, done: 'Nouvel e-mail envoyé.'),
                    child: const Text('Renvoyer l’e-mail'),
                  ),
                  TextButton(onPressed: _sync.cancelConfirmation, child: const Text('Annuler')),
                ],
              ],
            ),
            if (_error != null) _Message(_error!),
            if (_info != null) _Message(_info!, ok: true),
          ],
        ),
      ),
    ],
  );
}

class _AccountStatus extends StatelessWidget {
  const _AccountStatus(this.sync);
  final SyncService sync;

  Future<void> _delete(BuildContext context, SyncService sync) async {
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

  @override
  Widget build(BuildContext context) {
    final syncing = sync.status == SyncStatus.syncing;
    final state = syncing
        ? 'Synchronisation en cours…'
        : sync.status == SyncStatus.error
        ? sync.message ?? 'La dernière synchronisation a échoué.'
        : 'Dernière synchronisation : ${formatRelative(sync.lastSync)}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Compte',
          children: [
            SettingsOption(
              title: sync.email ?? 'Compte',
              subtitle: 'Connecté sur cet ordinateur. Tes données sont chiffrées avec ton mot de passe avant envoi.',
              child: SmallOutlinedButton(label: 'Se déconnecter', onTap: sync.signOut),
            ),
            SettingsOption(
              title: 'Synchronisation',
              subtitle: '$state Automatique au démarrage, après chaque changement et toutes les quelques minutes.',
              child: syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
                    )
                  : SmallOutlinedButton(label: 'Synchroniser', onTap: sync.syncNow),
            ),
            const SettingsOption(title: 'Ce qui est synchronisé', subtitle: _what, child: SizedBox.shrink()),
            SettingsOption(
              title: 'Supprimer le compte',
              subtitle: 'Efface le compte et ses données sur le serveur. Cet ordinateur garde les siennes.',
              child: SmallOutlinedButton(label: 'Supprimer', onTap: () => _delete(context, sync)),
            ),
          ],
        ),
      ],
    );
  }
}
