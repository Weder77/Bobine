import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/net.dart';
import '../core/theme.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
import '../services.dart';

/// Add / edit form for an Xtream Codes account or an M3U playlist.
class SourceForm extends StatefulWidget {
  const SourceForm({super.key, this.initial, required this.onSaved, this.onCancel});
  final Source? initial;
  final ValueChanged<int> onSaved;
  final VoidCallback? onCancel;

  @override
  State<SourceForm> createState() => _SourceFormState();
}

class _SourceFormState extends State<SourceForm> {
  late SourceType _type;
  final _name = TextEditingController();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _m3u = TextEditingController();
  final _epg = TextEditingController();
  final _ua = TextEditingController();
  String _liveFormat = 'ts';
  int _epgOffset = 0; // minutes
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _info;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _type = s?.type ?? SourceType.xtream;
    if (s != null) {
      _name.text = s.name;
      if (s.isXtream) {
        _server.text = s.url;
        _user.text = s.username ?? '';
        _pass.text = s.password ?? '';
      } else {
        _m3u.text = s.url;
      }
      _epg.text = s.epgUrl ?? '';
      _ua.text = s.userAgent ?? '';
      _liveFormat = s.liveFormat;
      _epgOffset = s.epgOffsetMinutes;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _server, _user, _pass, _m3u, _epg, _ua]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pasting a "get.php?username=…&password=…" link fills the Xtream fields.
  void _onServerChanged(String v) {
    final creds = XtreamCredentials.tryParse(v);
    if (creds != null) {
      _server.text = creds.server;
      _user.text = creds.username;
      _pass.text = creds.password;
      setState(() => _info = 'Lien détecté : identifiants remplis automatiquement.');
    }
  }

  void _onM3uChanged(String v) {
    final creds = XtreamCredentials.tryParse(v);
    if (creds != null && v.contains('get.php')) {
      setState(() => _info =
          'Ce lien vient d\'un serveur Xtream : l\'onglet « Xtream Codes » donne accès aux films, séries et au guide TV.');
    }
  }

