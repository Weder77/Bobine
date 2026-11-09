import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cast_device.dart';
import 'cast_media.dart';
import 'cast_session.dart';

/// One message of the Google Cast protocol (CastMessage protobuf).
class CastMessage {
  const CastMessage({required this.source, required this.destination, required this.namespace, required this.payload});
  final String source;
  final String destination;
  final String namespace;

  /// JSON text.
  final String payload;

  Map<String, Object?> get json {
    try {
      final v = jsonDecode(payload);
      return v is Map ? v.cast<String, Object?>() : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// Encodes [m] as protobuf, without the length prefix.
Uint8List encodeCastMessage(CastMessage m) {
  final b = BytesBuilder();
  void varint(int v) {
    while (v >= 0x80) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  void string(int field, String s) {
    final bytes = utf8.encode(s);
    varint(field << 3 | 2);
    varint(bytes.length);
    b.add(bytes);
  }

  varint(1 << 3); // protocol_version = CASTV2_1_0
  varint(0);
  string(2, m.source);
  string(3, m.destination);
  string(4, m.namespace);
  varint(5 << 3); // payload_type = STRING
  varint(0);
  string(6, m.payload);
  return b.toBytes();
}

/// Decodes a protobuf CastMessage (binary payloads are ignored).
CastMessage decodeCastMessage(Uint8List data) {
  var o = 0;
  int varint() {
    var shift = 0, v = 0;
    while (true) {
      final byte = data[o++];
      v |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return v;
      shift += 7;
      if (shift > 63) throw const FormatException('varint');
    }
  }

  final strings = <int, String>{};
  while (o < data.length) {
    final key = varint();
    final field = key >> 3;
    switch (key & 7) {
      case 0:
        varint();
      case 1:
        o += 8;
      case 2:
        final len = varint();
        if (o + len > data.length) throw const FormatException('length');
        if (field == 2 || field == 3 || field == 4 || field == 6) {
          strings[field] = utf8.decode(data.sublist(o, o + len), allowMalformed: true);
        }
        o += len;
      case 5:
        o += 4;
      default:
        throw const FormatException('wire type');
    }
  }
  return CastMessage(
    source: strings[2] ?? '',
    destination: strings[3] ?? '',
    namespace: strings[4] ?? '',
    payload: strings[6] ?? '',
  );
}

/// Cuts the TLS byte stream into messages (4-byte big-endian length prefix).
class CastFrameReader {
  final _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  List<CastMessage> add(List<int> chunk) {
    _buffer.add(_pending);
    _buffer.add(chunk);
    var data = _buffer.takeBytes();
    final out = <CastMessage>[];
    var o = 0;
    while (data.length - o >= 4) {
      final len = (data[o] << 24) | (data[o + 1] << 16) | (data[o + 2] << 8) | data[o + 3];
      if (len > 1 << 20) throw const FormatException('Message Cast trop grand');
      if (data.length - o - 4 < len) break;
      out.add(decodeCastMessage(Uint8List.sublistView(data, o + 4, o + 4 + len)));
      o += 4 + len;
    }
    _pending = Uint8List.fromList(Uint8List.sublistView(data, o));
    data = Uint8List(0);
    return out;
  }
}

Uint8List frameCastMessage(CastMessage m) {
  final body = encodeCastMessage(m);
  final out = Uint8List(body.length + 4);
  ByteData.sublistView(out).setUint32(0, body.length);
  out.setRange(4, out.length, body);
  return out;
}

/// Namespaces of the protocol.
class CastNs {
  static const connection = 'urn:x-cast:com.google.cast.tp.connection';
  static const heartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const receiver = 'urn:x-cast:com.google.cast.receiver';
  static const media = 'urn:x-cast:com.google.cast.media';
}

/// Google's Default Media Receiver: plays a URL, no app needed on the TV.
const kDefaultMediaReceiver = 'CC1AD845';

/// Opens the connection to a device (TLS; tests use plain sockets).
typedef CastConnector = Future<Socket> Function(String host, int port, Duration timeout);

Future<Socket> _tls(String host, int port, Duration timeout) => SecureSocket.connect(
  host,
  port,
  timeout: timeout,
  // Cast devices use certificates signed by Google's own authority.
  onBadCertificate: (_) => true,
);

/// Drives a Google Cast device with the Default Media Receiver.
class ChromecastSession implements CastSession {
  ChromecastSession(this.device, {this.connectTimeout = const Duration(seconds: 8), CastConnector? connector})
    : _connector = connector ?? _tls;

  @override
  final CastDevice device;
  final Duration connectTimeout;
  final CastConnector _connector;

  static const _sender = 'sender-bobine';
  static const _platform = 'receiver-0';

  Socket? _socket;
  final _reader = CastFrameReader();
  final _replies = <int, Completer<Map<String, Object?>>>{};
  final _updates = StreamController<RemoteStatus>.broadcast();
  int _requestId = 0;
  Timer? _heartbeat;
  DateTime _lastSeen = DateTime.now();
  bool _closed = false;

  String? _appSession;
  String? _transport;
  int? _mediaSession;
  bool _live = false;
  RemoteStatus _status = RemoteStatus();

  /// Broadcasts of RECEIVER_STATUS (to wait for the app to start).
  final _receiverStatus = StreamController<Map<String, Object?>>.broadcast();

  @override
  InternetAddress? get localAddress => _socket?.address;

  @override
  Stream<RemoteStatus> get updates => _updates.stream;

  @override
  Future<void> connect() async {
    try {
      _socket = await _connector(device.host, device.port, connectTimeout);
    } on SocketException {
      throw CastException("L'appareil ne répond pas. Vérifie qu'il est allumé et sur le même réseau.");
    } on TimeoutException {
      throw CastException("L'appareil ne répond pas. Vérifie qu'il est allumé et sur le même réseau.");
    } on HandshakeException {
      throw CastException('Connexion sécurisée impossible avec cet appareil.');
    }
    _socket!.listen(_onData, onError: (Object _) => _lost(), onDone: _lost, cancelOnError: true);
    _send(_platform, CastNs.connection, {'type': 'CONNECT'});
    _lastSeen = DateTime.now();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_lastSeen).inSeconds > 20) return _lost();
      _send(_platform, CastNs.heartbeat, {'type': 'PING'});
    });
  }

