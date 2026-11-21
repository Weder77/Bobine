import 'package:flutter/material.dart';

import '../core/device.dart';
import '../core/theme.dart';
import '../services.dart';
import '../sync/sync_service.dart';
import 'settings_account.dart';
import 'source_form.dart';
import 'widgets/tv_canvas.dart';
import 'widgets/brand.dart';
import 'widgets/common.dart';

/// First launch: sign in to a Bobine account (sources and settings come
/// back by the sync), or add a playlist without an account (nothing leaves
/// this device).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final here = Device.isTv ? 'cette télé' : 'cet ordinateur';
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -0.8),
            radius: 1.4,
            colors: [AppColors.accentSelected, AppColors.bg],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              // On the TV, Up / Down go through every field and link in order.
              child: TvFormNav(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BobineLogo(height: 60),
                    const SizedBox(height: 36),
                    Text('BIENVENUE', style: posterStyle(76, height: 0.9)),
                    const SizedBox(height: 10),
                    Text(
                      'Les chaînes, films, séries et le guide TV de ton abonnement, importés automatiquement.',
                      style: TextStyle(color: AppColors.textSoft, fontSize: 16, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    OnboardingChoice(
                      account: (context) => const _AccountStep(),
                      playlist: (context) => _Panel(child: SourceForm(onSaved: (_) {})),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Bobine est un lecteur : il ne fournit aucun contenu. Tes identifiants restent sur $here.',
                      style: TextStyle(color: AppColors.faint, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two ways to start, then the one chosen ([account] or [playlist]),
/// with a way back to the choice.
class OnboardingChoice extends StatefulWidget {
  const OnboardingChoice({super.key, required this.account, required this.playlist});

  final WidgetBuilder account;
  final WidgetBuilder playlist;

  @override
  State<OnboardingChoice> createState() => _OnboardingChoiceState();
}

enum _Way { account, playlist }

class _OnboardingChoiceState extends State<OnboardingChoice> {
  _Way? _way;

  void _choose(_Way? w) => setState(() => _way = w);

  @override
  Widget build(BuildContext context) {
    final way = _way;
    if (way == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WayCard(
            autofocus: true,
            icon: Icons.sync_rounded,
            title: 'Me connecter à mon compte Bobine',
            text:
                'Tes sources, profils, favoris et reprises reviennent tout seuls, et restent synchronisés '
                'avec tes autres appareils.',
            onTap: () => _choose(_Way.account),
          ),
          const SizedBox(height: 12),
          _WayCard(
            icon: Icons.playlist_add_rounded,
            title: 'Ajouter une playlist sans compte',
            text:
                'Un abonnement Xtream Codes ou une playlist M3U, tout de suite. Tu pourras créer un compte '
                'plus tard dans Paramètres → Compte.',
            onTap: () => _choose(_Way.playlist),
          ),
        ],
      );
    }
    // Back of the TV remote returns to the choice (not out of Bobine).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _choose(null);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _choose(null),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Autre choix'),
            ),
          ),
          const SizedBox(height: 8),
          if (way == _Way.playlist) ...[
            Text(
              'Sans compte, rien n’est synchronisé : tout reste sur cet appareil.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
          ],
          Builder(builder: way == _Way.account ? widget.account : widget.playlist),
        ],
      ),
    );
  }
}

/// One of the two ways to start: a large card, the remote's first stop.
class _WayCard extends StatelessWidget {
  const _WayCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    autofocus: autofocus,
    onActivate: onTap,
    focusRingRadius: 12,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: hovered ? AppColors.surface2 : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hovered ? AppColors.accent : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 30, color: AppColors.accent),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
                  ),
                  const SizedBox(height: 6),
                  Text(text, style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textSoft)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

/// Sign in (or create the account). Once signed in, the sync brings the
/// sources back and the app opens by itself; an account without any source
/// yet gets the playlist form, whose source then goes to the account.
class _AccountStep extends StatelessWidget {
  const _AccountStep();

  @override
  Widget build(BuildContext context) {
    final sync = AppScope.of(context).sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        if (!sync.signedIn) return const AccountSection();
        // A failed first sync (offline) shows the form rather than spinning.
        final fetching =
            sync.status == SyncStatus.syncing || (sync.lastSync == null && sync.status != SyncStatus.error);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              fetching
                  ? 'Connecté (${sync.email ?? 'compte Bobine'}). Récupération de tes sources…'
                  : 'Connecté (${sync.email ?? 'compte Bobine'}). Ce compte n’a pas encore de source : ajoute ta '
                        'playlist, elle sera synchronisée avec tes autres appareils.',
              style: TextStyle(color: AppColors.textSoft, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 14),
            if (fetching)
              const Center(child: CircularProgressIndicator())
            else
              _Panel(child: SourceForm(onSaved: (_) {})),
          ],
        );
      },
    );
  }
}
