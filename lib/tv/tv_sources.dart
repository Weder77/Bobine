import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/text.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
import '../services.dart';
import '../ui/widgets/pin_dialog.dart';
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

/// What a source holds: "1 234 chaînes · 3 210 films · 512 séries".
String tvSourceCounts({required int live, required int movies, required int series}) {
  String n(int count, String one, String many) => '${formatCount(count)} ${count > 1 ? many : one}';
  final parts = [
    if (live > 0) n(live, 'chaîne', 'chaînes'),
    if (movies > 0) n(movies, 'film', 'films'),
    if (series > 0) n(series, 'série', 'séries'),
  ];
  return parts.isEmpty ? 'Vide pour l’instant' : parts.join(' · ');
}

/// Where a source stands: being refreshed ([stage]), in error, or when it
/// was last updated; true for an error.
(String, bool) tvSourceState({required DateTime now, String? stage, String? error, DateTime? updated}) {
  if (stage != null) return ('Actualisation : $stage', false);
  if (error != null) return ('Erreur : $error', true);
  if (updated == null) return ('Jamais mise à jour', false);
  return ('Connectée · mise à jour il y a ${tvDuration(now.difference(updated))}', false);
}

/// Source on the TV: the sources of this TV and the two ways to add one,
/// then the few fields an IPTV provider gives. OK on a source: use it,
/// refresh it or delete it.
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

  /// The source whose page is shown (use, refresh, delete), and whether its
  /// deletion is being confirmed.
  int? _detail;
  bool _confirmDelete = false;
  AppServices? _s;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (s != _s) {
      // A refresh's progress, as it goes.
      _s?.imports.removeListener(_changed);
      _s = s..imports.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _s?.imports.removeListener(_changed);
    _c.dispose();
    for (final t in [_server, _user, _pass, _m3u]) {
      t.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String get _first {
    if (_detail != null) return _confirmDelete ? 'd-delete-no' : 'd-refresh';
    return switch (_form) {
      null => _activeId ?? 'add-xtream',
      SourceType.xtream => 'f-server',
      SourceType.m3u => 'f-m3u',
    };
  }

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

  void _back() {
    if (_confirmDelete) return _askDelete(false);
    final detail = _detail;
    if (detail != null) {
      setState(() => _detail = null);
      return _c.focus('src-$detail');
    }
    _form == null ? widget.onBack() : _open(null);
  }

  void _openDetail(int id) {
    setState(() {
      _detail = id;
      _confirmDelete = false;
    });
    _c.focus(_first);
  }

  void _askDelete(bool ask) {
    setState(() => _confirmDelete = ask);
    _c.focus(ask ? 'd-delete-no' : 'd-delete');
  }

  Future<void> _delete(AppServices s, Source src) async {
    // Its locks and hidden categories go with it: not without the code.
    if (!await confirmParent(context, title: 'Supprimer la source') || !mounted) return;
    await s.deleteSource(src.id);
    if (!mounted) return;
    setState(() {
      _detail = null;
      _confirmDelete = false;
    });
    // None left: the first launch's welcome is under this page.
    if (s.repo.sources().isEmpty) return widget.onBack();
    _c.focus(_first);
  }

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
            onOk: () => _openDetail(src.id),
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

  /// A source's page: what it holds, where it stands, and what to do with it.
  List<Widget> _detailView(AppServices s, Source src) {
    final active = src.id == s.activeSource?.id;
    final stage = s.imports.status(src.id)?.label;
    final (state, error) = tvSourceState(
      now: DateTime.now(),
      stage: stage,
      error: src.lastError,
      updated: src.contentUpdatedAt,
    );
    return [
      Text(
        tvSourceCounts(
          live: s.repo.count(src.id, ContentKind.live),
          movies: s.repo.count(src.id, ContentKind.movie),
          series: s.repo.count(src.id, ContentKind.series),
        ),
        style: tvText(28, color: TvColors.soft, height: 1.3),
      ),
      const SizedBox(height: 12),
      TvFormMessage(state, error: error),
      const SizedBox(height: 8),
      if (_confirmDelete) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Text(
            'Supprimer « ${src.name} » ? Ses chaînes, ses favoris et tes reprises disparaissent de cette télé.',
            style: tvText(30, weight: FontWeight.w600, height: 1.35),
          ),
        ),
        TvChoice(id: 'd-delete-no', icon: Icons.close_rounded, title: 'Annuler', onOk: () => _askDelete(false)),
        TvChoice(
          id: 'd-delete-yes',
          icon: Icons.delete_outline_rounded,
          title: 'Oui, supprimer la source',
          onOk: () => _delete(s, src),
        ),
      ] else ...[
        if (!active)
          TvChoice(
            id: 'd-use',
            icon: Icons.check_circle_outline_rounded,
            title: 'Utiliser cette source',
            text: 'Ses chaînes, ses films et ses séries à la place de ceux de la source actuelle.',
            onOk: () {
              s.selectSource(src.id);
              widget.onDone(src.id);
            },
          ),
        TvChoice(
          id: 'd-refresh',
          icon: Icons.refresh_rounded,
          title: stage == null ? 'Actualiser' : 'Actualisation en cours…',
          text: 'Recharge les chaînes, les films, les séries et le guide TV.',
          onOk: () {
            if (stage != null) return;
            unawaited(s.refresh(src).catchError((Object _) {}));
          },
        ),
        TvChoice(
          id: 'd-delete',
          icon: Icons.delete_outline_rounded,
          title: 'Supprimer la source',
          text: 'Elle disparaît de cette télé, et de tes autres appareils si tu es connecté à ton compte Bobine.',
          onOk: () => _askDelete(true),
        ),
      ],
    ];
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
            ? 'C’est la source utilisée. OK pour l’actualiser ou la supprimer.'
            : 'OK pour l’utiliser à la place de l’autre, l’actualiser ou la supprimer.',
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
    final detail = _detail == null ? null : s.repo.source(_detail!);
    if (_detail != null && detail == null) _detail = null;
    if (_c.id == null || !_c.isRegistered(_c.id!)) {
      // First frame, or the line focused went away: the first one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_c.id == null || !_c.isRegistered(_c.id!))) _c.focus(_first);
      });
    }
    if (detail != null) {
      return TvFormFrame(
        controller: _c,
        onBack: _back,
        title: detail.name,
        subtitle: detail.isXtream ? 'Abonnement Xtream Codes' : 'Playlist M3U',
        backLabel: _confirmDelete ? 'Annuler' : 'Source',
        side: TvFormHelp(
          title: detail.id == s.activeSource?.id ? 'Source utilisée' : 'Autre source',
          text:
              'Actualiser recharge tout depuis ton fournisseur, comme Bobine le fait seul de temps en temps. '
              'Supprimer enlève la source de cette télé ; tu pourras l’ajouter de nouveau.',
        ),
        children: _detailView(s, detail),
      );
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
