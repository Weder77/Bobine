import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

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
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler'))],
    );
  }
}
