import 'dart:convert';
import 'dart:io';

import 'package:bobine/cast/cast_test_run.dart';
import 'package:bobine/cast/dlna.dart';
import 'package:bobine/cast/relay.dart';
import 'package:bobine/cast/ssdp.dart';
import 'package:flutter_test/flutter_test.dart';

/// A TV like the Philips 50PUS8108: it lists "video/x-mkv" but answers
/// SetAVTransportURI with 714 Illegal MIME-type when the file is announced
/// so (it checks with HEAD); it plays "video/x-matroska".
class FakePhilips {
  FakePhilips._(this.server);
  final HttpServer server;
  final _client = HttpClient();
  final calls = <String>[];
  String? uri;
  String state = 'NO_MEDIA_PRESENT';
  Duration position = Duration.zero;

  static Future<FakePhilips> start() async {
    final f = FakePhilips._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    f.server.listen(f._handle);
    return f;
  }

  Uri get description => Uri.parse('http://127.0.0.1:${server.port}/desc.xml');

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decodeStream(req);
    final res = req.response;
    if (req.method == 'GET') {
      res.write(
        '''<root><device><friendlyName>50PUS8108/12(127.0.0.1)</friendlyName><manufacturer>Smart TV</manufacturer>
<serviceList>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/av</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType><controlURL>/cm</controlURL></service>
</serviceList></device></root>''',
      );
      return res.close();
    }
    final action = RegExp(r'#(\w+)"').firstMatch(req.headers.value('SOAPACTION')!)![1]!;
    calls.add(action);
    var inner = '';
    String? fault;
    switch (action) {
      case 'GetProtocolInfo':
        inner = '<Sink>http-get:*:video/mp4:*,http-get:*:video/x-mkv:*,http-get:*:video/mpeg:*</Sink>';
      case 'SetAVTransportURI':
        final url = soapValue(body, 'CurrentURI')!;
        final head = await (await _client.headUrl(Uri.parse(url))).close();
        await head.drain<void>();
        final type = head.headers.contentType?.mimeType;
        if (type == 'video/x-mkv') {
          fault = '714';
        } else {
          uri = url;
          state = 'STOPPED';
        }
      case 'Play':
        if (uri == null) {
          fault = '716';
          break;
        }
        state = 'TRANSITIONING';
        final req = await _client.getUrl(Uri.parse(uri!));
        req.headers.set('Range', 'bytes=0-');
        final media = await req.close();
        var got = 0;
        await for (final c in media) {
          got += c.length;
          if (got > 2 << 20) break;
        }
        state = 'PLAYING';
        position = const Duration(seconds: 3);
      case 'Stop':
        state = 'STOPPED';
        uri = null;
      case 'GetTransportInfo':
        inner =
            '<CurrentTransportState>$state</CurrentTransportState><CurrentTransportStatus>OK</CurrentTransportStatus>';
      case 'GetPositionInfo':
        inner = '<RelTime>${formatUpnpTime(position)}</RelTime><TrackDuration>0:45:00</TrackDuration>';
    }
    if (fault != null) {
      res.statusCode = 500;
      res.write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><detail>'
        '<UPnPError><errorCode>$fault</errorCode><errorDescription>'
        '${fault == '714' ? 'Illegal MIME-type' : 'Invalid CurrentURI Value'}</errorDescription></UPnPError>'
        '</detail></s:Fault></s:Body></s:Envelope>',
      );
    } else {
      res.write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
        '<u:${action}Response xmlns:u="x">$inner</u:${action}Response></s:Body></s:Envelope>',
      );
    }
    await res.close();
  }

  Future<void> close() async {
    _client.close(force: true);
    await server.close(force: true);
  }
}

void main() {
  test('variants: Bobine first, then the TV spellings, forced types, direct', () {
    final v = castVariants('https://h/series/u/p/1.mkv', const [
      'http-get:*:video/x-mkv:*',
      'http-get:*:video/x-matroska:DLNA.ORG_PN=MKV',
      'http-get:*:video/mp4:*',
    ], live: false);
    expect(v.map((x) => x.label).toList(), [
      'video/x-matroska, description de Bobine',
      'video/x-matroska, sans description',
      'video/x-mkv, comme dans la liste de la télé (*)',
      'video/x-matroska, comme dans la liste de la télé (DLNA.ORG_PN=MKV)',
      'video/x-matroska, sans drapeaux DLNA (*)',
      'video/x-mkv, sans description',
      'video/mp4 (type forcé)',
      'video/mpeg (type forcé)',
      'adresse du fournisseur en direct, video/x-matroska',
    ]);
  });

  test('finds the way the Philips plays a MKV, and reports it', () async {
    final tv = await FakePhilips.start();
    final dir = await Directory.systemTemp.createTemp('bobine_cast_test');
    final file = File('${dir.path}/episode.mkv');
    await file.writeAsBytes(List.filled(3 << 20, 7));
    final client = HttpClient();
    final device = (await DlnaBrowser.fetchDescription(client, tv.description))!;
    client.close();
    final session = DlnaSession(device);
    await session.connect();
    final requests = <RelayRequest>[];
    final relay = CastRelay(onRequest: requests.add);
    final lines = <String>[];
    final results = await CastTester(
      session,
      relay,
      say: lines.add,
      watch: const Duration(seconds: 3),
    ).run(file.path, live: false);

    final byLabel = {for (final r in results) r.variant.label: r};
    expect(byLabel['video/x-mkv, comme dans la liste de la télé (*)']!.refusal, '714 Illegal MIME-type');
    final winner = results.firstWhere((r) => r.played);
    expect(winner.variant.label, 'video/x-matroska, description de Bobine');
    expect(winner.states.last, 'PLAYING');
    expect(winner.bytes, greaterThan(1 << 20));
    final report = castTestReport(
      session: session,
      target: file.path,
      results: results,
      requests: requests,
      log: lines,
    );
    expect(report, contains('LUE'));
    expect(report, contains('HEAD episode.mkv'));
    expect(report, contains('http-get:*:video/x-mkv:*'));
    await relay.close();
    await session.close();
    await tv.close();
    await dir.delete(recursive: true);
  });
}
