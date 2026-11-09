import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../cast/cast_device.dart';
import '../cast/cast_media.dart';
import '../cast/cast_service.dart';
import '../cast/cast_session.dart';
import '../core/theme.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/net_image.dart';
import 'player_chrome.dart';

/// What the TV is doing, in a few words.
String castStateLabel(CastService c) {
  if (c.connecting) return 'Connexion à la télé…';
  final error = c.error;
  if (error != null) return error;
  return switch (c.status.state) {
    RemoteState.loading => 'Ouverture du flux sur la télé…',
    RemoteState.buffering => 'Mise en mémoire sur la télé…',
    RemoteState.playing => 'Lecture sur la télé',
    RemoteState.paused => 'En pause sur la télé',
    RemoteState.ended => 'Terminé',
    RemoteState.idle => 'Lecture arrêtée sur la télé',
    RemoteState.error => 'Erreur de lecture',
  };
}

IconData castDeviceIcon(CastDevice d) => d.protocol == CastProtocol.chromecast ? Icons.cast_rounded : Icons.tv_rounded;

// ------------------------------------------------------------------ panel

/// "Caster": devices of the network, the one in use, and how to stop.
class CastPanel extends StatefulWidget {
  const CastPanel({super.key, required this.cast, required this.onPick, required this.onStop, required this.onClose});
  final CastService cast;
  final ValueChanged<CastDevice> onPick;

  /// Stops casting and plays here again.
  final VoidCallback onStop;
  final VoidCallback onClose;

  @override
  State<CastPanel> createState() => _CastPanelState();
}

