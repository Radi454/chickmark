import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/widgets/weight_grid_widget.dart';

void main() {
  testWidgets('closing the last weight field does not assume 100 fields', (
    tester,
  ) async {
    final controllers = List.generate(3, (_) => TextEditingController());
    final focusNodes = List.generate(3, (_) => FocusNode());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: WeightGridWidget(
              controllers: controllers,
              focusNodes: focusNodes,
              enabled: true,
              mode: WeightsMode.egg,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_return));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });

  testWidgets('custom keypad next action moves to the next egg field', (
    tester,
  ) async {
    final controllers = List.generate(3, (_) => TextEditingController());
    final focusNodes = List.generate(3, (_) => FocusNode());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: WeightGridWidget(
              controllers: controllers,
              focusNodes: focusNodes,
              enabled: true,
              mode: WeightsMode.egg,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(focusNodes[1].hasFocus, isTrue);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });

  testWidgets('egg mode includes the keyboard hide action', (tester) async {
    final controllers = List.generate(100, (_) => TextEditingController());
    final focusNodes = List.generate(100, (_) => FocusNode());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeightGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            enabled: true,
            mode: WeightsMode.egg,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_hide), findsOneWidget);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });

  testWidgets('egg mode lower-right action moves down the same column', (
    tester,
  ) async {
    final controllers = List.generate(100, (_) => TextEditingController());
    final focusNodes = List.generate(100, (_) => FocusNode());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeightGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            enabled: true,
            mode: WeightsMode.egg,
          ),
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    final targetIndex = 1 + delegate.crossAxisCount;

    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_return));
    await tester.pumpAndSettle();

    expect(focusNodes[targetIndex].hasFocus, isTrue);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });

  testWidgets('egg mode lays out compact responsive numbered cells', (
    tester,
  ) async {
    final controllers = List.generate(100, (_) => TextEditingController());
    final focusNodes = List.generate(100, (_) => FocusNode());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: WeightGridWidget(
              controllers: controllers,
              focusNodes: focusNodes,
              enabled: true,
              mode: WeightsMode.egg,
            ),
          ),
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
    expect(delegate.childAspectRatio, greaterThan(1.7));
    expect(find.byType(SingleChildScrollView), findsNothing);

    final visibleFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .take(4)
        .toList();
    expect(visibleFields.map((field) => field.decoration?.hintText), [
      '1',
      '2',
      '3',
      '4',
    ]);
    expect(visibleFields.first.decoration?.suffixText, isNull);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });

  testWidgets('egg mode adds columns on wide sheets', (tester) async {
    final controllers = List.generate(100, (_) => TextEditingController());
    final focusNodes = List.generate(100, (_) => FocusNode());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: WeightGridWidget(
              controllers: controllers,
              focusNodes: focusNodes,
              enabled: true,
              mode: WeightsMode.egg,
            ),
          ),
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 6);
    expect(delegate.childAspectRatio, greaterThan(2));

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });

  testWidgets('egg mode uses only rounded input field chrome', (tester) async {
    final controllers = List.generate(100, (_) => TextEditingController());
    final focusNodes = List.generate(100, (_) => FocusNode());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeightGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            enabled: true,
            mode: WeightsMode.egg,
          ),
        ),
      ),
    );

    final firstField = tester.widget<TextField>(find.byType(TextField).first);
    final inputBorder = firstField.decoration?.border as OutlineInputBorder?;
    final enabledBorder =
        firstField.decoration?.enabledBorder as OutlineInputBorder?;

    expect(firstField.decoration?.filled, isTrue);
    expect(firstField.decoration?.fillColor, Colors.white);
    expect(firstField.decoration?.contentPadding, EdgeInsets.zero);
    expect(inputBorder?.borderRadius.topLeft.x, 14);
    expect(enabledBorder?.borderSide.color, const Color(0xFFE2E8F0));
    expect(enabledBorder?.borderSide.width, 1.2);
    expect(firstField.style?.fontSize, 18);
    expect(firstField.style?.fontWeight, FontWeight.w700);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });
}
