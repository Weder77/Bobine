import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/open_url.dart';
import '../core/theme.dart';
import '../core/version.dart';
import '../features/backup.dart';
import '../features/updater.dart';
import '../services.dart';
import 'diagnostic_screen.dart';
import 'settings_screen.dart';
import 'widgets/markdown.dart';

/// Réglages → Sauvegarde et diagnostic.
class BackupSection extends StatelessWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Sauvegarde et diagnostic',
      children: [
        SettingsOption(
          title: 'Sauvegarder mes données',
          subtitle:
              'Profils, favoris, reprises, catégories rangées, chaînes masquées, rappels et réglages, '
              'dans un fichier à garder ou à ouvrir sur un autre PC.',
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _export(context),
                icon: const Icon(Icons.save_alt_rounded, size: 20),
                label: const Text('Exporter…'),
              ),
              OutlinedButton.icon(
                onPressed: () => _restore(context),
                icon: const Icon(Icons.settings_backup_restore_rounded, size: 20),
                label: const Text('Restaurer…'),
              ),
            ],
          ),
        ),
        SettingsOption(
          title: 'Diagnostic',
          subtitle: 'Versions, stockage, test de connexion des sources et journal, avec un rapport à copier.',
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(DiagnosticScreen.route()),
            icon: const Icon(Icons.monitor_heart_outlined, size: 20),
            label: const Text('Ouvrir'),
          ),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final s = AppScope.of(context);
    final credentials = await showDialog<bool>(context: context, builder: (_) => const _ExportDialog());
    if (credentials == null || !context.mounted) return;
    final loc = await getSaveLocation(
      suggestedName: s.backup.suggestedFileName(),
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Sauvegarde Bobine', extensions: ['json']),
      ],
    );
    if (loc == null) return;
    final path = loc.path.toLowerCase().endsWith('.json') ? loc.path : '${loc.path}.json';
    try {
      await s.backup.exportTo(path, credentials: credentials);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sauvegarde enregistrée : $path')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec de la sauvegarde : $e')));
      }
    }
  }

  Future<void> _restore(BuildContext context) async {
    final s = AppScope.of(context);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Sauvegarde Bobine', extensions: ['json']),
      ],
    );
    if (file == null || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restaurer la sauvegarde ?', style: displayStyle(22)),
        content: const SizedBox(
          width: 460,
          child: Text(
            'Les données du fichier sont ajoutées à celles de cet ordinateur (rien n’est effacé). '
            'Les réglages du fichier remplacent les réglages actuels.',
            style: TextStyle(height: 1.5, color: AppColors.textSoft),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurer')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final report = await s.backup.restoreFrom(file.path);
      s.afterRestore(report);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(duration: const Duration(seconds: 8), content: Text('Restauré : $report')));
      }
    } on BackupException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _credentials = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Exporter mes données', style: displayStyle(22)),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sans les identifiants, le fichier retrouve tes sources si elles existent déjà sur l’autre PC '
            '(même serveur, même compte).',
            style: TextStyle(height: 1.5, color: AppColors.textSoft),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _credentials,
            onChanged: (v) => setState(() => _credentials = v ?? false),
            title: const Text('Inclure les sources avec leurs identifiants'),
            subtitle: const Text(
              'Ainsi que le code parental et la clé TMDB. Ils seront écrits en clair dans le fichier : '
              'garde-le en lieu sûr.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: () => Navigator.pop(context, _credentials), child: const Text('Choisir le fichier…')),
    ],
  );
}

/// Réglages → À propos et mises à jour.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final u = s.updates;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final info = u.available;
        final busy = u.stage == UpdateStage.checking || u.stage == UpdateStage.downloading;
        final status = switch (u.stage) {
          UpdateStage.checking => 'Recherche…',
          UpdateStage.upToDate => 'Bobine est à jour.',
          UpdateStage.available => 'Bobine ${info!.version} est disponible.',
          UpdateStage.downloading => 'Téléchargement… ${(u.progress * 100).round()} %',
          UpdateStage.ready => 'Prêt : Bobine va se fermer, s’installer puis se rouvrir.',
          UpdateStage.error => u.error ?? 'Erreur',
          UpdateStage.idle => null,
        };
        return SettingsSection(
          title: 'À propos et mises à jour',
          children: [
            SettingsOption(
              title: 'Bobine $kAppVersion',
              subtitle:
                  'Lecteur IPTV basé sur libmpv (FFmpeg) via media_kit. Toutes les données (sources, favoris, '
                  'progression) restent sur cet ordinateur.',
              child: OutlinedButton(
                onPressed: busy ? null : () => u.check(),
                child: const Text('Rechercher une mise à jour'),
              ),
            ),
            if (status != null)
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: switch (u.stage) {
                          UpdateStage.error => AppColors.live,
                          UpdateStage.available || UpdateStage.ready => AppColors.accent,
                          _ => AppColors.textSoft,
                        },
                      ),
                    ),
                    if (u.stage == UpdateStage.downloading) ...[
                      const SizedBox(height: 10),
                      SizedBox(width: 360, child: LinearProgressIndicator(value: u.progress)),
                    ],
                    if (info != null && info.notes != null && info.notes!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 280),
                        child: SingleChildScrollView(
                          child: MarkdownText(
                            info.notes!,
                            style: const TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
                          ),
                        ),
                      ),
                    ],
                    if (info != null && (u.stage == UpdateStage.available || u.stage == UpdateStage.ready)) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (u.canInstall && u.stage == UpdateStage.available)
                            FilledButton.icon(
                              onPressed: u.download,
                              icon: const Icon(Icons.download_rounded, size: 20),
                              label: const Text('Télécharger et installer'),
                            ),
                          if (u.stage == UpdateStage.ready)
                            FilledButton.icon(
                              onPressed: () => u.installAndRestart(beforeExit: () async => s.tracker.flush()),
                              icon: const Icon(Icons.restart_alt_rounded, size: 20),
                              label: const Text('Installer et redémarrer'),
                            ),
                          OutlinedButton(
                            onPressed: () => openExternal(info.page),
                            child: const Text('Voir la version'),
                          ),
                          if (u.stage == UpdateStage.available)
                            TextButton(onPressed: u.skip, child: const Text('Ignorer cette version')),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            SettingsSwitch(
              title: 'Vérifier les mises à jour au démarrage',
              subtitle: 'Une fois par jour au plus, sur les versions publiées dans GitHub.',
              value: s.settings.checkUpdates,
              onChanged: (v) => s.settings.update((x) => x.checkUpdates = v),
            ),
          ],
        );
      },
    );
  }
}
