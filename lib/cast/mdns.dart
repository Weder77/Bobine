import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cast_device.dart';

/// DNS record types used by the discovery.
class DnsType {
  static const a = 1;
  static const ptr = 12;
  static const txt = 16;
  static const srv = 33;
}

/// One resource record of a DNS / mDNS answer (only the fields Bobine uses).
class DnsRecord {
  const DnsRecord(this.name, this.type, {this.ptr, this.target, this.port, this.txt, this.address});
  final String name;
  final int type;

  /// PTR: the instance name.
  final String? ptr;

  /// SRV: host name and port of the service.
  final String? target;
  final int? port;

  /// TXT: key=value pairs (keys in lower case).
  final Map<String, String>? txt;

  /// A: IPv4 address.
  final InternetAddress? address;
}

/// A DNS query for [questions] (name, type). [unicast] sets the "QU" bit
/// (answer sent straight back instead of to the multicast group).
Uint8List dnsQuery(List<(String, int)> questions, {int id = 0, bool unicast = false}) {
  final b = BytesBuilder();
  void u16(int v) => b.add([(v >> 8) & 0xff, v & 0xff]);
  u16(id);
  u16(0); // standard query
  u16(questions.length);
  u16(0);
  u16(0);
  u16(0);
  for (final (name, type) in questions) {
    for (final label in name.split('.')) {
      if (label.isEmpty) continue;
      final bytes = utf8.encode(label);
      final n = bytes.length > 63 ? 63 : bytes.length;
      b.addByte(n);
      b.add(bytes.sublist(0, n));
    }
    b.addByte(0);
    u16(type);
    u16(unicast ? 0x8001 : 0x0001); // class IN
  }
  return b.toBytes();
}

/// Answers, authority and additional records of a DNS message. Unknown types
/// are skipped; a malformed message gives what could be read before the error.
List<DnsRecord> dnsRecords(Uint8List p) {
  final out = <DnsRecord>[];
  if (p.length < 12) return out;
  int u16(int o) => (p[o] << 8) | p[o + 1];
  try {
    // A real answer has a few records; a forged one can claim 196 605.
    final questions = u16(4).clamp(0, 16);
    final records = (u16(6) + u16(8) + u16(10)).clamp(0, 64);
    var o = 12;
    for (var i = 0; i < questions; i++) {
      o = _readName(p, o).$2 + 4;
    }
    for (var i = 0; i < records; i++) {
      final (name, next) = _readName(p, o);
      o = next;
      if (o + 10 > p.length) break;
      final type = u16(o);
      final length = u16(o + 8);
      o += 10;
      final end = o + length;
      if (end > p.length) break;
      switch (type) {
        case DnsType.ptr:
          out.add(DnsRecord(name, type, ptr: _readName(p, o).$1));
        case DnsType.srv when length >= 7:
          out.add(DnsRecord(name, type, port: u16(o + 4), target: _readName(p, o + 6).$1));
        case DnsType.txt:
          out.add(DnsRecord(name, type, txt: _txt(p, o, end)));
        case DnsType.a when length == 4:
          out.add(
            DnsRecord(name, type, address: InternetAddress.fromRawAddress(Uint8List.fromList(p.sublist(o, end)))),
          );
      }
      o = end;
    }
  } on RangeError {
    // Truncated message: keep what was read.
  } on FormatException {
    // Bad name: same.
  }
  return out;
}

/// Reads a (possibly compressed) name at [offset]: the name and the offset
/// right after it in the message.
(String, int) _readName(Uint8List p, int offset) {
  final labels = <String>[];
  var o = offset;
  int? after;
  var jumps = 0, size = 0;
  while (true) {
    final len = p[o];
    if (len == 0) {
      o++;
      break;
    }
    if (len & 0xC0 == 0xC0) {
      if (++jumps > 32) throw const FormatException('DNS name loop');
      after ??= o + 2;
      o = ((len & 0x3F) << 8) | p[o + 1];
      continue;
    }
    if (len & 0xC0 != 0) throw const FormatException('DNS label');
    o++;
    if (o + len > p.length) throw RangeError('DNS label');
    // 255 bytes at most (RFC 1035): pointers could otherwise build huge ones.
    size += len + 1;
    if (size > 255) throw const FormatException('DNS name too long');
    labels.add(utf8.decode(p.sublist(o, o + len), allowMalformed: true));
    o += len;
  }
  return (labels.join('.'), after ?? o);
}

