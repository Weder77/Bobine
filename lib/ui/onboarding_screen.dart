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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BobineMark(size: 44),
                      const SizedBox(width: 14),
                      Text('BOBINE', style: posterStyle(40).copyWith(letterSpacing: 6)),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Text('Bienvenue', style: displayStyle(44, weight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  const Text(
                    'Ajoute ton abonnement Xtream Codes ou une playlist M3U. '
                    'Les chaînes, films, séries et le guide TV seront importés automatiquement.',
                    style: TextStyle(color: AppColors.textSoft, fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SourceForm(onSaved: (_) {}),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Bobine est un lecteur : il ne fournit aucun contenu. Tes identifiants restent sur cet ordinateur.',
                    style: TextStyle(color: AppColors.faint, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