  void _onData(Uint8List chunk) {
    _lastSeen = DateTime.now();
    List<CastMessage> messages;
    try {
      messages = _reader.add(chunk);
    } on FormatException {
      return _lost();
    }
    for (final m in messages) {
      final json = m.json;
      final type = json['type'];
      if (m.namespace == CastNs.heartbeat) {
        if (type == 'PING') _send(m.source, CastNs.heartbeat, {'type': 'PONG'});
        continue;
      }
      if (m.namespace == CastNs.connection && type == 'CLOSE') {
        // The receiver app was closed (other sender, TV input changed…).
        if (m.source == _transport || m.source == _platform) _ended('La diffusion a été arrêtée sur la télé.');
        continue;
      }
      if (type == 'RECEIVER_STATUS') {
        _onReceiverStatus(json);
        _receiverStatus.add(json);
      } else if (type == 'MEDIA_STATUS') {
        _onMediaStatus(json);
      }
      final id = (json['requestId'] as num?)?.toInt() ?? 0;
      if (id != 0) _replies.remove(id)?.complete(json);
    }
  }

  void _onReceiverStatus(Map<String, Object?> json) {
    final status = json['status'];
    if (status is! Map) return;
    final volume = status['volume'];
    if (volume is Map && volume['level'] is num) {
      final muted = volume['muted'] == true;
      _emit(_status.copyWith(volume: muted ? 0 : (volume['level'] as num).toDouble()));
    }
    final apps = status['applications'];
    final ours = apps is List
        ? apps.whereType<Map>().where((a) => a['appId'] == kDefaultMediaReceiver).firstOrNull
        : null;
    // Our player is no longer running on the device.
    if (_transport != null && ours == null) _ended('La diffusion a été arrêtée sur la télé.');
  }

