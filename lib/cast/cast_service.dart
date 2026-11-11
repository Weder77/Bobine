import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/text.dart';
import '../player/player_service.dart';
import 'cast_device.dart';
import 'cast_media.dart';
import 'cast_session.dart';
import 'chromecast.dart';
import 'dlna.dart';
import 'mdns.dart';
import 'relay.dart';
import 'ssdp.dart';

/// Sends what is playing to a TV of the local network (Chromecast or DLNA)
/// and keeps the remote playback in sync for the player's controls.
///
/// One device at a time. While casting, the local player is stopped (the
/// IPTV account often allows a single connection) and the TV reads the
/// stream, through this computer by default (see [CastRelay]).
class CastService extends ChangeNotifier {
  CastService({
    this.describe,
    CastRelay? relay,
    this.sessionFactory,
    this.browsers,
    this.loadTimeout = const Duration(seconds: 45),
  }) : _relay = relay ?? CastRelay();

  /// A stream the TV has not started after this long is an error.
  final Duration loadTimeout;

  /// Title and subtitle the TV shows for an item (clean channel name, programme).
  final (String, String?) Function(PlayItem item)? describe;

  /// Tests: fake devices instead of the network.
  final CastSession Function(CastDevice device)? sessionFactory;
  final List<Future<void> Function(Duration timeout, void Function(CastDevice) onDevice)>? browsers;

  final CastRelay _relay;

  // ------------------------------------------------------------ discovery

  /// Devices found by the last search (the connected one always included).
  final ValueNotifier<List<CastDevice>> devices = ValueNotifier(const []);
  final ValueNotifier<bool> scanning = ValueNotifier(false);
  DateTime? _lastScan;

  /// Looks for devices on the network for [timeout]; the list fills as they answer.
  Future<void> scan({Duration timeout = const Duration(seconds: 4)}) async {
    if (scanning.value) return;
    scanning.value = true;
    final found = <String, CastDevice>{};
    final current = _device;
    if (current != null) found[current.key] = current;
    final shown = <String, CastDevice>{for (final d in devices.value) d.key: d, ...found};
    void add(CastDevice d) {
      // Another answer under the same name, from another host, does not
      // take the place of the device found first (a device of the network
      // could pass itself off as the TV, and inherit its choices).
      final known = found[d.key];
      if (known != null && (known.host != d.host || known.port != d.port)) return;
      found[d.key] = d;
      shown[d.key] = d;
      devices.value = _sorted(shown.values);
    }

    final search =
        browsers ??
        [
          (t, f) => ChromecastBrowser().browse(timeout: t, onDevice: f),
          (t, f) => DlnaBrowser().browse(timeout: t, onDevice: f),
        ];
    try {
      await Future.wait([
        for (final b in search) b(timeout, add).catchError((Object e) => debugPrint('Recherche des appareils : $e')),
      ]);
    } finally {
      devices.value = _sorted(found.values);
      scanning.value = false;
      _lastScan = DateTime.now();
    }
  }

  /// Searches again when the last search is old (the panel opens).
  void scanIfStale() {
    final last = _lastScan;
    if (last == null || DateTime.now().difference(last).inSeconds > 30) unawaited(scan());
  }

  static List<CastDevice> _sorted(Iterable<CastDevice> list) => list.toList()
    ..sort((a, b) {
      final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return n != 0 ? n : a.protocol.index.compareTo(b.protocol.index);
    });

  // -------------------------------------------------------------- session

  CastSession? _session;
  CastDevice? _device;

  /// What the TV plays; null when not casting.
  final ValueNotifier<PlayItem?> item = ValueNotifier(null);
  RemoteStatus _status = RemoteStatus();
  bool _connecting = false;
  String? _error;
  Timer? _poll;
  bool _polling = false;
  int _pollErrors = 0;
  StreamSubscription<RemoteStatus>? _updates;
  int _generation = 0;
  int _loadSeq = 0;
  DateTime _loadedAt = DateTime.now();

  /// Requests the relay had received when the last stream was sent.
  int _hitsAtLoad = 0;
  bool _unreachedLogged = false;
  Duration? _lastStart;

