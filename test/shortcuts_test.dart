import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/ui/shell.dart';

void main() {
  testWidgets('typing in a text field is seen as typing', (tester) async {
    final field = FocusNode(), button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: field),
              TextButton(focusNode: button, onPressed: () {}, child: const Text('Bouton')),
            ],
          ),
        ),
      ),
    );
    field.requestFocus();
    await tester.pump();
    expect(focusIsInTextField(), isTrue);
    button.requestFocus();
    await tester.pump();
    expect(focusIsInTextField(), isFalse);
  });
}
