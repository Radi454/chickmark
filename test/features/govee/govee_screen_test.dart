import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/govee/providers/govee_capture_provider.dart';
import 'package:hatchaudit/features/govee/screens/govee_screen.dart';
import 'package:hatchaudit/features/govee/widgets/govee_review_sheet.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:provider/provider.dart';

Widget buildGoveeTestApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => GoveeCaptureProvider()),
      ChangeNotifierProvider(create: (_) => CustomersProvider()),
    ],
    child: const MaterialApp(home: GoveeScreen()),
  );
}

Widget buildReviewTestApp() {
  return MaterialApp(
    home: Scaffold(
      body: GoveeReviewSheet(
        initialLabels: const ['Spot 1', 'Spot 2', 'Spot 3'],
        onSave: (_) async {},
      ),
    ),
  );
}

void main() {
  testWidgets('Govee screen shows capture controls instead of saved history', (
    tester,
  ) async {
    await tester.pumpWidget(buildGoveeTestApp());

    expect(find.text('Govee'), findsOneWidget);
    expect(find.text('Start Spot 1'), findsOneWidget);
    expect(find.text('No measures yet'), findsNothing);
  });

  testWidgets('review allows editing spot labels only', (tester) async {
    await tester.pumpWidget(buildReviewTestApp());

    expect(find.text('Spot 1'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('govee-spot-label-1')),
      'Door',
    );
    await tester.pump();

    expect(find.text('Door'), findsOneWidget);
    expect(find.text('Customer'), findsNothing);
    expect(find.text('Hatchery'), findsNothing);
  });
}