  void _onMediaStatus(Map<String, Object?> json) {
    final list = json['status'];
    if (list is! List) return;
    final st = list.whereType<Map>().firstOrNull;
    if (st == null) {
      // Nothing loaded any more.
      if (_mediaSession != null && _status.state != RemoteState.loading) {
        _emit(_status.copyWith(state: _status.state == RemoteState.ended ? RemoteState.ended : RemoteState.idle));
      }
      return;
    }
    final session = (st['mediaSessionId'] as num?)?.toInt();
    if (session != null) _mediaSession = session;
    final media = st['media'];
    final duration = media is Map && media['duration'] is num && !_live
        ? Duration(milliseconds: ((media['duration'] as num) * 1000).round())
        : null;
    final position = st['currentTime'] is num
        ? Duration(milliseconds: ((st['currentTime'] as num) * 1000).round())
        : _status.position;
    final state = switch (st['playerState']) {
      'PLAYING' => RemoteState.playing,
      'PAUSED' => RemoteState.paused,
      'BUFFERING' => RemoteState.buffering,
      'LOADING' => RemoteState.loading,
      _ => switch (st['idleReason']) {
        'FINISHED' => RemoteState.ended,
        'ERROR' => RemoteState.error,
        'CANCELLED' || 'INTERRUPTED' => RemoteState.idle,
        _ => _status.state == RemoteState.loading ? RemoteState.loading : RemoteState.idle,
      },
    };
    _emit(
      RemoteStatus(
        state: state,
        position: position,
        duration: (duration != null && duration > Duration.zero) ? duration : _status.duration,
        volume: _status.volume,
        error: state == RemoteState.error ? "La télé n'a pas pu lire ce flux." : null,
      ),
    );
  }

  void _emit(RemoteStatus s) {
    _status = s;
    if (!_updates.isClosed) _updates.add(s);
  }

  void _ended(String message) {
    if (_closed) return;
    _transport = null;
    _mediaSession = null;
    _emit(_status.copyWith(state: RemoteState.error, error: message));
  }

  void _lost() {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    for (final c in _replies.values) {
      if (!c.isCompleted) c.completeError(CastException('Connexion perdue avec la télé.'));
    }
    _replies.clear();
    _emit(_status.copyWith(state: RemoteState.error, error: 'Connexion perdue avec la télé.'));
    _socket?.destroy();
  }

  void _send(String destination, String namespace, Map<String, Object?> payload) {
    final s = _socket;
    if (s == null || _closed) return;
    try {
      s.add(
        frameCastMessage(
          CastMessage(source: _sender, destination: destination, namespace: namespace, payload: jsonEncode(payload)),
        ),
      );
    } catch (_) {
      _lost();
    }
  }

