import 'dart:async';

import 'package:flutter/material.dart';

import '../core/text.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
import '../services.dart';
import 'tv_focus.dart';
import 'tv_form.dart';
import 'tv_rows.dart';
import 'tv_theme.dart';

/// What is missing to add a source, or null.
String? tvSourceError({required bool xtream, String server = '', String user = '', String pass = '', String m3u = ''}) {
  if (xtream) {
    if (server.trim().isEmpty) return "Indique l'adresse du serveur.";
    if (user.trim().isEmpty || pass.isEmpty) return 'Identifiant et mot de passe requis.';
  } else if (m3u.trim().isEmpty) {
    return "Indique l'adresse de la playlist.";
  }
  return null;
}

/// The name a new source gets: the host of its address.
String tvSourceName({required bool xtream, required String location}) {
  final loc = location.trim();
  final host = Uri.tryParse(loc.contains('://') ? loc : 'http://$loc')?.host ?? '';
  if (host.isEmpty || !host.contains('.')) return xtream ? 'Mon IPTV' : 'Ma playlist';
  return host;
}

/// Source on the TV: the sources of this TV (OK uses one) and the two ways
/// to add one, then the few fields an IPTV provider gives.
class TvSourcesView extends StatefulWidget {
  const TvSourcesView({super.key, required this.onBack, required this.onDone, this.backLabel = 'Réglages'});

  final VoidCallback onBack;

  /// A source chosen or added (it is the one in use).
  final ValueChanged<int> onDone;
  final String backLabel;

  /// Réglages → Source.
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => TvSourcesView(onBack: () => Navigator.of(ctx).pop(), onDone: (_) => Navigator.of(ctx).pop()),
    ),
  );

  @override
  State<TvSourcesView> createState() => _TvSourcesViewState();
}

class _TvSourcesViewState extends State<TvSourcesView> {
  final _c = TvFocusController();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _m3u = TextEditingController();

