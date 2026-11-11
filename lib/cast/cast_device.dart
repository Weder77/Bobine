import 'dart:io';

/// How Bobine talks to a screen of the local network.
enum CastProtocol {
  /// Google Cast: Chromecast, Google TV, Android TV, Nest Hub, many TVs.
  chromecast,

  /// UPnP / DLNA media renderer: most Samsung, LG, Sony, Philips, Panasonic
  /// TVs, Kodi, boxes of internet providers.
  dlna,
}

/// A screen found on the local network that can play a stream.
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.model,
    this.manufacturer,
    this.avTransport,
    this.avTransportType,
    this.renderingControl,
    this.renderingControlType,
    this.connectionManager,
    this.connectionManagerType,
  });

  /// Stable identity (Chromecast id, UPnP UDN, else the address).
  final String id;
  final String name;
  final CastProtocol protocol;
  final String host;
  final int port;
  final String? model;
  final String? manufacturer;

  /// DLNA: control address and type of the AVTransport service.
  final Uri? avTransport;
  final String? avTransportType;

  /// DLNA: volume control (optional on renderers).
  final Uri? renderingControl;
  final String? renderingControlType;

  /// DLNA: the formats the renderer accepts (GetProtocolInfo).
  final Uri? connectionManager;
  final String? connectionManagerType;

  String get key => '${protocol.name}:$id';

  /// "Chromecast · Google TV", "DLNA · Samsung".
  String get kindLabel {
    final brand = switch (protocol) {
      CastProtocol.chromecast => model,
      CastProtocol.dlna => manufacturer ?? model,
    };
    final kind = protocol == CastProtocol.chromecast ? 'Chromecast' : 'DLNA';
    if (brand == null || brand.trim().isEmpty || brand.toLowerCase() == kind.toLowerCase()) return kind;
    return '$kind · ${_short(brand.trim())}';
  }

  static String _short(String brand) {
    // "Samsung Electronics", "LG Electronics." → "Samsung", "LG".
    final b = brand.replaceAll(RegExp(r'\s+(Electronics|Corporation|Corp\.?|Inc\.?|Ltd\.?|Co\.?)\.?$'), '');
    return b.length > 28 ? '${b.substring(0, 27)}…' : b;
  }

  @override
  bool operator ==(Object other) => other is CastDevice && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'CastDevice($kindLabel "$name" $host:$port)';
}

/// Usable IPv4 addresses of this computer (loopback and link-local left out).
Future<List<(NetworkInterface, InternetAddress)>> localIPv4() async {
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in list)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) (i, a),
    ];
  } catch (_) {
    return const [];
  }
}

/// This computer's address on the network of the device at [host], i.e. the
/// one the device can open (the relay is published there).
///
/// Dart gives no local address for an outgoing connection (`Socket.address`
/// is the address connected to, the TV's own), so it is worked out from the
/// computer's addresses: the one on the TV's network (same /24), else the one
/// a connection to the TV actually leaves from.
Future<InternetAddress?> localAddressFor(String host, int port) async {
  InternetAddress? target = InternetAddress.tryParse(host);
  if (target == null) {
    try {
      target = (await InternetAddress.lookup(host, type: InternetAddressType.IPv4)).firstOrNull;
    } on SocketException {
      return null;
    }
  }
  if (target == null) return null;
  if (target.isLoopback) return target;
  final candidates = [for (final (_, a) in await localIPv4()) a];
  // A renderer on this computer (Kodi, VLC…).
  if (candidates.any((a) => a.address == target!.address)) return target;
  final same = pickLocalAddress(target, candidates);
  if (same != null) return same;
  for (final a in candidatesByPrefix(target, candidates)) {
    try {
      final s = await Socket.connect(target, port, sourceAddress: a, timeout: const Duration(seconds: 3));
      s.destroy();
      return a;
    } catch (_) {}
  }
  return candidatesByPrefix(target, candidates).firstOrNull;
}

/// The address of [candidates] on the same /24 network as [target] (home
/// networks), the closest one first; null when none is.
InternetAddress? pickLocalAddress(InternetAddress target, List<InternetAddress> candidates) {
  final sorted = candidatesByPrefix(target, candidates);
  if (sorted.isEmpty || _sharedBits(sorted.first, target) < 24) return null;
  return sorted.first;
}

/// [candidates] (IPv4) sorted by the length of the prefix they share with [target].
List<InternetAddress> candidatesByPrefix(InternetAddress target, List<InternetAddress> candidates) {
  final v4 = candidates.where((a) => a.type == InternetAddressType.IPv4 && a.address != target.address).toList();
  v4.sort((a, b) => _sharedBits(b, target).compareTo(_sharedBits(a, target)));
  return v4;
}

int _sharedBits(InternetAddress a, InternetAddress b) {
  final x = a.rawAddress, y = b.rawAddress;
  if (x.length != y.length) return 0;
  var bits = 0;
  for (var i = 0; i < x.length; i++) {
    final d = x[i] ^ y[i];
    if (d == 0) {
      bits += 8;
      continue;
    }
    var mask = 0x80;
    while (mask > 0 && d & mask == 0) {
      bits++;
      mask >>= 1;
    }
    break;
  }
  return bits;
}

/// Whether [a] is an address of the local network: private, link-local, or
/// this computer.
bool isLocalNetworkAddress(InternetAddress a) {
  if (a.isLoopback || a.isLinkLocal) return true;
  if (a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
}

/// Whether a device that answered from [from] may be reached at [host]
/// (an address it gave itself): the same address, or another one of the
/// same local network (/24). Anything else (this computer for another
/// device, the router, a host on the Internet) is not followed: a device
/// of the network can answer anything.
bool answerMayPointTo(String host, InternetAddress from) {
  final to = InternetAddress.tryParse(host);
  if (to == null) return false;
  if (to.address == from.address) return true;
  if (to.type != InternetAddressType.IPv4 || from.type != InternetAddressType.IPv4) return false;
  if (to.isLoopback || !isLocalNetworkAddress(to) || !isLocalNetworkAddress(from)) return false;
  final x = to.rawAddress, y = from.rawAddress;
  return x[0] == y[0] && x[1] == y[1] && x[2] == y[2];
}
