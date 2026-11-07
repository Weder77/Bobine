import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/version.dart';

void main() {
  test('kAppVersion matches pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':').last.trim().split('+').first, kAppVersion);
  });

  test('versions compare numerically', () {
    expect(compareVersions('1.10.0', '1.9.3'), 1);
    expect(compareVersions('v1.1.0', '1.1.0+5'), 0);
    expect(compareVersions('1.1', '1.1.1'), -1);
  });
}
