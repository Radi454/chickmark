import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/widgets/audit_keyboard_dismiss.dart';

void main() {
  testWidgets('dismisses focused audit input when tapping outside it', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditKeyboardDismiss(
            child: Column(
              children: [
                TextField(focusNode: focusNode),
                const SizedBox(height: 120, child: Text('Audit content')),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Audit content'));
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('can leave focused audit input active for custom keypad sheets', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditKeyboardDismiss(
            enabled: false,
            child: Column(
              children: [
                TextField(focusNode: focusNode),
                const SizedBox(height: 120, child: Text('Scrollable sheet')),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Scrollable sheet'));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });
}
