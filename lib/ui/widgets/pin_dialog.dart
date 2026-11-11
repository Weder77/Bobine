import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../services.dart';

/// Whether an action that can undo the parental control (account, sources,
/// backups) needs the code now: always in a kids profile, elsewhere until
/// the code was typed this session.
bool parentalCodeNeeded(AppServices s) =>
    codeNeeded(enabled: s.settings.parentalEnabled, kids: s.profile.kids, unlocked: s.parentalUnlocked);

/// [parentalCodeNeeded], from its three facts.
bool codeNeeded({required bool enabled, required bool kids, required bool unlocked}) => enabled && (kids || !unlocked);

/// Asks the parental code before such an action. True when it may go on:
/// no code needed, or the right one typed.
Future<bool> confirmParent(BuildContext context, {required String title}) async {
  final s = AppScope.of(context);
  if (!parentalCodeNeeded(s)) return true;
  final pin = await askPin(context, title: title, message: 'Tape le code parental.');
  if (pin == null || !context.mounted) return false;
  if (s.checkParentalPin(pin)) return true;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.parentalRefusal)));
  return false;
}

/// Asks for the 4-digit parental code. With [confirm], it is asked twice
/// (setting a new code). Returns null when cancelled.
Future<String?> askPin(BuildContext context, {required String title, String? message, bool confirm = false}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(title: title, message: message, confirm: confirm),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, required this.confirm, this.message});
  final String title;
  final String? message;
  final bool confirm;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();
  String? _first;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String v) {
    if (v.length != 4) return;
    if (widget.confirm && _first == null) {
      setState(() {
        _first = v;
        _error = null;
        _controller.clear();
      });
      return;
    }
    if (widget.confirm && v != _first) {
      setState(() {
        _first = null;
        _error = 'Les deux codes ne sont pas identiques. Recommence.';
        _controller.clear();
      });
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.confirm && _first != null ? 'Retape le code pour confirmer.' : widget.message;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.title, style: displayStyle(22))),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (step != null) Text(step, style: TextStyle(color: AppColors.textSoft)),
            const SizedBox(height: 16),
            TextField(
              key: ValueKey(_first),
              controller: _controller,
              autofocus: true,
              obscureText: true,
              obscuringCharacter: '●',
              maxLength: 4,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 30, letterSpacing: 18, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(counterText: '', hintText: '····'),
              onChanged: _submit,
              onSubmitted: _submit,
            ),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(color: AppColors.live))],
          ],
        ),
      ),
      actions: [
        if (!widget.confirm)
          TextButton(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              forgotParentalCode(nav.context);
            },
            child: const Text('Code oublié ?'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
      ],
    );
  }
}

/// A forgotten parental code: a new one is chosen once the password of the
/// Bobine account of this device is typed. Without an account, it cannot
/// be: whoever is in front of the screen could otherwise lift it.
Future<void> forgotParentalCode(BuildContext context) async {
  final s = AppScope.of(context);
  if (!s.sync.signedIn) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code parental oublié'),
        content: const Text(
          "Le code ne peut être changé qu'avec le mot de passe du compte Bobine connecté sur cet ordinateur, "
          "et aucun compte n'y est connecté. Sans lui, seule une réinstallation qui efface les données de "
          "l'application retire le code.",
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
      ),
    );
    return;
  }
  final password = await showDialog<String>(context: context, builder: (_) => const _AccountPasswordDialog());
  if (password == null || !context.mounted) return;
  if (!await s.sync.checkPassword(password)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de passe du compte incorrect.')));
    }
    return;
  }
  if (!context.mounted) return;
  final pin = await askPin(context, title: 'Nouveau code parental', message: 'Choisis 4 chiffres.', confirm: true);
  if (pin == null || !context.mounted) return;
  s.setParentalPin(pin);
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nouveau code parental enregistré.')));
}

class _AccountPasswordDialog extends StatefulWidget {
  const _AccountPasswordDialog();

  @override
  State<_AccountPasswordDialog> createState() => _AccountPasswordDialogState();
}

class _AccountPasswordDialogState extends State<_AccountPasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = AppScope.of(context).sync.email ?? '';
    void submit() => Navigator.of(context).pop(_controller.text);
    return AlertDialog(
      title: const Text('Code parental oublié'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tape le mot de passe du compte Bobine ($email) pour choisir un nouveau code.',
              style: TextStyle(color: AppColors.textSoft),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe du compte'),
              onSubmitted: (_) => submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: submit, child: const Text('Continuer')),
      ],
    );
  }
}
