import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/core/net.dart';

// A self-signed certificate made for this test only (localhost).
const _cert = '''
-----BEGIN CERTIFICATE-----
MIIDCzCCAfOgAwIBAgIUHieN2vUUCB1UzqTynTKMSd2Jx+YwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MTExMTE3MzkwMloYDzIxMjYx
MDE4MTczOTAyWjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQDlT4CldVWfmOBlGw1PybsS7kmFlkMbygSHsDCO86Ou
+gtjrkOoCD/gfjZUZsi3nzu9o8xVH+SehH5LiL5+5m5HwSlJr6YkP2mfoD5w1bCZ
o0QRiH4ZBg3jeenzvDGdMMd/tagP9+a0Ga8LxqM4cLNhW8d2VceesOtg8k6r5Zo6
zqi6VGX2M1pS1MWTU4Ujjmr2hhnwdMN93FaGR3j/u1kYFiuNRfq0cOT0lm/D5cjy
NeQ3rmeZ691SlytruA6zUoXg8esPx3cD+U6rOISPFMLByKNhJ49PwZvGKyN7qXzP
jm+sJzBoUEIs/rxbyo2ZgZ865KelTQWkht7ju+a54XC3AgMBAAGjUzBRMB0GA1Ud
DgQWBBSX2xZwvvWV7nviPt3+YwhSIro/BDAfBgNVHSMEGDAWgBSX2xZwvvWV7nvi
Pt3+YwhSIro/BDAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQC/
2+GPDzoPG5lMlwlWMAJxkEYMN42fXuzmNDlxrsnx/XcJy8sS8hjqHZOKP4jPDvnH
4mtYvzloRBNkT/aMckRfZ3EAAOO+sNQpML7DNVJLMBmkj+bEae63ZPo8pNhshR78
S2aXblvMz2ogGwI4WJL9dgxfaUpEXlg4RAsO4MaEvZ2w07Oy5LNtSn15et8aXlzB
9PJmmEu3b4xYKMQt/dRjutUw1cn8OhYC7URgUOh0nsHY4tBTDgeSv5YVO62KbsEy
VkMKsMiDPOL74+uGT0D7UfwJAWPMY3Bxe+uBBFN2hTR2M+0FwmHz5SQRbXKaEMMs
J7gQUEablxk6OkJognpS
-----END CERTIFICATE-----
''';
const _key = '''
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDlT4CldVWfmOBl
Gw1PybsS7kmFlkMbygSHsDCO86Ou+gtjrkOoCD/gfjZUZsi3nzu9o8xVH+SehH5L
iL5+5m5HwSlJr6YkP2mfoD5w1bCZo0QRiH4ZBg3jeenzvDGdMMd/tagP9+a0Ga8L
xqM4cLNhW8d2VceesOtg8k6r5Zo6zqi6VGX2M1pS1MWTU4Ujjmr2hhnwdMN93FaG
R3j/u1kYFiuNRfq0cOT0lm/D5cjyNeQ3rmeZ691SlytruA6zUoXg8esPx3cD+U6r
OISPFMLByKNhJ49PwZvGKyN7qXzPjm+sJzBoUEIs/rxbyo2ZgZ865KelTQWkht7j
u+a54XC3AgMBAAECggEADWo7QnK80Ztl9URB4RsSIKdkEbaasnN9FFsQXCyQtNnX
9LrrJldlNULs9r8Umvlry0pb19cHzuY9ZTnYux/L79KzEaZ+97vl9/qt7Hfz3ukY
QFZV2izqfxZQw3uNA38pDKWZ8WU1T+/4t52lStX9CIMQBjI6fWQoQQGr7I6AGVSF
XR3Mwy1Ah1FwI2k75o7wMEykR9RLD+0Z/+I3UXnCqi+GBYih8jotlAfboE9fghhQ
PnSqt24at06P0xPzsjxOMGC/NUBz0TH3A6Gdz8hHfK0QUGzlJTqdmc/iOHV1rDGk
eq1A5K1X9971AdiWdMNR/l/tQr2Kz6Cjig+a4KhsoQKBgQDzG4/EzcNxOrAYvGc7
vt1W7O2hZFzRyynqGj2TOM8f8/oko2uZjUg0EWpqn5E/aFtoxdnnq7F8fEEUgZUr
ebeW7O7athr9jJGjAHDZU2D+APFAvUHRGwlWHKc2Bkrhss+Y6515TZvokyFxRkYT
NTHo/p7qbfsinkifTEZTexxdLwKBgQDxeKGEHTf54e1s0PScvMX+lo98HxW/eLqT
FVsCxreZKU4XZvAue67HtYnKGupiLdrcNhN0CfMwzSuMMELAoAgkdTfXMcRwz0pH
AN9Xz0KS4NrKkewMUdkRay+G4BdJJAChUGFqDiK/AwiixHwLdjiO/pTSAQxXZRg+
nDC9BrqS+QKBgGRsPjdNyC490ABn0z0a2tPNi1vf2XfQNMA/lq/6B5VrcykvWINV
mT3o88yXnahTs27US+8nPWnu6fNOlBAhd3Ug6onuL7gNGRv8UqFzj91dBkt34ng+
ctzfeTMX5lbVRmwk6CfzpzOrk2T3YnsMvlFA3OR6CgOC3vzuxR42/MCBAoGAUG+1
pfOxvMyUsWXdxgRgFBGFVHxqWzDVPb+kZIVbjWqj98mzglhy/VWsw6U5pGDQAgEF
c+cImp4NvpIo+k+UxshBRK7wV//FJ2fT/kUtUQ4T89yt++Cb5WCGIXCucQ/MIfBL
su9ohaZ2DvpSs+K6rm+BlX8B5G7pp5mR5rXCGskCgYA8ow7dWkOKcfc2WyUp8OAh
9LRSfKHf6u1pIEk2ygwO2TSwwuf1msTDwVgBxzingNteZ1ZHmxJGm7qxamiS+UFW
oCSF/vjKcCFupSBvZex2jobW3RkG2x1sTGqfv/XW5TCp6qIAaRk5TtkBfKSzJAnQ
YRokjF9tdyXgEGO0TqXCLQ==
-----END PRIVATE KEY-----
''';

void main() {
  late HttpServer server;
  setUp(() async {
    final ctx = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(_cert))
      ..usePrivateKeyBytes(utf8.encode(_key));
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
    server.listen((r) async {
      r.response.write('#EXTM3U');
      await r.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  test('an invalid certificate is refused, unless the source accepts it', () async {
    final uri = Uri.parse('https://127.0.0.1:${server.port}/list.m3u');
    final strict = createHttpClient();
    addTearDown(() => strict.close(force: true));
    await expectLater(
      openGet(strict, uri),
      throwsA(isA<NetException>().having((e) => e.message, 'message', kBadCertificateMessage)),
    );

    final lenient = createHttpClient(acceptInvalidCertificate: true);
    addTearDown(() => lenient.close(force: true));
    final res = await openGet(lenient, uri);
    expect(await utf8.decodeStream(res), '#EXTM3U');

    final byHost = createHttpClient(acceptFor: (h) => h == '127.0.0.1');
    addTearDown(() => byHost.close(force: true));
    expect((await openGet(byHost, uri)).statusCode, 200);
  });
}