  /// The TV has played what was last sent (its position can be trusted).
  bool _started = false;
  DateTime _holdUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _volumeTimer;
  int _ended = 0;
  final _messages = StreamController<String>.broadcast();

  /// TVs given the provider's address instead of a stream that goes
  /// through this computer (the default; local files always do).
  ///
  /// In direct mode the TV receives the address as it is, with the account's
  /// identifiers in it: they travel in clear on the local network and the TV
  /// tells them to any device that asks what it is playing. So it is a
  /// choice made for one TV, not for the next one met, and it is forgotten
  /// when the app closes.
  final Set<String> _direct = {};
  bool _viaRelay = false;

  /// Whether streams reach [d] through this computer.
  bool relayFor(CastDevice d) => !_direct.contains(_directKey(d));

  /// Direct mode is chosen for this TV at this address: another device
  /// announcing the same name elsewhere does not get the identifiers.
  static String _directKey(CastDevice d) => '${d.key}@${d.host}:${d.port}';

  /// Sends streams to [d] directly ([direct]) or through this computer.
  void setDirect(CastDevice d, bool direct) => direct ? _direct.add(_directKey(d)) : _direct.remove(_directKey(d));

  /// Whether direct mode hands the TV the account's identifiers for [it]
  /// (they are part of the provider's address).
  static bool directRevealsCredentials(PlayItem it) => !isLocalMedia(it.url) && redactCredentials(it.url) != it.url;

  bool get active => _device != null;
  CastDevice? get device => _device;
  bool get connecting => _connecting;
  bool get viaRelay => _viaRelay;
  RemoteStatus get status => _status;

  /// What went wrong, shown with "Réessayer".
  String? get error => _error ?? (_status.state == RemoteState.error ? (_status.error ?? 'Erreur de lecture.') : null);
  bool get playing => _status.state == RemoteState.playing;
  bool get loading => _connecting || _status.state == RemoteState.loading || _status.state == RemoteState.buffering;
  Duration? get duration => _status.duration;
  double get volume => _status.volume ?? 1;

  /// Bumped each time the TV reaches the end of a film or episode.
  int get endedCount => _ended;

  /// Short messages for the player (an action the TV refused).
  Stream<String> get messages => _messages.stream;

  /// Position on the TV, moving on between two status updates.
  Duration get position {
    final s = _status;
    var p = s.position;
    if (s.state == RemoteState.playing) p += DateTime.now().difference(s.at);
    final d = s.duration;
    if (d != null && p > d) p = d;
    return p.isNegative ? Duration.zero : p;
  }

  CastSession _create(CastDevice d) => switch (d.protocol) {
    CastProtocol.chromecast => ChromecastSession(d),
    CastProtocol.dlna => DlnaSession(d),
  };

  /// Connects to [d] and plays [it] there from [start].
  Future<void> start(CastDevice d, PlayItem it, {Duration? start}) async {
    // Same device again: the old connection must be gone before the new one
    // starts the player on the TV.
    if (_device != null) await _disconnect(stopRemote: _device != d, wait: _device == d);
    final gen = ++_generation;
    _device = d;
    _connecting = true;
    _error = null;
    _status = RemoteStatus(state: RemoteState.loading);
    item.value = it;
    notifyListeners();
    final session = (sessionFactory ?? _create)(d);
    _session = session;
    try {
      await session.connect();
      if (gen != _generation) {
        unawaited(session.close().catchError((Object _) {}));
        return;
      }
      _updates = session.updates.listen((s) {
        if (gen == _generation) _setStatus(s);
      });
      _connecting = false;
      _startPolling(gen);
      // Zapped while connecting: the last channel asked is the one to play.
      final (what, from) = _pending ?? (it, start);
      _pending = null;
      final seq = ++_loadSeq;
      try {
        await _load(what, from, gen, seq);
      } catch (e) {
        if (gen == _generation && seq == _loadSeq) _fail(e);
      }
    } catch (e) {
      if (gen != _generation) return;
      _connecting = false;
      _pending = null;
      _fail(e);
    }
  }

  /// Asked with [load] while the connection was being made.
  (PlayItem, Duration?)? _pending;

