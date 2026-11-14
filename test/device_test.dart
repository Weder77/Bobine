import 'package:bobine/core/device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => Device.debugTv = null);

  test("sur la télé, les fonctions de l'ordinateur sont coupées", () {
    Device.debugTv = true;
    expect(Device.isTv, isTrue);
    expect([
      Device.canCast,
      Device.canRecord,
      Device.canPickFiles,
      Device.canSelfUpdate,
      Device.seekPreview,
    ], everyElement(isFalse));
    expect(Device.maxMultiSlots, 2);
    expect(Device.backKey, 'Retour');
  });

  test("sur l'ordinateur, rien ne change", () {
    Device.debugTv = false;
    expect(Device.isTv, isFalse);
    expect(Device.maxMultiSlots, 4);
    expect(Device.backKey, 'Échap');
    expect([
      Device.canCast,
      Device.canRecord,
      Device.canPickFiles,
      Device.canSelfUpdate,
      Device.seekPreview,
    ], everyElement(isTrue));
  });

  test('sans forçage, la télé est Android (les tests tournent sur ordinateur)', () {
    expect(Device.isTv, isFalse);
  });
}
