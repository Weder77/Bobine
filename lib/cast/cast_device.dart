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