  /// Plays [it] on the connected TV (zapping, next episode).
  Future<void> load(PlayItem it, {Duration? start}) async {
    if (_session == null) return;
    if (_connecting) {
      // Played as soon as the TV is connected (see [start]).
      _pending = (it, start);
      item.value = it;
      notifyListeners();
      return;
    }
    final gen = _generation;
    final seq = ++_loadSeq;
    try {
      await _load(it, start, gen, seq);
    } catch (e) {
      if (gen == _generation && seq == _loadSeq) _fail(e);
    }
  }

  Future<void> _load(PlayItem it, Duration? start, int gen, int seq) async {
    final session = _session!;
    final d = _device!;
    if (!it.canOpen) throw CastException(PlayerService.refusedMessage);
    item.value = it;
    _lastStart = start;
    _started = false;
    _error = null;
    _loadedAt = DateTime.now();
    _status = RemoteStatus(state: RemoteState.loading, volume: _status.volume, position: start ?? Duration.zero);
    notifyListeners();

    final address = castUrl(it.url, d.protocol);
    _viaRelay = isLocalMedia(address) || relayFor(d);
    final host = session.localAddress;
    if (_viaRelay && host == null) {
      throw CastException('Adresse de cet ordinateur introuvable sur le réseau de la télé.');
    }
    final (title, subtitle) = describe?.call(it) ?? (it.title, it.subtitle);
    // A TV that answers "Illegal MIME-type" (714) gets the other spellings
    // of the same format it may know.
    final types = session.contentTypesFor(address, live: it.isLive);
    for (final (i, contentType) in types.indexed) {
      // A newer load took over: its relay address must not be cleared.
      if (gen != _generation || seq != _loadSeq) return;
      var url = address;
      if (_viaRelay) {
        _relay.clear();
        url = await _relay.publish(address, host: host!, userAgent: it.userAgent, contentType: contentType);
        _hitsAtLoad = _relay.hits;
        _unreachedLogged = false;
      }
      if (gen != _generation || seq != _loadSeq) return;
      final media = CastMedia(
        url: url,
        contentType: contentType,
        live: it.isLive,
        title: title,
        subtitle: subtitle,
        image: it.image,
      );
      final via = _viaRelay ? ' (relais ${Uri.parse(url).authority})' : '';
      debugPrint('Cast : ${d.kindLabel} « ${d.name} » ← ${redactCredentials(address)}$via');
      try {
        await session.load(media, start: it.isLive ? null : start);
        return;
      } on CastException catch (e) {
        if (e.code != 714 || i == types.length - 1) rethrow;
        debugPrint('Cast : type $contentType refusé, essai avec ${types[i + 1]}');
      }
    }
  }

  /// Tries again after an error; [viaRelay] switches the way the TV gets the stream.
  Future<void> retry({bool? viaRelay}) async {
    final d = _device;
    final it = item.value;
    if (d == null || it == null) return;
    if (viaRelay != null) setDirect(d, !viaRelay);
    Duration? from;
    if (!it.isLive) from = position > const Duration(seconds: 5) ? position : _lastStart;
    await _disconnect(stopRemote: false, wait: true);
    await start(d, it, start: from);
  }

  /// Stops casting; returns where the film or episode was on the TV.
  Future<Duration?> stop() async {
    if (_device == null) return null;
    final it = item.value;
    Duration? pos;
    if (it != null && !it.isLive) {
      // A TV that never started (still loading, or refused the stream)
      // reports 0: the film goes on from where it was sent, not from the
      // beginning (which would also overwrite its "Reprendre" position).
      pos = _started ? position : _lastStart;
      if (pos == Duration.zero) pos = null;
    }
    await _disconnect(stopRemote: true);
    return pos;
  }

