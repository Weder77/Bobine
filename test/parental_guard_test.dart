import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/ui/widgets/pin_dialog.dart';

void main() {
  test('what can undo the parental control asks the code: always in a kids profile, elsewhere until typed', () {
    // No code: nothing to protect.
    expect(codeNeeded(enabled: false, kids: true, unlocked: false), isFalse);
    expect(codeNeeded(enabled: false, kids: false, unlocked: false), isFalse);
    // A kids profile: always, even after the code was typed for the categories.
    expect(codeNeeded(enabled: true, kids: true, unlocked: false), isTrue);
    expect(codeNeeded(enabled: true, kids: true, unlocked: true), isTrue);
    // Another profile: until the code was typed this session.
    expect(codeNeeded(enabled: true, kids: false, unlocked: false), isTrue);
    expect(codeNeeded(enabled: true, kids: false, unlocked: true), isFalse);
  });
}
