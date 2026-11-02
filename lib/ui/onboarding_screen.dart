import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'shell.dart';
import 'source_form.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -0.8),
            radius: 1.4,
            colors: [Color(0xFF2A1F0E), AppColors.bg],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  LumenMark(size: 52),
                  SizedBox(width: 16),
                  Text('Lumen', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                ]),
                const SizedBox(height: 26),
                const Text('Bienvenue 👋',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Ajoute ton abonnement Xtream Codes ou une playlist M3U. '
                  'Les chaînes, films, séries et le guide TV seront importés automatiquement.',
                  style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SourceForm(onSaved: (_) {}),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Lumen est un lecteur : il ne fournit aucun contenu. Tes identifiants restent sur cet ordinateur.',
                  style: TextStyle(color: AppColors.faint, fontSize: 12),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
