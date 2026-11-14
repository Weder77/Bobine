import 'package:flutter/material.dart';

import '../core/app_exit.dart';
import 'tv_account.dart';
import 'tv_focus.dart';
import 'tv_form.dart';
import 'tv_sources.dart';

enum _Way { account, source }

/// First launch on the TV: sign in to a Bobine account (the sources come
/// back by the sync) or add a source without an account. Once there is a
/// source, the app opens by itself.
class TvWelcomeScreen extends StatefulWidget {
  const TvWelcomeScreen({super.key, this.onExit});

  /// Retour on the choice (default: leave Bobine).
  final VoidCallback? onExit;

  @override
  State<TvWelcomeScreen> createState() => _TvWelcomeScreenState();
}

class _TvWelcomeScreenState extends State<TvWelcomeScreen> {
  final _c = TvFocusController(initial: 'w-account');
  _Way? _way;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go(_Way? way) {
    setState(() => _way = way);
    if (way == null) _c.focus('w-account');
  }

  @override
  Widget build(BuildContext context) => switch (_way) {
    _Way.account => TvAccountView(onBack: () => _go(null), onAddSource: () => _go(_Way.source), backLabel: 'Bienvenue'),
    _Way.source => TvSourcesView(onBack: () => _go(null), onDone: (_) {}, backLabel: 'Bienvenue'),
    null => TvFormFrame(
      controller: _c,
      onBack: widget.onExit ?? AppExit.leave,
      title: 'Bienvenue',
      subtitle: 'Les chaînes, films, séries et le guide TV de ton abonnement IPTV, à la télécommande.',
      backLabel: 'Quitter',
      side: const TvFormHelp(
        title: 'Bobine',
        text:
            'Bobine est un lecteur : il ne fournit aucun contenu. Tes identifiants restent sur cette télé, '
            'ou chiffrés dans ton compte Bobine.',
      ),
      children: [
        TvChoice(
          id: 'w-account',
          icon: Icons.sync_rounded,
          title: 'Me connecter à mon compte Bobine',
          text: 'Tes sources, profils, favoris et reprises reviennent tout seuls.',
          onOk: () => _go(_Way.account),
        ),
        TvChoice(
          id: 'w-source',
          icon: Icons.add_rounded,
          title: 'Ajouter une source sans compte',
          text: 'Un abonnement Xtream Codes ou une playlist M3U. Rien n’est synchronisé.',
          onOk: () => _go(_Way.source),
        ),
      ],
    ),
  };
}