  Future<Map<String, Object?>> _request(
    String destination,
    String namespace,
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_closed || _socket == null) return Future.error(CastException('Connexion perdue avec la télé.'));
    final id = ++_requestId;
    final c = Completer<Map<String, Object?>>();
    _replies[id] = c;
    _send(destination, namespace, {...payload, 'requestId': id});
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _replies.remove(id);
        throw CastException('La télé ne répond pas.');
      },
    );
  }

  /// Starts (or finds) the Default Media Receiver and connects to it.
  Future<void> _launch() async {
    String? transportOf(Map<String, Object?> json) {
      final apps = (json['status'] as Map?)?['applications'];
      if (apps is! List) return null;
      for (final a in apps.whereType<Map>()) {
        if (a['appId'] == kDefaultMediaReceiver && a['transportId'] is String) {
          _appSession = a['sessionId'] as String?;
          return a['transportId'] as String;
        }
      }
      return null;
    }

    var transport = transportOf(await _request(_platform, CastNs.receiver, {'type': 'GET_STATUS'}));
    if (transport == null) {
      final waiting = _receiverStatus.stream.map(transportOf).firstWhere((t) => t != null, orElse: () => null);
      final reply = await _request(_platform, CastNs.receiver, {'type': 'LAUNCH', 'appId': kDefaultMediaReceiver});
      if (reply['type'] == 'LAUNCH_ERROR') {
        throw CastException("La télé n'a pas pu ouvrir le lecteur Chromecast.");
      }
      transport =
          transportOf(reply) ??
          await waiting.timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw CastException("La télé n'a pas ouvert le lecteur Chromecast."),
          );
    }
    if (transport != _transport) {
      _transport = transport;
      _send(transport!, CastNs.connection, {'type': 'CONNECT'});
    }
  }

  @override
  String contentTypeFor(String url, {required bool live}) =>
      castContentType(url, live: live, protocol: CastProtocol.chromecast);

  @override
  Future<void> load(CastMedia media, {Duration? start}) async {
    if (_transport == null) await _launch();
    _live = media.live;
    _mediaSession = null;
    _emit(RemoteStatus(state: RemoteState.loading, volume: _status.volume));
    final reply = await _request(_transport!, CastNs.media, {
      'type': 'LOAD',
      'autoplay': true,
      if (start != null && !media.live && start.inSeconds > 0) 'currentTime': start.inMilliseconds / 1000,
      'media': {
        'contentId': media.url,
        'contentUrl': media.url,
        'contentType': media.contentType,
        'streamType': media.live ? 'LIVE' : 'BUFFERED',
        'metadata': {
          'metadataType': 0,
          'title': media.title,
          if (media.subtitle != null && media.subtitle!.isNotEmpty) 'subtitle': media.subtitle,
          if (media.image != null && media.image!.startsWith('http'))
            'images': [
              {'url': media.image},
            ],
        },
      },
    }, timeout: const Duration(seconds: 30));
    switch (reply['type']) {
      case 'LOAD_FAILED' || 'LOAD_CANCELLED' || 'INVALID_REQUEST' || 'ERROR':
        final reason = reply['detailedErrorCode'] ?? reply['reason'];
        _emit(_status.copyWith(state: RemoteState.error, error: "La télé n'a pas pu lire ce flux."));
        throw CastException("La télé n'a pas pu lire ce flux${reason == null ? '' : ' ($reason)'}.");
    }
  }

  Future<void> _media(String type, [Map<String, Object?> extra = const {}]) async {
    final session = _mediaSession;
    final transport = _transport;
    if (session == null || transport == null) throw CastException('Rien en cours sur la télé.');
    await _request(transport, CastNs.media, {'type': type, 'mediaSessionId': session, ...extra});
  }

  @override
  Future<void> play() => _media('PLAY');

  @override
  Future<void> pause() => _media('PAUSE');

  @override
  Future<void> seek(Duration position) => _media('SEEK', {'currentTime': position.inMilliseconds / 1000});

  @override
  Future<void> setVolume(double level) async {
    await _request(_platform, CastNs.receiver, {
      'type': 'SET_VOLUME',
      'volume': {'level': level.clamp(0, 1)},
    });
    _emit(_status.copyWith(volume: level.clamp(0, 1).toDouble()));
  }

  @override
  Future<void> stop() async {
    if (_mediaSession != null) {
      try {
        await _media('STOP');
      } catch (_) {}
    }
    _mediaSession = null;
  }

  @override
  Future<RemoteStatus> poll() async {
    final transport = _transport;
    if (transport != null && !_closed) {
      await _request(transport, CastNs.media, {
        'type': 'GET_STATUS',
        if (_mediaSession != null) 'mediaSessionId': _mediaSession,
      }, timeout: const Duration(seconds: 6));
    }
    return _status;
  }

  @override
  Future<void> close() async {
    if (!_closed) {
      // Quits the player on the TV (back to its home screen).
      final app = _appSession;
      if (app != null && _socket != null) {
        try {
          await _request(_platform, CastNs.receiver, {
            'type': 'STOP',
            'sessionId': app,
          }, timeout: const Duration(seconds: 3));
        } catch (_) {}
      }
      if (_transport != null) _send(_transport!, CastNs.connection, {'type': 'CLOSE'});
      _send(_platform, CastNs.connection, {'type': 'CLOSE'});
      _closed = true;
      try {
        await _socket?.flush().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    _heartbeat?.cancel();
    _socket?.destroy();
    if (!_updates.isClosed) await _updates.close();
    if (!_receiverStatus.isClosed) await _receiverStatus.close();
  }
}