  Future<void> _pickFile() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Playlists', extensions: ['m3u', 'm3u8', 'txt']),
    ]);
    if (file != null) {
      _m3u.text = file.path;
      if (_name.text.isEmpty) _name.text = file.name.replaceAll(RegExp(r'\.(m3u8?|txt)$'), '');
    }
  }

  String? _validate() {
    if (_type == SourceType.xtream) {
      if (_server.text.trim().isEmpty) return "Indique l'adresse du serveur.";
      if (_user.text.trim().isEmpty || _pass.text.isEmpty) return 'Identifiant et mot de passe requis.';
    } else if (_m3u.text.trim().isEmpty) {
      return "Indique l'URL ou le fichier de la playlist.";
    }
    return null;
  }

  Future<void> _test() async {
    final err = _validate();
    if (err != null) return setState(() => _error = err);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_type == SourceType.xtream) {
        final api = XtreamApi(
          baseUrl: _server.text,
          username: _user.text.trim(),
          password: _pass.text,
          userAgent: _ua.text.trim(),
        );
        try {
          final info = await api.authenticate();
          final exp = info['exp_date'] as int?;
          final parts = [
            'Compte actif',
            if (exp != null && exp > 0)
              'expire le ${formatDate(DateTime.fromMillisecondsSinceEpoch(exp * 1000))}'
            else
              "pas de date d'expiration",
            if (info['max_connections'] != null) '${info['max_connections']} connexion(s) max',
            if (info['is_trial'] == true) 'essai',
          ];
          setState(() => _info = '✓ ${parts.join(' · ')}');
        } finally {
          api.close();
        }
      } else {
        final loc = _m3u.text.trim();
        if (!loc.startsWith('http')) {
          setState(() => _info = '✓ Fichier local : il sera lu à l\'enregistrement.');
        } else {
          final client = createHttpClient();
          try {
            final res = await openGet(client, Uri.parse(loc), userAgent: _ua.text.trim());
            final head = await gunzipIfNeeded(res)
                .transform(const Utf8Decoder(allowMalformed: true))
                .join()
                .timeout(const Duration(seconds: 60));
            final n = '#EXTINF'.allMatches(head).length;
            if (n == 0 && !head.trimLeft().startsWith('#EXTM3U')) {
              throw NetException("Le fichier reçu n'est pas une playlist M3U.");
            }
            setState(() => _info = '✓ Playlist valide : ${formatCount(n)} entrées.');
          } finally {
            client.close(force: true);
          }
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) return setState(() => _error = err);
    final s = AppScope.of(context);
    final isX = _type == SourceType.xtream;
    var name = _name.text.trim();
    if (name.isEmpty) {
      final host = Uri.tryParse(isX ? (_server.text.contains('://') ? _server.text : 'http://${_server.text}') : _m3u.text)?.host;
      name = (host == null || host.isEmpty) ? (isX ? 'Mon IPTV' : 'Ma playlist') : host;
    }
    final url = isX ? _server.text.trim() : _m3u.text.trim();
    int id;
    if (_editing) {
      id = widget.initial!.id;
      s.repo.updateSource(id,
          name: name,
          url: url,
          username: isX ? _user.text.trim() : null,
          password: isX ? _pass.text : null,
          epgUrl: _epg.text,
          userAgent: _ua.text,
          liveFormat: _liveFormat,
          epgOffset: _epgOffset);
      s.library.contentChanged();
    } else {
      id = s.repo.insertSource(
          name: name,
          type: _type,
          url: url,
          username: isX ? _user.text.trim() : null,
          password: isX ? _pass.text : null,
          epgUrl: _epg.text,
          userAgent: _ua.text,
          liveFormat: _liveFormat,
          epgOffset: _epgOffset);
      s.selectSource(id);
    }
    final source = s.repo.source(id)!;
    unawaited(s.refresh(source).catchError((Object _) {}));
    widget.onSaved(id);
  }

  static String _offsetLabel(int minutes) {
    if (minutes == 0) return 'Aucun';
    final sign = minutes > 0 ? '+' : '−';
    final m = minutes.abs();
    final h = m ~/ 60, r = m % 60;
    return '$sign${h > 0 ? '$h h' : ''}${r > 0 ? ' ${r.toString().padLeft(h > 0 ? 2 : 1, '0')} min' : ''}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final isX = _type == SourceType.xtream;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (!_editing)
        SegmentedButton<SourceType>(
          segments: const [
            ButtonSegment(value: SourceType.xtream, icon: Icon(Icons.dns_rounded), label: Text('Xtream Codes')),
            ButtonSegment(value: SourceType.m3u, icon: Icon(Icons.playlist_play_rounded), label: Text('Playlist M3U')),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            _type = v.first;
            _error = null;
            _info = null;
          }),
        ),
      const SizedBox(height: 18),
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Nom (facultatif)', hintText: 'Ex. : Mon abonnement'),
      ),
      const SizedBox(height: 12),
      if (isX) ...[
        TextField(
          controller: _server,
          onChanged: _onServerChanged,
          decoration: const InputDecoration(
            labelText: 'Serveur',
            hintText: 'http://exemple.com:8080  (ou colle un lien get.php)',
            prefixIcon: Icon(Icons.public, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'Identifiant', prefixIcon: Icon(Icons.person_outline, size: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ),
        ]),
      ] else
        Row(children: [
          Expanded(
            child: TextField(
              controller: _m3u,
              onChanged: _onM3uChanged,
              decoration: const InputDecoration(
                labelText: 'URL ou fichier de la playlist',
                hintText: 'https://… .m3u / .m3u8',
                prefixIcon: Icon(Icons.link, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.folder_open), label: const Text('Parcourir')),
        ]),
      const SizedBox(height: 6),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Options avancées', style: TextStyle(fontSize: 14, color: AppColors.muted)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            TextField(
              controller: _epg,
              decoration: InputDecoration(
                labelText: 'URL du guide TV (XMLTV)',
                hintText: isX ? 'Automatique avec Xtream (laisser vide)' : 'Détectée dans la playlist si disponible',
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ua,
                  decoration: const InputDecoration(
                    labelText: 'User-Agent',
                    hintText: 'Laisser vide sauf si le fournisseur en exige un',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Préréglages',
                icon: const Icon(Icons.tune),
                onSelected: (v) => setState(() => _ua.text = v),
                itemBuilder: (_) => [
                  for (final e in kUserAgentPresets.entries) PopupMenuItem(value: e.value, child: Text(e.key)),
                ],
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              const Expanded(
                child: Text(
                  'Décalage du guide TV\n'
                  'À ajuster si les programmes affichés sont en avance ou en retard.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
              IconButton.outlined(
                tooltip: '-30 min',
                onPressed: _epgOffset <= -720 ? null : () => setState(() => _epgOffset -= 30),
                icon: const Icon(Icons.remove, size: 18),
              ),
              SizedBox(
                width: 96,
                child: Text(_offsetLabel(_epgOffset),
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton.outlined(
                tooltip: '+30 min',
                onPressed: _epgOffset >= 720 ? null : () => setState(() => _epgOffset += 30),
                icon: const Icon(Icons.add, size: 18),
              ),
            ]),
            if (isX) ...[
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(
                  child: Text('Format des chaînes en direct',
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ts', label: Text('MPEG-TS (conseillé)')),
                    ButtonSegment(value: 'm3u8', label: Text('HLS')),
                  ],
                  selected: {_liveFormat},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _liveFormat = v.first),
                ),
              ]),
            ],
          ],
        ),
      ),
      if (_error != null) _Message(_error!, error: true),
      if (_info != null && _error == null) _Message(_info!),
      const SizedBox(height: 14),
      Row(children: [
        if (widget.onCancel != null)
          TextButton(onPressed: widget.onCancel, child: const Text('Annuler')),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _busy ? null : _test,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.network_check),
          label: const Text('Tester'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_editing ? 'Enregistrer' : 'Ajouter et importer'),
        ),
      ]),
    ]);
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (error ? AppColors.live : AppColors.success).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(error ? Icons.error_outline : Icons.info_outline,
              size: 18, color: error ? AppColors.live : AppColors.success),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

/// Opens the form in a dialog.
Future<void> showSourceDialog(BuildContext context, {Source? initial}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(initial == null ? 'Ajouter une source' : 'Modifier « ${initial.name} »',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            SourceForm(
              initial: initial,
              onSaved: (_) => Navigator.of(ctx).pop(),
              onCancel: () => Navigator.of(ctx).pop(),
            ),
          ]),
        ),
      ),
    ),
  );
}