class _CastPanelState extends State<CastPanel> {
  @override
  void initState() {
    super.initState();
    // Deferred: the search notifies listeners, not allowed while building.
    scheduleMicrotask(widget.cast.scanIfStale);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cast;
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.devices, c.scanning]),
      builder: (context, _) {
        final current = c.device;
        final others = c.devices.value.where((d) => d != current).toList();
        final scanning = c.scanning.value;
        return PlayerSidePanel(
          right: true,
          width: 420,
          kicker: 'Sur la télé ou un autre écran',
          title: 'Caster',
          onClose: widget.onClose,
          footer: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Text(
              'La télé doit être allumée et sur le même réseau que cet ordinateur. Fonctionne avec '
              'Chromecast, Google TV, Android TV et les télés DLNA (Samsung, LG, Sony, Philips…). '
              'Si Windows demande d’autoriser Bobine sur le réseau, accepte : c’est par là que la télé reçoit la vidéo.',
              style: const TextStyle(fontSize: 12.5, height: 1.45, color: DarkColors.faint),
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            children: [
              if (current != null) ...[
                _title('En cours'),
                _DeviceRow(device: current, selected: true, detail: castStateLabel(c), onTap: widget.onClose),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: widget.onStop,
                    icon: const Icon(Icons.cancel_presentation_rounded, size: 18),
                    label: const Text('Arrêter et regarder ici'),
                  ),
                ),
                const SizedBox(height: 26),
              ],
              Row(
                children: [
                  Expanded(child: _title(current == null ? 'Appareils' : 'Autres appareils')),
                  if (scanning)
                    const Padding(
                      padding: EdgeInsets.only(right: 12, bottom: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: DarkColors.accent),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextButton.icon(
                        onPressed: () => c.scan(),
                        style: TextButton.styleFrom(
                          foregroundColor: DarkColors.textSoft,
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Actualiser', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                ],
              ),
              for (final d in others)
                _DeviceRow(device: d, selected: false, detail: d.kindLabel, onTap: () => widget.onPick(d)),
              if (others.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  child: Text(
                    scanning ? 'Recherche sur le réseau…' : 'Aucun appareil trouvé.',
                    style: const TextStyle(fontSize: 14, color: DarkColors.muted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t.toUpperCase(), style: darkLabel(color: DarkColors.faint, size: 12)),
  );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.selected, required this.detail, required this.onTap});
  final CastDevice device;
  final bool selected;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: onTap,
    focusRingRadius: 8,
    builder: (context, hover) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: hover ? const Color(0x0FFFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.cast_connected_rounded : castDeviceIcon(device),
              size: 22,
              color: selected ? DarkColors.accent : DarkColors.textSoft,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: selected ? DarkColors.text : DarkColors.textSoft,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: darkMono(12, height: 1.3, color: selected ? DarkColors.accent : DarkColors.faint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------ full screen

/// Takes the place of the video while the TV plays it.
class CastRemoteView extends StatelessWidget {
  const CastRemoteView({
    super.key,
    required this.cast,
    required this.image,
    required this.onRetry,
    required this.onStop,
  });
  final CastService cast;
  final String? image;

  /// Tries again, optionally switching through this computer / direct.
  final void Function({bool? viaRelay}) onRetry;
  final VoidCallback onStop;

  /// Switches the way the stream reaches the TV. Direct mode gives the TV
  /// the provider's address: when the account's identifiers are in it, the
  /// user is told what that means and decides.
  Future<void> _switchMode(BuildContext context) async {
    final toDirect = cast.viaRelay;
    final item = cast.item.value;
    if (toDirect && item != null && CastService.directRevealsCredentials(item)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Diffuser en direct ?'),
          content: SizedBox(
            width: 480,
            child: Text(
              'En direct, la télé va chercher le flux elle-même : elle reçoit l’adresse de ton fournisseur, '
              'identifiant et mot de passe compris. Ils circulent en clair sur ton réseau, et la télé les donne '
              'à tout appareil du réseau qui lui demande ce qu’elle lit.\n\n'
              'À réserver à ton propre réseau. Ce choix vaut pour « ${cast.device?.name ?? 'cette télé'} », '
              'jusqu’à la fermeture de Bobine.',
              style: const TextStyle(height: 1.5),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Diffuser en direct')),
          ],
        ),
      );
      if (ok != true) return;
    }
    onRetry(viaRelay: !toDirect);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cast,
    builder: (context, _) {
      final device = cast.device;
      final size = MediaQuery.sizeOf(context);
      final nameSize = math.min(size.width * 0.06, size.height * 0.1).clamp(36.0, 88.0);
      final state = cast.status.state;
      final failed = cast.error != null;
      final stopped = !failed && (state == RemoteState.idle || state == RemoteState.ended);
      final busy = cast.loading && !failed;
      final local = isLocalMedia(cast.item.value?.url ?? '');
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (image != null)
            Opacity(
              opacity: 0.28,
              child: NetImage(image, fit: BoxFit.cover, placeholder: const SizedBox.shrink()),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(radius: 1.1, colors: [Color(0x99000000), Color(0xF2000000)]),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    failed ? Icons.error_outline_rounded : Icons.cast_connected_rounded,
                    size: 46,
                    color: DarkColors.accent,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'EN DIFFUSION SUR',
                    style: darkLabel(color: DarkColors.accent, size: 13).copyWith(letterSpacing: 13 * 0.18),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    (device?.name ?? 'la télé').toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: darkPoster(nameSize),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: DarkColors.textSoft),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          castStateLabel(cast),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            color: failed ? DarkColors.text : DarkColors.textSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (failed || stopped) ...[
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: () => onRetry(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(failed ? 'Réessayer' : 'Relancer'),
                        ),
                        if (failed && !local)
                          OutlinedButton(
                            onPressed: () => _switchMode(context),
                            child: Text(cast.viaRelay ? 'Essayer en direct' : 'Essayer via cet ordinateur'),
                          ),
                      ],
                    ),
                    if (failed && device?.protocol == CastProtocol.chromecast && _tsLive(cast)) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Chromecast ne lit pas les flux MPEG-TS : essaie une télé DLNA, ou le format HLS dans '
                        'les options avancées de la source.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, height: 1.45, color: DarkColors.faint),
                      ),
                    ],
                  ],
                  const SizedBox(height: 26),
                  TextButton.icon(
                    onPressed: onStop,
                    style: TextButton.styleFrom(foregroundColor: DarkColors.textSoft),
                    icon: const Icon(Icons.laptop_rounded, size: 18),
                    label: const Text('Arrêter et regarder sur cet ordinateur'),
                  ),
                  if (cast.viaRelay && !failed) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Le flux passe par cet ordinateur : garde Bobine ouvert pendant la diffusion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: DarkColors.faint),
                    ),
                  ],
                  if (!cast.viaRelay && !failed && !local && _revealing(cast)) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'En direct : la télé reçoit l’adresse de ton fournisseur, identifiants compris.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: DarkColors.faint),
                    ),
                  ],
                  // The TV may refuse the stream while reporting that it
                  // plays: the other way to send it stays at hand.
                  if (!failed && !local && device != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => _switchMode(context),
                      style: TextButton.styleFrom(
                        foregroundColor: DarkColors.faint,
                        textStyle: const TextStyle(fontSize: 12.5, decoration: TextDecoration.underline),
                      ),
                      child: Text(
                        cast.viaRelay
                            ? 'La télé n’affiche pas la vidéo ? Essayer en direct'
                            : 'La télé n’affiche pas la vidéo ? Essayer via cet ordinateur',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  /// The TV is being given an address that holds the account's identifiers.
  static bool _revealing(CastService c) {
    final item = c.item.value;
    return item != null && CastService.directRevealsCredentials(item);
  }

  static bool _tsLive(CastService c) {
    final it = c.item.value;
    if (it == null || !it.isLive) return false;
    return !isHlsUrl(castUrl(it.url, CastProtocol.chromecast));
  }
}

// ------------------------------------------------------------ mini-player

/// Mini-player content while casting: artwork and where it plays.
class CastMiniView extends StatelessWidget {
  const CastMiniView({super.key, required this.cast, required this.image});
  final CastService cast;
  final String? image;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cast,
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (image != null)
          Opacity(
            opacity: 0.35,
            child: NetImage(image, fit: BoxFit.cover, decodeWidth: 448, placeholder: const SizedBox.shrink()),
          ),
        Positioned(
          left: 14,
          // Leaves room for the buttons of the mini-player.
          right: 130,
          top: 16,
          child: Row(
            children: [
              const Icon(Icons.cast_connected_rounded, size: 16, color: DarkColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cast.device?.name ?? 'Télé',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: darkMono(12, color: DarkColors.accent, height: 1),
                ),
              ),
            ],
          ),
        ),
        if (cast.error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                cast.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: DarkColors.textSoft),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Cast button of the player's top bar (vermilion while casting).
class CastButton extends StatelessWidget {
  const CastButton({super.key, required this.cast, required this.onTap});
  final CastService cast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cast,
    builder: (context, _) {
      final on = cast.active;
      return Tooltip(
        message: on ? 'En diffusion sur ${cast.device!.name} (T)' : 'Caster sur la télé (T)',
        child: IconButton(
          onPressed: onTap,
          iconSize: 22,
          style: IconButton.styleFrom(
            foregroundColor: on ? DarkColors.accent : DarkColors.text,
            fixedSize: const Size(44, 44),
            minimumSize: const Size(44, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ).copyWith(overlayColor: const WidgetStatePropertyAll(Color(0x24FFFFFF))),
          icon: Icon(on ? Icons.cast_connected_rounded : Icons.cast_rounded),
        ),
      );
    },
  );
}