Map<String, String> _txt(Uint8List p, int start, int end) {
  final out = <String, String>{};
  var o = start;
  while (o < end) {
    final len = p[o++];
    if (o + len > end) break;
    final s = utf8.decode(p.sublist(o, o + len), allowMalformed: true);
    o += len;
    final eq = s.indexOf('=');
    if (eq <= 0) continue;
    out[s.substring(0, eq).toLowerCase()] = s.substring(eq + 1);
  }
  return out;
}

/// Sets the interface multicast packets leave from (IP_MULTICAST_IF), so a
/// query goes out on every network and not only the default one.
void setMulticastInterface(RawDatagramSocket s, InternetAddress address) {
  final option = (Platform.isLinux || Platform.isAndroid) ? 32 : 9;
  try {
    s.setRawOption(RawSocketOption(RawSocketOption.levelIPv4, option, Uint8List.fromList(address.rawAddress)));
  } catch (_) {}
}

/// Finds Google Cast devices (Chromecast, Google TV, Android TV…) with mDNS.
class ChromecastBrowser {
  static const service = '_googlecast._tcp.local';
  static final group = InternetAddress('224.0.0.251');
  static const mdnsPort = 5353;

  /// Asks the network for [timeout] and reports each device once.
  Future<void> browse({required Duration timeout, required void Function(CastDevice) onDevice}) async {
    final interfaces = await localIPv4();
    final sockets = <RawDatagramSocket>[];
    // One socket per network, from a random port: devices answer it directly
    // ("legacy unicast", RFC 6762 §6.7). Works beside any other mDNS service.
    for (final (_, address) in interfaces) {
      try {
        final s = await RawDatagramSocket.bind(address, 0);
        s.multicastHops = 255;
        setMulticastInterface(s, address);
        sockets.add(s);
      } catch (_) {}
    }
    // Shared mDNS port too, for devices that only answer to the group.
    RawDatagramSocket? shared;
    for (final reusePort in [if (!Platform.isWindows) true, false]) {
      try {
        shared = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          mdnsPort,
          reuseAddress: true,
          reusePort: reusePort,
        );
        break;
      } catch (_) {}
    }
    if (shared != null) {
      shared.multicastHops = 255;
      for (final (i, _) in interfaces) {
        try {
          shared.joinMulticast(group, i);
        } catch (_) {}
      }
      sockets.add(shared);
    }
    if (sockets.isEmpty) return;

    final state = ChromecastAnswers();
    final asked = <String>{};
    void send(Uint8List packet) {
      for (final s in sockets) {
        try {
          s.send(packet, group, mdnsPort);
        } catch (_) {}
      }
    }

    void onPacket(Datagram d) {
      for (final device in state.add(dnsRecords(d.data), d.address)) {
        onDevice(device);
      }
      // Answers without the details: ask for them.
      for (final instance in state.incomplete) {
        if (asked.length < ChromecastAnswers.maxEntries && asked.add(instance)) {
          send(dnsQuery([(instance, DnsType.txt), (instance, DnsType.srv)]));
        }
      }
    }

    final subs = [
      for (final s in sockets)
        s.listen((e) {
          if (e != RawSocketEvent.read) return;
          final d = s.receive();
          if (d != null) onPacket(d);
        }, onError: (Object _) {}),
    ];
    final query = dnsQuery([(service, DnsType.ptr)]);
    final timers = [
      for (final ms in const [0, 900, 2200]) Timer(Duration(milliseconds: ms), () => send(query)),
    ];
    await Future<void>.delayed(timeout);
    for (final t in timers) {
      t.cancel();
    }
    for (final s in subs) {
      await s.cancel();
    }
    for (final s in sockets) {
      s.close();
    }
  }
}

