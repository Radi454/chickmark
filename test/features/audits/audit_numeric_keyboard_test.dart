import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/widgets/audit_numeric_browser_policy.dart';
import 'package:hatchaudit/features/audits/widgets/audit_numeric_keyboard.dart';

void main() {
  group('browser platform policy', () {
    test('uses system keyboard for Mac web even without pointer support', () {
      expect(
        auditNumericBrowserPrefersSystemKeyboard(
          platform: 'MacIntel',
          userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
          hasDesktopPointer: false,
        ),
        isTrue,
      );
    });

    test('uses system keyboard for Windows and Linux web', () {
      expect(
        auditNumericBrowserPrefersSystemKeyboard(
          platform: 'Win32',
          userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          hasDesktopPointer: false,
        ),
        isTrue,
      );
      expect(
        auditNumericBrowserPrefersSystemKeyboard(
          platform: 'Linux x86_64',
          userAgent: 'Mozilla/5.0 (X11; Linux x86_64)',
          hasDesktopPointer: false,
        ),
        isTrue,
      );
    });

    test('keeps custom keyboard policy for mobile web platforms', () {
      expect(
        auditNumericBrowserPrefersSystemKeyboard(
          platform: 'iPhone',
          userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
          hasDesktopPointer: true,
        ),
        isFalse,
      );
      expect(
        auditNumericBrowserPrefersSystemKeyboard(
          platform: 'Linux armv8l',
          userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel)',
          hasDesktopPointer: true,
        ),
        isFalse,
      );
    });
  });

  testWidgets('tapping digits and decimal updates the active field', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            inputMode: AuditNumericInputMode.customKeyboard,
            child: Center(
              child: AuditNumericField(
                controller: controller,
                focusNode: focusNode,
                allowDecimal: true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7'));
    await tester.tap(find.text('8'));
    await tester.tap(find.text('.'));
    await tester.tap(find.text('9'));
    await tester.pump();

    expect(controller.text, '78.9');
  });

  testWidgets(
    'decimal key is inert and bottom-left hides when negative is disallowed',
    (tester) async {
      final controller = TextEditingController();

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditNumericKeyboardScope(
              inputMode: AuditNumericInputMode.customKeyboard,
              child: AuditNumericField(controller: controller),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuditNumericField));
      await tester.pumpAndSettle();

      expect(find.text('-'), findsNothing);
      expect(find.text('.'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_hide), findsOneWidget);

      await tester.tap(find.text('.'));
      await tester.pump();

      expect(controller.text, isEmpty);

      await tester.tap(find.byIcon(Icons.keyboard_hide));
      await tester.pumpAndSettle();

      expect(find.byType(AuditNumericKeyboard), findsNothing);
    },
  );

  testWidgets('negative key remains available when allowed', (tester) async {
    final controller = TextEditingController();

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            inputMode: AuditNumericInputMode.customKeyboard,
            child: AuditNumericField(
              controller: controller,
              allowNegative: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField));
    await tester.pumpAndSettle();

    expect(find.text('-'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_hide), findsNothing);

    await tester.tap(find.text('-'));
    await tester.pump();

    expect(controller.text, '-');
  });

  testWidgets('backspace removes one character', (tester) async {
    final controller = TextEditingController(text: '123');

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            inputMode: AuditNumericInputMode.customKeyboard,
            child: AuditNumericField(controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();

    expect(controller.text, '12');
  });

  testWidgets('next moves to the next numeric field', (tester) async {
    final firstController = TextEditingController();
    final secondController = TextEditingController();
    final firstFocusNode = FocusNode();
    final secondFocusNode = FocusNode();

    addTearDown(() {
      firstController.dispose();
      secondController.dispose();
      firstFocusNode.dispose();
      secondFocusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            inputMode: AuditNumericInputMode.customKeyboard,
            child: Column(
              children: [
                AuditNumericField(
                  controller: firstController,
                  focusNode: firstFocusNode,
                ),
                AuditNumericField(
                  controller: secondController,
                  focusNode: secondFocusNode,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('7'));
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8'));
    await tester.pump();

    expect(firstController.text, '7');
    expect(secondController.text, '8');
    expect(secondFocusNode.hasFocus, isTrue);
  });

  testWidgets('bottom-left hide action closes the keypad', (tester) async {
    final controller = TextEditingController();

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            inputMode: AuditNumericInputMode.customKeyboard,
            child: AuditNumericField(controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_hide), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_hide));
    await tester.pumpAndSettle();

    expect(find.byType(AuditNumericKeyboard), findsNothing);
  });

  testWidgets(
    'lower-right action moves to the field below in the same column',
    (tester) async {
      final controllers = List.generate(4, (_) => TextEditingController());
      final focusNodes = List.generate(4, (_) => FocusNode());

      addTearDown(() {
        for (final controller in controllers) {
          controller.dispose();
        }
        for (final focusNode in focusNodes) {
          focusNode.dispose();
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditNumericKeyboardScope(
              inputMode: AuditNumericInputMode.customKeyboard,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AuditNumericField(
                          controller: controllers[0],
                          focusNode: focusNodes[0],
                          navigationGroup: 'grid',
                          navigationRow: 0,
                          navigationColumn: 0,
                        ),
                      ),
                      Expanded(
                        child: AuditNumericField(
                          controller: controllers[1],
                          focusNode: focusNodes[1],
                          navigationGroup: 'grid',
                          navigationRow: 0,
                          navigationColumn: 1,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: AuditNumericField(
                          controller: controllers[2],
                          focusNode: focusNodes[2],
                          navigationGroup: 'grid',
                          navigationRow: 1,
                          navigationColumn: 0,
                        ),
                      ),
                      Expanded(
                        child: AuditNumericField(
                          controller: controllers[3],
                          focusNode: focusNodes[3],
                          navigationGroup: 'grid',
                          navigationRow: 1,
                          navigationColumn: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuditNumericField).at(1));
      await tester.pumpAndSettle();

      final rightColumnX = tester
          .getCenter(find.byIcon(Icons.keyboard_return))
          .dx;
      final rowThreeY = tester.getCenter(find.text('1')).dy;
      await tester.tapAt(Offset(rightColumnX, rowThreeY));
      await tester.pumpAndSettle();

      expect(focusNodes[3].hasFocus, isTrue);
      expect(find.byType(AuditNumericKeyboard), findsOneWidget);
    },
  );

  testWidgets('lower-right action falls back to normal next field order', (
    tester,
  ) async {
    final firstController = TextEditingController();
    final secondController = TextEditingController();
    final firstFocusNode = FocusNode();
    final secondFocusNode = FocusNode();

    addTearDown(() {
      firstController.dispose();
      secondController.dispose();
      firstFocusNode.dispose();
      secondFocusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            inputMode: AuditNumericInputMode.customKeyboard,
            child: Column(
              children: [
                AuditNumericField(
                  controller: firstController,
                  focusNode: firstFocusNode,
                ),
                AuditNumericField(
                  controller: secondController,
                  focusNode: secondFocusNode,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_return));
    await tester.pumpAndSettle();

    expect(secondFocusNode.hasFocus, isTrue);
    expect(find.byType(AuditNumericKeyboard), findsOneWidget);
  });

  testWidgets('lower-right action does not close when no next target exists', (
    tester,
  ) async {
    final controller = TextEditingController();

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            inputMode: AuditNumericInputMode.customKeyboard,
            child: AuditNumericField(controller: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_return));
    await tester.pumpAndSettle();

    expect(find.byType(AuditNumericKeyboard), findsOneWidget);
  });

  testWidgets('keypad rows ignore inherited top media padding', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(430, 932),
          padding: EdgeInsets.only(top: 120, bottom: 34),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Material(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AuditNumericKeyboard(
                allowDecimal: true,
                allowNegative: true,
                hasNext: true,
                hasMoveDown: true,
                onDigit: (_) {},
                onDecimal: () {},
                onNegative: () {},
                onBackspace: () {},
                onNext: () {},
                onMoveDown: () {},
                onHide: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final keyboardTop = tester.getTopLeft(find.byType(AuditNumericKeyboard)).dy;
    final sevenTop = tester.getTopLeft(find.text('7')).dy;

    expect(sevenTop - keyboardTop, lessThan(80));
  });

  testWidgets('keypad overlay paints the bottom safe area', (tester) async {
    final controller = TextEditingController();

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(430, 932),
          padding: EdgeInsets.only(bottom: 34),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: AuditNumericKeyboardScope(
              inputMode: AuditNumericInputMode.customKeyboard,
              child: AuditNumericField(controller: controller),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AuditNumericField));
    await tester.pumpAndSettle();

    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('audit_numeric_keyboard_safe_area')),
    );
    expect(surface.color, const Color(0xFFCDD2DC));
  });

  testWidgets(
    'desktop platforms use normal text input instead of the custom keypad',
    (tester) async {
      final controller = TextEditingController();
      var changedValue = '';

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditNumericKeyboardScope(
              inputMode: AuditNumericInputMode.systemKeyboard,
              child: AuditNumericField(
                controller: controller,
                allowDecimal: true,
                maxDecimalPlaces: 1,
                onChanged: (value) => changedValue = value,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuditNumericField));
      await tester.pumpAndSettle();

      expect(find.byType(AuditNumericKeyboard), findsNothing);

      await tester.enterText(find.byType(AuditNumericField), '78.9');
      await tester.pump();

      expect(controller.text, '78.9');
      expect(changedValue, '78.9');
    },
  );

  testWidgets('adaptive mode uses normal text input on macOS targets', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditNumericKeyboardScope(
              child: AuditNumericField(controller: controller),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuditNumericField));
      await tester.pumpAndSettle();

      expect(find.byType(AuditNumericKeyboard), findsNothing);

      await tester.enterText(find.byType(AuditNumericField), '42');
      await tester.pump();

      expect(controller.text, '42');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('adaptive mode uses native numeric input on iOS targets', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditNumericKeyboardScope(
              child: AuditNumericField(
                controller: controller,
                allowDecimal: true,
                allowNegative: true,
                maxDecimalPlaces: 1,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuditNumericField));
      await tester.pumpAndSettle();

      expect(find.byType(AuditNumericKeyboard), findsNothing);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isFalse);
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(decimal: true, signed: true),
      );

      await tester.enterText(find.byType(AuditNumericField), '12.3');
      await tester.pump();
      expect(controller.text, '12.3');

      await tester.enterText(find.byType(AuditNumericField), '12.34');
      await tester.pump();
      expect(controller.text, '12.3');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('adaptive mode keeps the custom keypad on Android targets', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditNumericKeyboardScope(
              child: AuditNumericField(controller: controller),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuditNumericField));
      await tester.pumpAndSettle();

      expect(find.byType(AuditNumericKeyboard), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop physical input rejects invalid numeric text', (
    tester,
  ) async {
    final controller = TextEditingController();

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuditNumericKeyboardScope(
            inputMode: AuditNumericInputMode.systemKeyboard,
            child: AuditNumericField(
              controller: controller,
              allowDecimal: true,
              maxDecimalPlaces: 1,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(AuditNumericField), '12.3');
    await tester.pump();
    expect(controller.text, '12.3');

    await tester.enterText(find.byType(AuditNumericField), '12.34');
    await tester.pump();
    expect(controller.text, '12.3');

    await tester.enterText(find.byType(AuditNumericField), '12.4.5');
    await tester.pump();
    expect(controller.text, '12.3');

    await tester.enterText(find.byType(AuditNumericField), '12a');
    await tester.pump();
    expect(controller.text, '12.3');
  });
}