  /// The form shown, or null for the list.
  SourceType? _form;
  String? _busy;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _c.fallback = () => _first;
  }

  @override
  void dispose() {
    _c.dispose();
    for (final t in [_server, _user, _pass, _m3u]) {
      t.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String get _first => switch (_form) {
    null => _activeId ?? 'add-xtream',
    SourceType.xtream => 'f-server',
    SourceType.m3u => 'f-m3u',
  };

  /// The source in use, the first stop of the list.
  String? get _activeId {
    final id = AppScope.of(context).activeSource?.id;
    return id == null ? null : 'src-$id';
  }

  void _open(SourceType? form) {
    setState(() {
      _form = form;
      _error = null;
      _info = null;
      _busy = null;
    });
    _c.focus(_first);
  }

  void _back() => _form == null ? widget.onBack() : _open(null);

  /// Pasting a "get.php?username=…&password=…" link fills the three fields.
  void _onServer(String v) {
    final creds = XtreamCredentials.tryParse(v);
    if (creds == null || !v.contains('password=')) return;
    _server.text = creds.server;
    _user.text = creds.username;
    _pass.text = creds.password;
    setState(() => _info = 'Lien détecté : identifiant et mot de passe remplis.');
  }

  Future<void> _save() async {
    var form = _form;
    if (form == null || _busy != null) return;
    // A provider's "get.php?username=…" link is an Xtream account: saved as
    // one, it gives the films, the series and the guide too.
    final creds = form == SourceType.m3u && _m3u.text.contains('get.php')
        ? XtreamCredentials.tryParse(_m3u.text)
        : null;
    if (creds != null) {
      form = SourceType.xtream;
      _server.text = creds.server;
      _user.text = creds.username;
      _pass.text = creds.password;
    }
    final xtream = form == SourceType.xtream;
    final err = tvSourceError(xtream: xtream, server: _server.text, user: _user.text, pass: _pass.text, m3u: _m3u.text);
    if (err != null) return setState(() => _error = err);
    setState(() {
      _busy = xtream ? 'Vérification de l’abonnement…' : 'Enregistrement…';
      _error = null;
      _info = null;
    });
    if (xtream) {
      final api = XtreamApi(baseUrl: _server.text.trim(), username: _user.text.trim(), password: _pass.text);
      try {
        await api.authenticate();
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = null;
            _error = redactCredentials(e.toString());
          });
        }
        return;
      } finally {
        api.close();
      }
    }
    if (!mounted) return;
    final s = AppScope.of(context);
    final url = xtream ? _server.text.trim() : _m3u.text.trim();
    final id = s.repo.insertSource(
      name: tvSourceName(xtream: xtream, location: url),
      type: form,
      url: url,
      username: xtream ? _user.text.trim() : null,
      password: xtream ? _pass.text : null,
    );
    s.selectSource(id);
    unawaited(s.refresh(s.repo.source(id)!).catchError((Object _) {}));
    widget.onDone(id);
  }

  Widget _list(AppServices s) {
    final active = s.activeSource?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final src in s.repo.sources())
          TvChoice(
            id: 'src-${src.id}',
            icon: src.isXtream ? Icons.dns_rounded : Icons.playlist_play_rounded,
            title: src.name,
            text: src.isXtream ? 'Xtream Codes' : 'Playlist M3U',
            trailing: src.id == active
                ? Text(
                    '● Utilisée',
                    style: tvText(24, weight: FontWeight.w600, height: 1, color: TvColors.ok),
                  )
                : null,
            onOk: () {
              s.selectSource(src.id);
              widget.onDone(src.id);
            },
          ),
        const SizedBox(height: 18),
        TvChoice(
          id: 'add-xtream',
          icon: Icons.add_rounded,
          title: 'Ajouter un abonnement Xtream Codes',
          text: 'Adresse du serveur, identifiant et mot de passe.',
          onOk: () => _open(SourceType.xtream),
        ),
        TvChoice(
          id: 'add-m3u',
          icon: Icons.add_rounded,
          title: 'Ajouter une playlist M3U',
          text: 'Le lien de la playlist donné par ton fournisseur.',
          onOk: () => _open(SourceType.m3u),
        ),
      ],
    );
  }

  List<Widget> _fields() => [
    if (_form == SourceType.xtream) ...[
      TvTextField(
        id: 'f-server',
        label: 'Adresse du serveur',
        hint: 'http://exemple.com:8080',
        controller: _server,
        keyboard: TextInputType.url,
        onDone: _onServer,
      ),
      TvTextField(id: 'f-user', label: 'Identifiant', controller: _user),
      TvTextField(id: 'f-pass', label: 'Mot de passe', controller: _pass, obscure: true),
    ] else
      TvTextField(
        id: 'f-m3u',
        label: 'Adresse de la playlist',
        hint: 'http://exemple.com/playlist.m3u',
        controller: _m3u,
        keyboard: TextInputType.url,
      ),
    if (_busy != null)
      TvFormMessage(_busy!)
    else if (_error != null)
      TvFormMessage(_error!, error: true)
    else if (_info != null)
      TvFormMessage(_info!),
    TvButton(
      id: 'f-save',
      label: _busy == null ? 'Enregistrer' : 'Patiente…',
      icon: Icons.check_rounded,
      primary: true,
      onOk: _save,
    ),
  ];

  Widget? _help(AppServices s) {
    final id = _c.id;
    if (_form == SourceType.xtream) {
      return const TvFormHelp(
        title: 'Xtream Codes',
        text:
            'Les trois informations envoyées par ton fournisseur IPTV. Un lien « get.php » collé dans l’adresse '
            'remplit tout seul l’identifiant et le mot de passe.',
      );
    }
    if (_form == SourceType.m3u) {
      return const TvFormHelp(
        title: 'Playlist M3U',
        text: 'Le lien de ta playlist. Un abonnement Xtream Codes donne en plus les films, les séries et le guide TV.',
      );
    }
    if (id != null && id.startsWith('src-')) {
      final src = s.repo.source(int.tryParse(id.substring(4)) ?? -1);
      if (src == null) return null;
      final updated = src.contentUpdatedAt;
      return TvFormHelp(
        title: src.name,
        text: src.id == s.activeSource?.id
            ? 'C’est la source utilisée. Ses chaînes, films et séries sont ceux de Bobine.'
            : 'OK pour utiliser cette source à la place de l’autre.',
        extra: Text(
          [
            src.lastError == null ? 'Connectée' : 'Erreur : ${src.lastError}',
            if (updated != null) 'Mise à jour il y a ${tvDuration(DateTime.now().difference(updated))}',
          ].join('\n'),
          style: tvMono(22, height: 1.6, color: src.lastError == null ? TvColors.ok : TvColors.accent),
        ),
      );
    }
    return const TvFormHelp(
      title: 'Ajouter une source',
      text:
          'Bobine lit l’abonnement de ton fournisseur IPTV. Xtream Codes donne les chaînes, les films, les séries '
          'et le guide TV ; une playlist M3U, les chaînes.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (_c.id == null || !_c.isRegistered(_c.id!)) {
      // First frame, or the line focused went away: the first one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_c.id == null || !_c.isRegistered(_c.id!))) _c.focus(_first);
      });
    }
    return TvFormFrame(
      controller: _c,
      onBack: _back,
      title: switch (_form) {
        null => 'Source',
        SourceType.xtream => 'Xtream Codes',
        SourceType.m3u => 'Playlist M3U',
      },
      subtitle: _form == null
          ? 'D’où viennent les chaînes, les films et les séries.'
          : 'Les informations données par ton fournisseur IPTV.',
      backLabel: _form == null ? widget.backLabel : 'Source',
      side: _help(s),
      children: _form == null ? [_list(s)] : _fields(),
    );
  }
}
