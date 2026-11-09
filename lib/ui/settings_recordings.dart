import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'launch.dart';
import 'settings_screen.dart';

/// Réglages → Enregistrements: folder, planned and finished recordings.
class RecordingsSection extends StatelessWidget {
  const RecordingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // Recordings of a locked channel stay out while the code is required.
    final list = [
      for (final r in s.repo.recordings())
        if (!s.repo.isLocked(r.sourceId, ContentKind.live, r.channelExt)) r,
    ];
    return SettingsSection(
      title: 'Enregistrements',
      children: [
        SettingsOption(
          title: 'Dossier',
          subtitle:
              '${s.recordings.folder}\nUn enregistrement utilise une 2e connexion de ton abonnement : '
              'si ton fournisseur n\'en autorise qu\'une, il ne peut pas tourner pendant que tu regardes.',
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final dir = await getDirectoryPath(confirmButtonText: 'Choisir');
                  if (dir != null) s.settings.update((x) => x.recordingsDir = dir);
                },
                child: const Text('Changer'),
              ),
              if (s.settings.recordingsDir != null)
                TextButton(
                  onPressed: () => s.settings.update((x) => x.recordingsDir = null),
                  child: const Text('Par défaut'),
                ),
            ],
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'Aucun enregistrement. Dans le guide ou en Live TV, choisis une émission puis « Enregistrer ».',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        for (final r in list) _RecordingTile(recording: r),
      ],
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.recording});
  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final r = recording;
    final (label, color) = switch (r.status) {
      RecordingStatus.scheduled => ('Prévu', AppColors.textSoft),
      RecordingStatus.recording => ('En cours', AppColors.live),
      RecordingStatus.done => ('Terminé', AppColors.success),
      RecordingStatus.failed => ('Échec', AppColors.live),
      RecordingStatus.cancelled => ('Annulé', AppColors.muted),
    };
    final when = '${formatDay(r.start)} ${formatClock(r.start)} – ${formatClock(r.stop)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            r.status == RecordingStatus.recording ? Icons.fiber_manual_record_rounded : Icons.videocam_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    r.channelName,
                    when,
                    label,
                    if (r.size != null && r.size! > 0) formatBytes(r.size!),
                    if (r.error != null) r.error!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: r.status == RecordingStatus.failed ? AppColors.live : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (r.status == RecordingStatus.done)
            IconButton(
              tooltip: 'Regarder',
              onPressed: () => Launch.recording(context, r),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          if (r.status == RecordingStatus.done && r.path != null && Platform.isWindows)
            IconButton(
              tooltip: 'Afficher dans le dossier',
              onPressed: () => Process.run('explorer.exe', ['/select,', r.path!]),
              icon: const Icon(Icons.folder_open_rounded),
            ),
          if (r.status == RecordingStatus.scheduled || r.status == RecordingStatus.recording)
            IconButton(
              tooltip: r.status == RecordingStatus.recording ? 'Arrêter' : 'Annuler',
              onPressed: () => s.recordings.stop(r.id),
              icon: Icon(r.status == RecordingStatus.recording ? Icons.stop_rounded : Icons.close_rounded),
            )
          else
            IconButton(
              tooltip: 'Supprimer (et le fichier)',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Supprimer cet enregistrement ?'),
                    content: Text('« ${r.title} » et son fichier seront supprimés.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
                    ],
                  ),
                );
                if (ok == true) await s.recordings.delete(r.id);
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
    );
  }
}

/// Réglages → Rappels: upcoming reminders of the profile.
class RemindersSection extends StatelessWidget {
  const RemindersSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final list = s.repo.reminders();
    return SettingsSection(
      title: 'Rappels',
      children: [
        SettingsOption(
          title: 'Prévenir avant le début',
          subtitle: "Un message apparaît dans Bobine (l'app doit être ouverte).",
          child: SettingsSegments<int>(
            value: s.settings.reminderLeadMinutes,
            options: const {0: "À l'heure", 2: '2 min', 5: '5 min', 10: '10 min'},
            onChanged: (v) => s.settings.update((x) => x.reminderLeadMinutes = v),
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'Aucun rappel. Dans le guide, choisis une émission à venir puis « Me le rappeler ».',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        for (final r in list)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            leading: Icon(Icons.notifications_active_outlined, color: AppColors.accent),
            title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${r.channelName} · ${formatDay(r.start)} ${formatClock(r.start)}',
              style: TextStyle(color: AppColors.muted),
            ),
            trailing: IconButton(
              tooltip: 'Retirer',
              onPressed: () {
                s.repo.deleteReminder(r.id);
                s.library.userChanged();
              },
              icon: const Icon(Icons.close_rounded),
            ),
          ),
      ],
    );
  }
}
