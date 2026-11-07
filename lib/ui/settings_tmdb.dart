import 'package:flutter/material.dart';

import '../core/open_url.dart';
import '../core/theme.dart';
import '../services.dart';
import 'settings_screen.dart';

/// Réglages → Fiches enrichies (TMDB).
class TmdbSection extends StatefulWidget {
  const TmdbSection({super.key});

  @override
  State<TmdbSection> createState() => _TmdbSectionState();
}

class _TmdbSectionState extends State<TmdbSection> {
  late final AppServices _s = AppScope.of(context);
  late final _c = TextEditingController(text: _s.settings.tmdbKey ?? '');
  bool _obscure = true;
  bool _testing = false;
  String? _message;
  bool _ok = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _c.text.trim();
    if (key == (_s.settings.tmdbKey ?? '')) return;
    _s.settings.update((x) => x.tmdbKey = key.isEmpty ? null : key);
    if (key.isEmpty) {
      setState(() => _message = null);
    } else {
      await _test();
    }
  }

  Future<void> _test() async {
    final key = _c.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _testing = true;
      _message = null;
    });
    final error = await _s.tmdb.testKey(key);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = error == null;
      _message = error ?? 'Clé valide : les fiches seront complétées en ouvrant un film ou une série.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Fiches enrichies (TMDB)',
      children: [
        SettingsOption(
          title: 'Clé TMDB',
          subtitle:
              'Ajoute grandes images, résumé en français, distribution et bande-annonce aux films et séries. '
              'Clé gratuite : crée un compte sur themoviedb.org → Paramètres → API. '
              'La clé (ou le jeton de lecture) reste sur cet ordinateur, chiffrée.',
          child: SizedBox(
            width: 320,
            child: TextField(
              controller: _c,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Clé API ou jeton',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Afficher' : 'Masquer',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              onSubmitted: (_) => _save(),
              onTapOutside: (_) => _save(),
            ),
          ),
        ),
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(onPressed: _testing ? null : _test, child: const Text('Tester la clé')),
              TextButton(
                onPressed: () => openExternal('https://www.themoviedb.org/settings/api'),
                child: const Text('Obtenir une clé'),
              ),
              TextButton(
                onPressed: () {
                  _s.repo.tmdbClear();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fiches TMDB oubliées.')));
                },
                child: const Text('Vider le cache'),
              ),
              if (_testing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text),
                ),
              if (_message != null) Text(_message!, style: TextStyle(color: _ok ? AppColors.success : AppColors.live)),
            ],
          ),
        ),
      ],
    );
  }
}
