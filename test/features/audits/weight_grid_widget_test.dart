import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/widgets/weight_grid_widget.dart';

void main() {
  testWidgets('submitting the last weight field does not assume 100 fields', (
    tester,
  ) async {
    final controllers = List.generate(3, (_) => TextEditingController());
    final focusNodes = List.generate(3, (_) => FocusNode());

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

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(tester.takeException(), isNull);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });

  testWidgets('egg mode removes the keyboard hide action', (tester) async {
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

    expect(find.byIcon(Icons.keyboard_hide), findsNothing);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });

  testWidgets('egg mode lays out 25 numbered cells per row', (tester) async {
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
    expect(delegate.crossAxisCount, 25);

    final firstField = tester.widget<TextField>(find.byType(TextField).first);
    final lastField = tester.widget<TextField>(find.byType(TextField).last);
    expect(firstField.decoration?.hintText, '1');
    expect(lastField.decoration?.hintText, '100');
    expect(firstField.decoration?.suffixText, isNull);

    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focusNode in focusNodes) {
      focusNode.dispose();
    }
  });
}