/// Puts mDNS answers together into devices.
class ChromecastAnswers {
  final _instances = <String, InternetAddress>{}; // instance → responder
  final _spelling = <String, String>{}; // instance → name as announced
  final _txt = <String, Map<String, String>>{};
  final _srv = <String, (String, int)>{};
  final _hosts = <String, InternetAddress>{};
  final _reported = <String, String>{};

  /// Instances announced without their TXT record yet.
  Iterable<String> get incomplete => _instances.keys.where((i) => !_txt.containsKey(i));

  /// Most instances and records kept: a network with more Chromecasts than
  /// this is not a home, and forged answers must not fill the memory.
  static const maxEntries = 64;

  /// Adds the [records] of a message sent by [from]; returns devices that are
  /// new or changed.
  List<CastDevice> add(List<DnsRecord> records, InternetAddress from) {
    // A full table refuses new names only: what is already known keeps
    // being updated (a device's new address), where everything stopped.
    bool room(Map<String, Object?> m, String key) => m.containsKey(key) || m.length < maxEntries;
    for (final r in records) {
      final name = r.name.toLowerCase();
      switch (r.type) {
        case DnsType.ptr when name == ChromecastBrowser.service && r.ptr != null:
          final instance = r.ptr!.toLowerCase();
          if (!room(_instances, instance)) continue;
          _instances[instance] = from;
          _spelling[instance] = r.ptr!;
        case DnsType.txt when r.txt != null:
          if (room(_txt, name)) _txt[name] = r.txt!;
        case DnsType.srv when r.target != null:
          if (room(_srv, name)) _srv[name] = (r.target!.toLowerCase(), r.port ?? 8009);
        case DnsType.a when r.address != null:
          if (room(_hosts, name)) _hosts[name] = r.address!;
      }
    }
    // A device that answers a TXT / SRV query directly is known too.
    for (final r in records) {
      final name = r.name.toLowerCase();
      if ((r.type == DnsType.txt || r.type == DnsType.srv) && name.endsWith('.${ChromecastBrowser.service}')) {
        _instances.putIfAbsent(name, () => from);
        _spelling.putIfAbsent(name, () => r.name);
      }
    }
    final out = <CastDevice>[];
    for (final MapEntry(key: instance, value: responder) in _instances.entries) {
      final txt = _txt[instance];
      if (txt == null) continue;
      final caps = int.tryParse(txt['ca'] ?? '');
      final model = txt['md'];
      // Speakers and speaker groups: no picture.
      if (caps != null && caps & 1 == 0) continue;
      if (model != null && model.toLowerCase().contains('group')) continue;
      final srv = _srv[instance];
      final announced = srv == null ? null : _hosts[srv.$1];
      // The address it gives itself, when it is on the responder's network.
      final host = announced != null && answerMayPointTo(announced.address, responder) ? announced : responder;
      final device = CastDevice(
        id: txt['id'] ?? instance,
        name: _name(txt['fn'], _spelling[instance] ?? instance),
        protocol: CastProtocol.chromecast,
        host: host.address,
        port: srv?.$2 ?? 8009,
        model: model,
      );
      final signature = '${device.name}|${device.host}|${device.port}';
      if (_reported[instance] == signature) continue;
      _reported[instance] = signature;
      out.add(device);
    }
    return out;
  }

  static String _name(String? friendly, String instance) {
    if (friendly != null && friendly.trim().isNotEmpty) return friendly.trim();
    var n = instance.split('._googlecast').first;
    n = n.replaceFirst(RegExp(r'-[0-9a-f]{32}$', caseSensitive: false), '');
    return n.replaceAll('-', ' ');
  }
}