  Future<void> _disconnect({required bool stopRemote, bool wait = false}) async {
    _generation++;
    _poll?.cancel();
    _poll = null;
    _volumeTimer?.cancel();
    await _updates?.cancel();
    _updates = null;
    final s = _session;
    _session = null;
    _device = null;
    _connecting = false;
    _error = null;
    _status = RemoteStatus();
    item.value = null;
    _relay.clear();
    notifyListeners();
    if (s == null) return;
    final closing = () async {
      if (stopRemote) {
        try {
          await s.stop().timeout(const Duration(seconds: 4));
        } catch (_) {}
      }
      try {
        await s.close().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }();
    if (wait) await closing;
  }

  void _startPolling(int gen) {
    _poll?.cancel();
    _pollErrors = 0;
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      final session = _session;
      if (_polling || gen != _generation || session == null) return;
      // A stream the TV never starts.
      if (_status.state == RemoteState.loading && DateTime.now().difference(_loadedAt) > loadTimeout) {
        _fail(CastException(_unreached ?? "La télé n'arrive pas à lire ce flux."));
        return;
      }
      _polling = true;
      try {
        final st = await session.poll();
        if (gen == _generation) {
          _pollErrors = 0;
          _setStatus(st);
        }
      } catch (e) {
        if (gen == _generation && ++_pollErrors >= 5) _fail(e);
      } finally {
        _polling = false;
      }
    });
  }

  /// Why the TV may have failed when it never asked the relay for the
  /// stream: it cannot reach this computer (firewall, other network).
  String? get _unreached {
    if (!_viaRelay || _relay.hits != _hitsAtLoad) return null;
    if (!_unreachedLogged) debugPrint('Cast : la télé n’a rien demandé au relais');
    _unreachedLogged = true;
    return "La télé n'a pas pu joindre cet ordinateur. Sous Windows, autorise Bobine dans le pare-feu "
        '(réseaux privés et publics), puis réessaie.';
  }

  void _setStatus(RemoteStatus s) {
    // The TV gave up opening the stream without ever asking for it.
    if (s.state == RemoteState.error &&
        _error == null &&
        _status.state == RemoteState.loading &&
        !(s.error ?? '').startsWith('Connexion perdue')) {
      final why = _unreached;
      if (why != null) s = s.copyWith(error: why);
    }
    if (_error != null && s.state != RemoteState.playing) return;
    // Just after a seek, the TV may still report the old position.
    if (DateTime.now().isBefore(_holdUntil) && s.state != RemoteState.error) s = s.copyWith(position: position);
    final before = _status.state;
    _status = s;
    if (s.state == RemoteState.playing) {
      _error = null;
      _started = true;
    }
    if (s.state == RemoteState.ended && before != RemoteState.ended) _ended++;
    notifyListeners();
  }

  void _fail(Object e) {
    final message = e is CastException ? e.message : "La diffusion a échoué.";
    debugPrint('Cast : ${redactCredentials('$e')}');
    _error = message;
    _status = _status.copyWith(state: RemoteState.error, error: message);
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function(CastSession s) action) async {
    final s = _session;
    if (s == null) return;
    try {
      await action(s);
    } on CastException catch (e) {
      if (!_messages.isClosed) _messages.add(e.message);
    } catch (e) {
      debugPrint('Cast : ${redactCredentials('$e')}');
    }
  }

  // ------------------------------------------------------------- controls

  Future<void> play() async {
    _status = _status.copyWith(state: RemoteState.playing, position: position);
    notifyListeners();
    await _guard((s) => s.play());
  }

  Future<void> pause() async {
    _status = _status.copyWith(state: RemoteState.paused, position: position);
    notifyListeners();
    await _guard((s) => s.pause());
  }

  Future<void> togglePlay() =>
      (_status.state == RemoteState.playing || _status.state == RemoteState.buffering) ? pause() : play();

  Future<void> seekTo(Duration to) async {
    final it = item.value;
    if (it == null || it.isLive) return;
    var target = to.isNegative ? Duration.zero : to;
    final d = duration;
    if (d != null && target > d) target = d;
    _status = _status.copyWith(position: target);
    _holdUntil = DateTime.now().add(const Duration(milliseconds: 2500));
    notifyListeners();
    await _guard((s) => s.seek(target));
  }

  Future<void> seekBy(Duration delta) => seekTo(position + delta);

  /// [level] from 0 to 1 (slider moves are grouped).
  void setVolume(double level) {
    final v = level.clamp(0.0, 1.0);
    _status = _status.copyWith(volume: v);
    notifyListeners();
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 150), () => _guard((s) => s.setVolume(v)));
  }
}
