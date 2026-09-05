import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/widgets/searchable_dropdown_field.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  const options = [
    SearchableDropdownOption<String>(value: null, label: 'All customers'),
    SearchableDropdownOption<String>(value: 'c1', label: 'Dr Osama Elsayed'),
    SearchableDropdownOption<String>(value: 'c2', label: 'Nile Valley Farms'),
  ];

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('focusing clears the selected label so typing starts empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SearchableDropdownField<String>(
          label: 'Customer',
          value: null,
          options: options,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'All customers');

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(fieldText(tester), isEmpty);
  });

  testWidgets('typing filters the options by substring', (tester) async {
    await tester.pumpWidget(
      wrap(
        SearchableDropdownField<String>(
          label: 'Customer',
          value: null,
          options: options,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'osama');
    await tester.pumpAndSettle();

    expect(find.text('Dr Osama Elsayed'), findsWidgets);
    expect(find.text('Nile Valley Farms'), findsNothing);
  });

  testWidgets('losing focus without a selection restores the label', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SearchableDropdownField<String>(
          label: 'Customer',
          value: 'c2',
          options: options,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Nile Valley Farms');

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    tester.testTextInput.hide();
    final focus = FocusScope.of(tester.element(find.byType(TextField)));
    focus.unfocus();
    await tester.pumpAndSettle();

    expect(fieldText(tester), 'Nile Valley Farms');
  });
}
