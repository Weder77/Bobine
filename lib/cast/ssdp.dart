import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/version.dart';
import 'cast_device.dart';
import 'cast_xml.dart';
import 'mdns.dart' show setMulticastInterface;

/// Finds DLNA / UPnP media renderers (smart TVs, Kodi, boxes) with SSDP.
class DlnaBrowser {
  DlnaBrowser({this.client});

  /// Downloads the descriptions (a new one for each search when null).
  final HttpClient? client;

  static final group = InternetAddress('239.255.255.250');
  static const ssdpPort = 1900;
  static const targets = ['urn:schemas-upnp-org:device:MediaRenderer:1', 'urn:schemas-upnp-org:service:AVTransport:1'];

  /// Descriptions fetched at most per search.
  static const maxDescriptions = 32;

  /// Asks the network for [timeout] and reports each renderer once.
  Future<void> browse({required Duration timeout, required void Function(CastDevice) onDevice}) async {
    final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 4));
    final sockets = <RawDatagramSocket>[];
    for (final (_, address) in await localIPv4()) {
      try {
        final s = await RawDatagramSocket.bind(address, 0);
        s.multicastHops = 4;
        setMulticastInterface(s, address);
        sockets.add(s);
      } catch (_) {}
    }
    if (sockets.isEmpty) {
      try {
        sockets.add(await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0));
      } catch (_) {}
    }
    final seen = <String>{};
    final pending = <Future<void>>[];
    final deadline = DateTime.now().add(timeout);
    void onMessage(String text, InternetAddress from) {
      final location = ssdpLocation(text);
      // The description is fetched from the device that answered, and a
      // few of them at most: a device of the network can name any address.
      if (location == null || seen.length >= maxDescriptions || !answerMayPointTo(location.host, from)) return;
      if (!seen.add(location.toString())) return;
      pending.add(
        fetchDescription(http, location, deadline: deadline)
            .then((d) {
              if (d != null) onDevice(d);
            })
            .catchError((Object _) {}),
      );
    }

    final subs = [
      for (final s in sockets)
        s.listen((e) {
          if (e != RawSocketEvent.read) return;
          final d = s.receive();
          if (d != null) onMessage(latin1.decode(d.data, allowInvalid: true), d.address);
        }, onError: (Object _) {}),
    ];
    void search() {
      for (final st in targets) {
        final packet = ascii.encode(ssdpSearch(st));
        for (final s in sockets) {
          try {
            s.send(packet, group, ssdpPort);
          } catch (_) {}
        }
      }
    }

    final timers = [
      for (final ms in const [0, 1000, 2400]) Timer(Duration(milliseconds: ms), search),
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
    // Descriptions still downloading get a last moment.
    await Future.wait(pending).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    if (client == null) http.close(force: true);
  }

  /// Downloads and reads the description of the device at [location].
  static Future<CastDevice?> fetchDescription(HttpClient client, Uri location, {DateTime? deadline}) async {
    var wait = deadline == null ? const Duration(seconds: 5) : deadline.difference(DateTime.now());
    if (wait < const Duration(seconds: 2)) wait = const Duration(seconds: 2);
    final req = await client.getUrl(location).timeout(wait);
    final res = await req.close().timeout(wait);
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final xml = await readDeviceAnswer(res, timeout: wait);
    return parseUpnpDescription(xml, location);
  }
}

/// M-SEARCH request for the search target [st].
String ssdpSearch(String st, {int mx = 2}) =>
    'M-SEARCH * HTTP/1.1\r\n'
    'HOST: 239.255.255.250:1900\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: $mx\r\n'
    'ST: $st\r\n'
    'USER-AGENT: ${Platform.operatingSystem}/1 UPnP/1.1 Bobine/$kAppVersion\r\n'
    '\r\n';

/// LOCATION of an SSDP answer (or announcement), when it is an HTTP address.
Uri? ssdpLocation(String message) {
  final lines = message.split(RegExp(r'\r?\n'));
  if (lines.isEmpty) return null;
  final first = lines.first.toUpperCase();
  if (!(first.startsWith('HTTP/') && first.contains(' 200')) && !first.startsWith('NOTIFY')) return null;
  for (final line in lines.skip(1)) {
    final i = line.indexOf(':');
    if (i <= 0 || line.substring(0, i).trim().toLowerCase() != 'location') continue;
    final uri = Uri.tryParse(line.substring(i + 1).trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return null;
    return uri;
  }
  return null;
}

/// Reads a UPnP device description: a renderer when it has AVTransport.
CastDevice? parseUpnpDescription(String xml, Uri location) {
  String? tag(String source, String name) => xmlText(source, name);

  final urlBase = Uri.tryParse(tag(xml, 'URLBase') ?? '');
  final base = (urlBase != null && urlBase.hasScheme && urlBase.host.isNotEmpty) ? urlBase : location;
  Uri? resolve(String? url) {
    if (url == null) return null;
    try {
      return base.resolve(url);
    } on FormatException {
      return null;
    }
  }

  (Uri, String)? avTransport;
  (Uri, String)? rendering;
  (Uri, String)? connections;
  for (final block in xmlElements(xml, 'service').take(64)) {
    final type = tag(block, 'serviceType');
    final control = resolve(tag(block, 'controlURL'));
    if (type == null || control == null) continue;
    if (avTransport == null && type.contains(':service:AVTransport:')) avTransport = (control, type);
    if (rendering == null && type.contains(':service:RenderingControl:')) rendering = (control, type);
    if (connections == null && type.contains(':service:ConnectionManager:')) connections = (control, type);
  }
  if (avTransport == null) return null;
  // Its controls are on the device the description came from (or its
  // network): not on this computer, the router or the Internet.
  final from = InternetAddress.tryParse(location.host);
  if (from != null && !answerMayPointTo(avTransport.$1.host, from)) return null;
  final name = tag(xml, 'friendlyName') ?? location.host;
  return CastDevice(
    id: tag(xml, 'UDN') ?? '${location.host}:${location.port}',
    name: name,
    protocol: CastProtocol.dlna,
    host: avTransport.$1.host,
    port: avTransport.$1.port,
    model: tag(xml, 'modelName'),
    manufacturer: tag(xml, 'manufacturer'),
    avTransport: avTransport.$1,
    avTransportType: avTransport.$2,
    renderingControl: rendering?.$1,
    renderingControlType: rendering?.$2,
    connectionManager: connections?.$1,
    connectionManagerType: connections?.$2,
  );
}
