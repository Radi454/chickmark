import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/alarm_triage_feed.dart';

TriageItem _item(ScopeSeverity sev, String metric) => TriageItem(
      severity: sev,
      primaryTag: 'Hatch Result',
      secondaryTag: 'Pooled',
      metric: metric,
      value: '1.0%',
      context: 'Limit ≤ 8.0%',
      advice: sev == ScopeSeverity.good ? null : 'do something',
    );

Future<void> _pump(WidgetTester tester, List<TriageItem> items) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: AlarmTriageFeed(items: items)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('splits into Critical / Watch; green stays collapsed until tapped',
      (tester) async {
    await _pump(tester, [
      _item(ScopeSeverity.err, 'Hatchability'),
      _item(ScopeSeverity.warn, 'EST CV%'),
      _item(ScopeSeverity.good, 'Fertility'),
    ]);

    expect(find.text('CRITICAL — ACTION REQUIRED'), findsOneWidget);
    expect(find.text('WATCH — NEAR THRESHOLD'), findsOneWidget);
    expect(find.text('Hatchability'), findsOneWidget);
    expect(find.text('EST CV%'), findsOneWidget);

    // Good item hidden behind the collapsed "In Target" toggle.
    expect(find.text('Fertility'), findsNothing);
    expect(find.text('1 in target'), findsOneWidget);

    await tester.tap(find.text('1 in target'));
    await tester.pumpAndSettle();
    expect(find.text('Fertility'), findsOneWidget);
  });

  testWidgets('all-good shows the all-clear card + collapsible count',
      (tester) async {
    await _pump(tester, [
      _item(ScopeSeverity.good, 'Hatchability'),
      _item(ScopeSeverity.good, 'Fertility'),
    ]);

    expect(find.textContaining('within target'), findsOneWidget);
    expect(find.text('CRITICAL — ACTION REQUIRED'), findsNothing);
    expect(find.text('WATCH — NEAR THRESHOLD'), findsNothing);
    expect(find.text('2 in target'), findsOneWidget);
  });

  testWidgets('nothing to report → renders nothing', (tester) async {
    await _pump(tester, const []);

    expect(find.text('CRITICAL — ACTION REQUIRED'), findsNothing);
    expect(find.textContaining('in target'), findsNothing);
    expect(find.textContaining('within target'), findsNothing);
  });
}
