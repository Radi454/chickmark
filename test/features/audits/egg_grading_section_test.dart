import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/egg_storage_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          if (call.method == 'check') return ['wifi'];
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  Future<AuditProvider> pumpEggGrading(WidgetTester tester) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(
            create: (_) =>
                AuthProvider(supabaseService: _MockSupabaseService()),
          ),
          ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: EggStorageScreen(
            context: AuditContextData(
              auditType: 'Egg',
              customerId: 'customer-1',
              flockId: 'flock-1',
              breed: 'Ross 308',
              flockAgeWeeks: 42,
              date: '2026-08-23',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return provider;
  }

  Future<void> expandEggGrading(WidgetTester tester) async {
    final heading = find.text('Egg grading / visual quality');
    await tester.ensureVisible(heading);
    await tester.tap(heading);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpEggGradingWithTwoHouses(WidgetTester tester) async {
    final provider = await pumpEggGrading(tester);
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': '1', 'houseLabel': 'House 1'});
    provider.updateField('esGradingSampleSize', 100);
    provider.updateGradingCounts({'dirty': 4});
    provider.addEggQualityScopeSample(StationSampleModel.sampleKindHouse);
    provider.updateSampleMetadata({'houseNo': '2', 'houseLabel': 'House 2'});
    await tester.pump(const Duration(milliseconds: 300));
    provider.switchSample(0);
    await tester.pump(const Duration(milliseconds: 300));
    await expandEggGrading(tester);
  }

  testWidgets('entering counts updates the summary strip', (tester) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);

    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '100',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-rejected')), '12');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '4',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Acceptable 88 (88.0%)'), findsOneWidget);
    expect(find.text('Rejected 12 (12.0%)'), findsOneWidget);
    expect(find.textContaining('Dirty'), findsWidgets);
  });

  testWidgets('a defect count above the sample size shows an error', (
    tester,
  ) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);
    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '50',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '80',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('cannot exceed eggs inspected'), findsOneWidget);
  });

  testWidgets('clearing inspected eggs validates retained counts', (
    tester,
  ) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);
    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '100',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('egg-grading-rejected')), '12');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '4',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Eggs rejected cannot exceed eggs inspected.'),
      findsOneWidget,
    );
    expect(
      find.text('Dirty count cannot exceed eggs inspected.'),
      findsOneWidget,
    );
  });

  testWidgets('a defect sum above the sample size is accepted', (tester) async {
    await pumpEggGrading(tester);
    await expandEggGrading(tester);
    await tester.enterText(
      find.byKey(const Key('egg-grading-sample-size')),
      '100',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-dirty')),
      '60',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('egg-grading-count-cracked')),
      '55',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('cannot exceed'), findsNothing);
  });

  testWidgets('switching house samples swaps the counts', (tester) async {
    await pumpEggGradingWithTwoHouses(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('egg-grading-count-dirty')))
          .controller!
          .text,
      '4',
    );
    final secondHouseChip = find.widgetWithText(ChoiceChip, 'H2');
    await tester.ensureVisible(secondHouseChip);
    await tester.tap(secondHouseChip);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('egg-grading-count-dirty')))
          .controller!
          .text,
      '',
    );
  });
}
