import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bobine/cast/cast_device.dart';
import 'package:bobine/cast/cast_media.dart';
import 'package:bobine/cast/cast_session.dart';
import 'package:bobine/cast/chromecast.dart';
import 'package:bobine/cast/dlna.dart';
import 'package:bobine/cast/mdns.dart';
import 'package:bobine/cast/ssdp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes DNS messages with name compression, like real responders.
class _DnsWriter {
  final out = <int>[];
  final _names = <String, int>{};

  void u16(int v) => out.addAll([(v >> 8) & 0xff, v & 0xff]);
  void u32(int v) => out.addAll([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);

  void name(String n) {
    final labels = n.split('.');
    for (var i = 0; i < labels.length; i++) {
      final suffix = labels.sublist(i).join('.').toLowerCase();
      final at = _names[suffix];
      if (at != null) return u16(0xC000 | at);
      _names[suffix] = out.length;
      final bytes = utf8.encode(labels[i]);
      out
        ..add(bytes.length)
        ..addAll(bytes);
    }
    out.add(0);
  }

  void record(String n, int type, void Function() rdata) {
    name(n);
    u16(type);
    u16(0x8001);
    u32(120);
    final at = out.length;
    u16(0);
    rdata();
    final len = out.length - at - 2;
    out[at] = len >> 8;
    out[at + 1] = len & 0xff;
  }

  static Uint8List answer(void Function(_DnsWriter w) records, {required int count}) {
    final w = _DnsWriter();
    w
      ..u16(0)
      ..u16(0x8400)
      ..u16(0)
      ..u16(count)
      ..u16(0)
      ..u16(0);
    records(w);
    return Uint8List.fromList(w.out);
  }
}

Uint8List _chromecastAnswer({String fn = 'Salon', String ca = '201221', String md = 'Chromecast'}) {
  const instance = 'Chromecast-0123456789abcdef0123456789abcdef._googlecast._tcp.local';
  return _DnsWriter.answer(count: 4, (w) {
    w.record(ChromecastBrowser.service, DnsType.ptr, () => w.name(instance));
    w.record(instance, DnsType.txt, () {
      for (final kv in ['id=0123456789abcdef', 'md=$md', 'fn=$fn', 'ca=$ca', 'rs=']) {
        final b = utf8.encode(kv);
        w.out
          ..add(b.length)
          ..addAll(b);
      }
    });
    w.record(instance, DnsType.srv, () {
      w
        ..u16(0)
        ..u16(0)
        ..u16(8009)
        ..name('0123-4567.local');
    });
    w.record('0123-4567.local', DnsType.a, () => w.out.addAll([192, 168, 1, 42]));
  });
}

void main() {
  group('mDNS', () {
    test('query packet asks for the PTR of the Cast service', () {
      final q = dnsQuery([(ChromecastBrowser.service, DnsType.ptr)], unicast: true);
      expect(q.sublist(0, 12), [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      expect(utf8.decode(q.sublist(13, 24)), '_googlecast');
      // Type PTR, class IN with the "unicast response" bit.
      expect(q.sublist(q.length - 4), [0, 12, 0x80, 1]);
    });

    test('compressed answer gives a Chromecast with its name, address and port', () {
      final records = dnsRecords(_chromecastAnswer(fn: 'Télé du salon'));
      expect(records.map((r) => r.type), [DnsType.ptr, DnsType.txt, DnsType.srv, DnsType.a]);
      final devices = ChromecastAnswers().add(records, InternetAddress('192.168.1.99'));
      expect(devices, hasLength(1));
      final d = devices.single;
      expect(d.name, 'Télé du salon');
      expect(d.host, '192.168.1.42');
      expect(d.port, 8009);
      expect(d.id, '0123456789abcdef');
      expect(d.protocol, CastProtocol.chromecast);
      expect(d.kindLabel, 'Chromecast');
    });

    test('speakers and groups are left out; the same device is reported once', () {
      final answers = ChromecastAnswers();
      final from = InternetAddress('192.168.1.42');
      // ca without the "video out" bit: a speaker.
      expect(answers.add(dnsRecords(_chromecastAnswer(ca: '2052')), from), isEmpty);
      final groups = ChromecastAnswers();
      expect(groups.add(dnsRecords(_chromecastAnswer(md: 'Google Cast Group', ca: '2085')), from), isEmpty);
      final tv = ChromecastAnswers();
      expect(tv.add(dnsRecords(_chromecastAnswer()), from), hasLength(1));
      expect(tv.add(dnsRecords(_chromecastAnswer()), from), isEmpty);
      expect(tv.add(dnsRecords(_chromecastAnswer(fn: 'Chambre')), from).single.name, 'Chambre');
    });

    test('a bare PTR asks for details; the responder address is used without A record', () {
      const instance = 'Google-TV-ffffffffffffffffffffffffffffffff._googlecast._tcp.local';
      final answers = ChromecastAnswers();
      final from = InternetAddress('10.0.0.7');
      final ptr = _DnsWriter.answer(
        count: 1,
        (w) => w.record(ChromecastBrowser.service, DnsType.ptr, () => w.name(instance)),
      );
      expect(answers.add(dnsRecords(ptr), from), isEmpty);
      expect(answers.incomplete, [instance.toLowerCase()]);
      final txt = _DnsWriter.answer(
        count: 1,
        (w) => w.record(instance, DnsType.txt, () {
          final b = utf8.encode('md=Google TV');
          w.out
            ..add(b.length)
            ..addAll(b);
        }),
      );
      final d = answers.add(dnsRecords(txt), from).single;
      expect(d.host, '10.0.0.7');
      expect(d.port, 8009);
      expect(d.name, 'Google TV');
      expect(d.kindLabel, 'Chromecast · Google TV');
    });

    test('truncated or looping messages do not throw', () {
      final full = _chromecastAnswer();
      for (var n = 0; n < full.length; n += 7) {
        expect(() => dnsRecords(Uint8List.sublistView(full, 0, n)), returnsNormally);
      }
      // A name pointing to itself.
      final loop = Uint8List.fromList([0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0xC0, 12, 0, 12, 0, 1, 0, 0, 0, 1, 0, 0]);
      expect(dnsRecords(loop), isEmpty);
    });
  });

  group('SSDP / UPnP', () {
    test('search request and LOCATION of answers', () {
      final m = ssdpSearch('urn:schemas-upnp-org:device:MediaRenderer:1');
      expect(m, startsWith('M-SEARCH * HTTP/1.1\r\n'));
      expect(m, contains('MAN: "ssdp:discover"\r\n'));
      expect(m, endsWith('\r\n\r\n'));
      expect(
        ssdpLocation(
          'HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLocation: http://192.168.1.20:9197/dmr\r\n\r\n',
        ),
        Uri.parse('http://192.168.1.20:9197/dmr'),
      );
      expect(ssdpLocation('M-SEARCH * HTTP/1.1\r\nLOCATION: http://x/\r\n'), isNull);
      expect(ssdpLocation('HTTP/1.1 200 OK\r\nST: x\r\n'), isNull);
    });

    test('description of a renderer: name, brand and resolved control addresses', () {
      const xml = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:dlna="urn:schemas-dlna-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>[TV] Samsung Q60 &amp; co</friendlyName>
    <manufacturer>Samsung Electronics</manufacturer>
    <modelName>QE55Q60</modelName>
    <UDN>uuid:abcd-1234</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>RenderingControl/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/upnp/control/AVTransport1</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';
      final d = parseUpnpDescription(
        xml.replaceFirst(
          '</serviceList>',
          '<service><serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>'
              '<controlURL>/upnp/control/ConnectionManager1</controlURL></service></serviceList>',
        ),
        Uri.parse('http://192.168.1.20:9197/dmr/desc.xml'),
      )!;
      expect(d.connectionManager, Uri.parse('http://192.168.1.20:9197/upnp/control/ConnectionManager1'));
      expect(d.name, '[TV] Samsung Q60 & co');
      expect(d.id, 'uuid:abcd-1234');
      expect(d.protocol, CastProtocol.dlna);
      expect(d.avTransport, Uri.parse('http://192.168.1.20:9197/upnp/control/AVTransport1'));
      expect(d.renderingControl, Uri.parse('http://192.168.1.20:9197/dmr/RenderingControl/control'));
      expect(d.host, '192.168.1.20');
      expect(d.kindLabel, 'DLNA · Samsung');
    });

    test('URLBase is used, and devices without AVTransport are not renderers', () {
      const withBase = '''<root><URLBase>http://10.0.0.5:1400/</URLBase><device><friendlyName>Kodi</friendlyName>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:2</serviceType>
<controlURL>MediaRenderer/AVTransport/Control</controlURL></service></serviceList></device></root>''';
      final d = parseUpnpDescription(withBase, Uri.parse('http://10.0.0.5:8080/desc.xml'))!;
      expect(d.avTransport, Uri.parse('http://10.0.0.5:1400/MediaRenderer/AVTransport/Control'));
      expect(d.avTransportType, 'urn:schemas-upnp-org:service:AVTransport:2');
      expect(d.renderingControl, isNull);
      const server = '''<root><device><friendlyName>NAS</friendlyName><serviceList><service>
<serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType><controlURL>/cd</controlURL>
</service></serviceList></device></root>''';
      expect(parseUpnpDescription(server, Uri.parse('http://10.0.0.6/')), isNull);
    });
  });

  test('renderer answering one request per connection (Philips): every action gets through', () async {
    final actions = <String>[];
    var dropFirstSet = true;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((sock) {
      final buf = <int>[];
      var answered = false;
      sock.listen((chunk) {
        if (answered) return sock.destroy(); // a second request on this connection: dropped
        buf.addAll(chunk);
        final text = latin1.decode(buf);
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        final length = int.parse(RegExp(r'content-length: *(\d+)', caseSensitive: false).firstMatch(text)![1]!);
        if (buf.length < end + 4 + length) return;
        final action = RegExp(r'#(\w+)"').firstMatch(text)![1]!;
        if (action == 'SetAVTransportURI' && dropFirstSet) {
          dropFirstSet = false;
          return sock.destroy();
        }
        actions.add(action);
        answered = true;
        final inner = action == 'GetProtocolInfo' ? '<Sink>http-get:*:video/x-mkv:*</Sink>' : '';
        final body = utf8.encode(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
          '<u:${action}Response xmlns:u="x">$inner</u:${action}Response></s:Body></s:Envelope>',
        );
        // HTTP/1.1 without "Connection: close", then the socket stays open.
        sock.add(latin1.encode('HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nContent-Length: ${body.length}\r\n\r\n'));
        sock.add(body);
      }, onError: (Object _) {});
    });
    final base = 'http://127.0.0.1:${server.port}';
    final s = DlnaSession(
      CastDevice(
        id: 'philips',
        name: '50PUS8108/12',
        protocol: CastProtocol.dlna,
        host: '127.0.0.1',
        port: server.port,
        avTransport: Uri.parse('$base/av'),
        avTransportType: 'urn:schemas-upnp-org:service:AVTransport:1',
        connectionManager: Uri.parse('$base/cm'),
        connectionManagerType: 'urn:schemas-upnp-org:service:ConnectionManager:1',
      ),
    );
    await s.connect();
    expect(s.contentTypeFor('http://h/series/u/p/1.mkv', live: false), 'video/x-mkv');
    await s.load(
      const CastMedia(url: 'http://192.168.1.10:5000/c/t/m/1.mkv', contentType: 'video/x-mkv', live: false, title: 'É'),
    );
    await s.pause();
    expect(actions, ['GetProtocolInfo', 'SetAVTransportURI', 'Play', 'Pause']);
    await s.close();
    await server.close();
  });

  group('DLNA renderer', () {
    late HttpServer server;
    late List<(String, String)> calls;
    late String transportState;
    late Duration relTime;
    var failSeek = false;

    setUp(() async {
      calls = [];
      transportState = 'PLAYING';
      relTime = const Duration(minutes: 1, seconds: 2);
      failSeek = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await utf8.decodeStream(req);
        if (req.method == 'GET') {
          req.response.headers.contentType = ContentType('text', 'xml');
          req.response.write(
            '''<root><device><friendlyName>Salon</friendlyName><manufacturer>LG Electronics.</manufacturer>
<serviceList>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/av</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><controlURL>/rc</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType><controlURL>/cm</controlURL></service>
</serviceList></device></root>''',
          );
          return req.response.close();
        }
        final action = req.headers.value('SOAPACTION')!;
        final name = action.substring(action.indexOf('#') + 1, action.length - 1);
        calls.add((action, body));
        String inner = '';
        if (name == 'GetTransportInfo') {
          inner =
              '<CurrentTransportState>$transportState</CurrentTransportState>'
              '<CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed>';
        } else if (name == 'GetPositionInfo') {
          inner = '<Track>1</Track><TrackDuration>1:30:00</TrackDuration><RelTime>${formatUpnpTime(relTime)}</RelTime>';
        } else if (name == 'GetProtocolInfo') {
          inner =
              '<Source></Source><Sink>http-get:*:video/mp4:*,http-get:*:video/x-mkv:*,'
              'http-get:*:video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_EU_ISO</Sink>';
        } else if (name == 'GetVolume') {
          inner = '<CurrentVolume>30</CurrentVolume>';
        } else if (name == 'Seek' && failSeek) {
          req.response.statusCode = 500;
          req.response.write(
            '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
            '<detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>710</errorCode>'
            '<errorDescription>Seek mode not supported</errorDescription></UPnPError></detail>'
            '</s:Fault></s:Body></s:Envelope>',
          );
          return req.response.close();
        }
        req.response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
        req.response.write(
          '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
          '<u:${name}Response xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">$inner</u:${name}Response>'
          '</s:Body></s:Envelope>',
        );
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<CastDevice> device() async {
      final client = HttpClient();
      final d = await DlnaBrowser.fetchDescription(client, Uri.parse('http://127.0.0.1:${server.port}/desc.xml'));
      client.close();
      return d!;
    }

    test('loads with a description, plays, and reads position, length and volume', () async {
      final d = await device();
      expect(d.name, 'Salon');
      expect(d.kindLabel, 'DLNA · LG');
      final s = DlnaSession(d);
      await s.connect();
      expect(s.localAddress!.isLoopback, isTrue);
      // The TV's own spellings of the formats it accepts.
      expect(calls.single.$1, '"urn:schemas-upnp-org:service:ConnectionManager:1#GetProtocolInfo"');
      expect(s.sink, hasLength(3));
      expect(s.contentTypeFor('http://h/movie/u/p/1.mkv', live: false), 'video/x-mkv');
      expect(s.contentTypeFor('http://h/live/u/p/1.ts', live: true), 'video/vnd.dlna.mpeg-tts');
      expect(s.contentTypeFor('http://h/movie/u/p/1.mp4', live: false), 'video/mp4');
      calls.clear();
      await s.load(
        const CastMedia(
          url: 'http://192.168.1.10:5000/c/tok/m/film.mkv?a=1&b=2',
          contentType: 'video/x-matroska',
          live: false,
          title: 'Le <grand> film',
          image: 'http://img/poster.jpg',
        ),
      );
      expect(calls.map((c) => c.$1), [
        '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
        '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
      ]);
      final set = calls.first.$2;
      expect(set, contains('<CurrentURI>http://192.168.1.10:5000/c/tok/m/film.mkv?a=1&amp;b=2</CurrentURI>'));
      // The metadata is itself escaped XML inside the SOAP body.
      expect(set, contains('&lt;dc:title&gt;Le &amp;lt;grand&amp;gt; film&lt;/dc:title&gt;'));
      expect(set, contains('http-get:*:video/x-matroska:DLNA.ORG_OP=01'));
      final st = await s.poll();
      expect(st.state, RemoteState.playing);
      expect(st.position, const Duration(minutes: 1, seconds: 2));
      expect(st.duration, const Duration(hours: 1, minutes: 30));
      expect(st.volume, closeTo(0.3, 1e-9));
      await s.close();
    });

    test('seek, volume, pause; refused seek gives a French message', () async {
      final s = DlnaSession(await device());
      await s.connect();
      await s.seek(const Duration(minutes: 5, seconds: 7));
      expect(calls.last.$2, contains('<Unit>REL_TIME</Unit><Target>00:05:07</Target>'));
      await s.setVolume(0.55);
      expect(calls.last.$1, contains('RenderingControl:1#SetVolume'));
      expect(calls.last.$2, contains('<Channel>Master</Channel><DesiredVolume>55</DesiredVolume>'));
      await s.pause();
      expect(calls.last.$1, endsWith('#Pause"'));
      failSeek = true;
      await expectLater(
        s.seek(const Duration(seconds: 10)),
        throwsA(isA<CastException>().having((e) => e.message, 'message', contains("d'avancer"))),
      );
      await s.close();
    });

    test('a film stopped near its end is finished; earlier it is stopped', () async {
      final s = DlnaSession(await device());
      await s.connect();
      await s.load(const CastMedia(url: 'http://x/f.mp4', contentType: 'video/mp4', live: false, title: 'F'));
      transportState = 'TRANSITIONING';
      expect((await s.poll()).state, RemoteState.loading);
      transportState = 'PLAYING';
      relTime = const Duration(hours: 1, minutes: 29, seconds: 50);
      expect((await s.poll()).state, RemoteState.playing);
      transportState = 'STOPPED';
      expect((await s.poll()).state, RemoteState.ended);
      await s.load(const CastMedia(url: 'http://x/f.mp4', contentType: 'video/mp4', live: false, title: 'F'));
      transportState = 'PLAYING';
      relTime = const Duration(minutes: 3);
      await s.poll();
      transportState = 'STOPPED';
      expect((await s.poll()).state, RemoteState.idle);
      await s.close();
    });

    test('UPnP times', () {
      expect(formatUpnpTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
      expect(parseUpnpTime('0:00:07.500'), const Duration(seconds: 7, milliseconds: 500));
      expect(parseUpnpTime('NOT_IMPLEMENTED'), isNull);
      expect(parseUpnpTime(''), isNull);
    });
  });

  group('Google Cast', () {
    test('messages survive encoding and arbitrary chunking', () {
      const m = CastMessage(
        source: 'sender-0',
        destination: 'receiver-0',
        namespace: CastNs.receiver,
        payload: '{"type":"GET_STATUS","requestId":1,"t":"é"}',
      );
      final framed = [...frameCastMessage(m), ...frameCastMessage(m)];
      final reader = CastFrameReader();
      final out = <CastMessage>[];
      for (var i = 0; i < framed.length; i += 5) {
        out.addAll(reader.add(framed.sublist(i, i + 5 > framed.length ? framed.length : i + 5)));
      }
      expect(out, hasLength(2));
      expect(out.first.source, 'sender-0');
      expect(out.first.destination, 'receiver-0');
      expect(out.first.namespace, CastNs.receiver);
      expect(out.last.json['t'], 'é');
    });

    test('launches the media receiver, loads, controls and quits', () async {
      final fake = await _FakeChromecast.start();
      final s = ChromecastSession(
        const CastDevice(id: 'cc', name: 'Salon', protocol: CastProtocol.chromecast, host: '127.0.0.1', port: 0),
        connector: (host, port, timeout) => Socket.connect(host, fake.port, timeout: timeout),
      );
      final updates = <RemoteState>[];
      s.updates.listen((u) => updates.add(u.state));
      await s.connect();
      await s.load(
        const CastMedia(
          url: 'http://192.168.1.10:5000/c/t/m/film.mp4',
          contentType: 'video/mp4',
          live: false,
          title: 'Film',
          subtitle: '2024',
          image: 'http://img/p.jpg',
        ),
        start: const Duration(seconds: 30),
      );
      expect(fake.launched, isTrue);
      final load = fake.received.firstWhere((m) => m['type'] == 'LOAD');
      final media = load['media'] as Map;
      expect(media['contentId'], 'http://192.168.1.10:5000/c/t/m/film.mp4');
      expect(media['streamType'], 'BUFFERED');
      expect((media['metadata'] as Map)['title'], 'Film');
      expect(load['currentTime'], 30);
      expect(fake.mediaDestination, 'web-1');

      var st = await s.poll();
      expect(st.state, RemoteState.playing);
      expect(st.duration, const Duration(minutes: 90));
      await s.pause();
      expect((await s.poll()).state, RemoteState.paused);
      await s.seek(const Duration(minutes: 10));
      st = await s.poll();
      expect(st.position, const Duration(minutes: 10));
      await s.setVolume(0.4);
      expect(fake.volume, 0.4);
      expect(s.localAddress!.isLoopback, isTrue);
      expect(updates, contains(RemoteState.playing));

      fake.finish();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((await s.poll()).state, RemoteState.ended);

      await s.close();
      expect(fake.received.any((m) => m['type'] == 'STOP' && m['sessionId'] == 'sess-1'), isTrue);
      await fake.close();
    });

    test('a refused stream is an error; the app closed on the TV is noticed', () async {
      final fake = await _FakeChromecast.start(failLoad: true);
      final s = ChromecastSession(
        const CastDevice(id: 'cc', name: 'Salon', protocol: CastProtocol.chromecast, host: '127.0.0.1', port: 0),
        connector: (host, port, timeout) => Socket.connect(host, fake.port, timeout: timeout),
      );
      await s.connect();
      await expectLater(
        s.load(const CastMedia(url: 'http://x/live.ts', contentType: 'video/mp2t', live: true, title: 'TF1')),
        throwsA(isA<CastException>()),
      );
      fake.failLoad = false;
      await s.load(
        const CastMedia(url: 'http://x/live.m3u8', contentType: 'application/x-mpegURL', live: true, title: 'TF1'),
      );
      expect((fake.received.lastWhere((m) => m['type'] == 'LOAD')['media'] as Map)['streamType'], 'LIVE');
      fake.closeApp();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final st = await s.poll();
      expect(st.state, RemoteState.error);
      expect(st.error, contains('arrêtée'));
      await s.close();
      await fake.close();
    });
  });

  group('renderer formats', () {
    test('sink list keeps DLNA parameters whole', () {
      expect(
        parseSinkProtocols(
          ' http-get:*:video/mp4:*, http-get:*:video/mpeg:DLNA.ORG_PN=MPEG_TS_SD_EU,x ,,http-get:*:image/jpeg:*',
        ),
        ['http-get:*:video/mp4:*', 'http-get:*:video/mpeg:DLNA.ORG_PN=MPEG_TS_SD_EU,x', 'http-get:*:image/jpeg:*'],
      );
    });

    test('the TV spelling of the same format is announced', () {
      const philips = [
        'http-get:*:video/x-matroska:*',
        'http-get:*:video/MP2T:*',
        'http-get:*:video/avi:*',
        'rtsp-rtp-udp:*:video/x-mkv:*',
      ];
      expect(rendererMime('video/x-matroska', philips), 'video/x-matroska');
      expect(rendererMime('video/mp2t', philips), 'video/MP2T');
      expect(rendererMime('video/x-msvideo', philips), 'video/avi');
      expect(rendererMime('video/mp4', philips), 'video/mp4');
      expect(rendererMime('video/x-matroska', const ['http-get:*:video/x-mkv:*']), 'video/x-mkv');
      expect(rendererMime('video/quicktime', const ['http-get:*:video/mp4:*']), 'video/mp4');
      expect(rendererMime('video/x-matroska', const ['http-get:*:*:*']), 'video/x-matroska');
      expect(rendererMime('video/x-matroska', const []), 'video/x-matroska');
    });
  });

  group('address of this computer for the TV', () {
    test('the one on the TV network, never the TV itself', () {
      final tv = InternetAddress('192.168.1.67');
      final mine = [
        InternetAddress('10.8.0.2'), // VPN
        InternetAddress('172.17.0.1'), // Docker / Hyper-V
        InternetAddress('192.168.56.1'), // VirtualBox
        InternetAddress('192.168.1.20'), // Wi-Fi
      ];
      expect(pickLocalAddress(tv, mine)!.address, '192.168.1.20');
      expect(pickLocalAddress(tv, [...mine, tv])!.address, '192.168.1.20');
      expect(pickLocalAddress(tv, [InternetAddress('10.8.0.2')]), isNull);
      // Bigger networks: the closest addresses are tried first.
      final far = InternetAddress('10.0.2.7');
      expect(pickLocalAddress(far, [InternetAddress('192.168.1.20'), InternetAddress('10.0.1.5')]), isNull);
      expect(
        candidatesByPrefix(far, [InternetAddress('192.168.1.20'), InternetAddress('10.0.1.5')]).first.address,
        '10.0.1.5',
      );
    });

    test('a renderer on this computer, or on loopback, is reached at its own address', () async {
      expect((await localAddressFor('127.0.0.1', 1))!.isLoopback, isTrue);
      final mine = await localIPv4();
      if (mine.isNotEmpty) expect((await localAddressFor(mine.first.$2.address, 1))!.address, mine.first.$2.address);
    });
  });

  group('cast addresses', () {
    test('Xtream live channels are asked in HLS for Chromecast only', () {
      const ts = 'http://host:8080/live/user/pass/123.ts';
      expect(castUrl(ts, CastProtocol.chromecast), 'http://host:8080/live/user/pass/123.m3u8');
      expect(castUrl('$ts?token=1', CastProtocol.chromecast), 'http://host:8080/live/user/pass/123.m3u8?token=1');
      expect(castUrl(ts, CastProtocol.dlna), ts);
      const movie = 'http://host:8080/movie/user/pass/9.mkv';
      expect(castUrl(movie, CastProtocol.chromecast), movie);
    });

    test('content types', () {
      String t(String u, {bool live = false, CastProtocol p = CastProtocol.dlna}) =>
          castContentType(u, live: live, protocol: p);
      expect(t('http://h/a/b.m3u8?x=1'), 'application/x-mpegURL');
      expect(t('http://h/live/u/p/1.ts', live: true), 'video/mp2t');
      expect(t('http://h/movie/u/p/1.mkv'), 'video/x-matroska');
      expect(t('http://h/movie/u/p/1.mkv', p: CastProtocol.chromecast), 'video/mp4');
      expect(t('http://h/stream/42', live: true), 'video/mp2t');
      expect(t('http://h/stream/42'), 'video/mp4');
      expect(t(r'C:\Users\me\Videos\Bobine\TF1.ts'), 'video/mp2t');
      expect(isLocalMedia(r'C:\Videos\a.ts'), isTrue);
      expect(isLocalMedia('/home/me/a.ts'), isTrue);
      expect(isLocalMedia('https://h/a.ts'), isFalse);
      expect(isHlsUrl('http://h/index.m3u8?t=1'), isTrue);
    });
  });
}

/// A Cast device on a plain socket: answers like the Default Media Receiver.
class _FakeChromecast {
  _FakeChromecast._(this._server, this.failLoad);

  static Future<_FakeChromecast> start({bool failLoad = false}) async {
    final f = _FakeChromecast._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), failLoad);
    f._server.listen(f._onClient);
    return f;
  }

  final ServerSocket _server;
  bool failLoad;
  Socket? _client;
  final received = <Map<String, Object?>>[];
  bool launched = false;
  String? mediaDestination;
  double volume = 1;
  String playerState = 'BUFFERING';
  double currentTime = 0;
  String? idleReason;

  int get port => _server.port;

  void _onClient(Socket c) {
    _client = c;
    final reader = CastFrameReader();
    c.listen((chunk) {
      for (final m in reader.add(chunk)) {
        _onMessage(m);
      }
    }, onError: (Object _) {});
  }

  void _send(String ns, String to, Map<String, Object?> payload, {String from = 'receiver-0'}) {
    _client?.add(
      frameCastMessage(CastMessage(source: from, destination: to, namespace: ns, payload: jsonEncode(payload))),
    );
  }

  Map<String, Object?> _receiverStatus(int id) => {
    'type': 'RECEIVER_STATUS',
    'requestId': id,
    'status': {
      if (launched)
        'applications': [
          {'appId': kDefaultMediaReceiver, 'sessionId': 'sess-1', 'transportId': 'web-1', 'displayName': 'Default'},
        ],
      'volume': {'level': volume, 'muted': false},
    },
  };

  Map<String, Object?> _mediaStatus(int id) => {
    'type': 'MEDIA_STATUS',
    'requestId': id,
    'status': [
      {
        'mediaSessionId': 1,
        'playerState': playerState,
        'currentTime': currentTime,
        'idleReason': ?idleReason,
        'media': {'duration': 5400},
      },
    ],
  };

  void _onMessage(CastMessage m) {
    final json = m.json;
    received.add(json);
    final id = (json['requestId'] as num?)?.toInt() ?? 0;
    switch ((m.namespace, json['type'])) {
      case (CastNs.heartbeat, 'PING'):
        _send(CastNs.heartbeat, m.source, {'type': 'PONG'});
      case (CastNs.receiver, 'GET_STATUS'):
        _send(CastNs.receiver, m.source, _receiverStatus(id));
      case (CastNs.receiver, 'LAUNCH'):
        launched = true;
        _send(CastNs.receiver, m.source, _receiverStatus(id));
      case (CastNs.receiver, 'SET_VOLUME'):
        volume = ((json['volume'] as Map)['level'] as num).toDouble();
        _send(CastNs.receiver, m.source, _receiverStatus(id));
      case (CastNs.receiver, 'STOP'):
        launched = false;
        _send(CastNs.receiver, m.source, _receiverStatus(id));
      case (CastNs.media, 'LOAD'):
        mediaDestination = m.destination;
        if (failLoad) {
          _send(CastNs.media, m.source, {'type': 'LOAD_FAILED', 'requestId': id}, from: 'web-1');
          return;
        }
        currentTime = ((json['currentTime'] as num?) ?? 0).toDouble();
        playerState = 'BUFFERING';
        _send(CastNs.media, m.source, _mediaStatus(id), from: 'web-1');
        playerState = 'PLAYING';
      case (CastNs.media, 'PAUSE'):
        playerState = 'PAUSED';
        _send(CastNs.media, m.source, _mediaStatus(id), from: 'web-1');
      case (CastNs.media, 'PLAY'):
        playerState = 'PLAYING';
        _send(CastNs.media, m.source, _mediaStatus(id), from: 'web-1');
      case (CastNs.media, 'SEEK'):
        currentTime = (json['currentTime'] as num).toDouble();
        _send(CastNs.media, m.source, _mediaStatus(id), from: 'web-1');
      case (CastNs.media, 'GET_STATUS' || 'STOP'):
        _send(CastNs.media, m.source, _mediaStatus(id), from: 'web-1');
    }
  }

  /// The film reaches its end.
  void finish() {
    playerState = 'IDLE';
    idleReason = 'FINISHED';
    _send(CastNs.media, 'sender-bobine', _mediaStatus(0), from: 'web-1');
  }

  /// Someone quits the player on the TV.
  void closeApp() {
    launched = false;
    _send(CastNs.receiver, 'sender-bobine', _receiverStatus(0));
  }

  Future<void> close() async {
    _client?.destroy();
    await _server.close();
  }
}
