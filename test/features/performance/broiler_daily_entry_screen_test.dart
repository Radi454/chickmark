import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/broiler_daily_record_models.dart';
import 'package:hatchaudit/features/performance/providers/broiler_daily_entry_provider.dart';
import 'package:hatchaudit/features/performance/screens/broiler_daily_entry_screen.dart';
import 'package:hatchaudit/features/performance/widgets/house_daily_entry_card.dart';

void main() {
  testWidgets('selectors are presented in customer farm flock date order', (
    tester,
  ) async {
    final provider = BroilerDailyEntryProvider();
    await tester.pumpWidget(
      MaterialApp(home: BroilerDailyEntryScreen(provider: provider)),
    );

    final customer = find.byKey(const ValueKey('daily-entry-customer'));
    final farm = find.byKey(const ValueKey('daily-entry-farm'));
    final flock = find.byKey(const ValueKey('daily-entry-flock'));
    final date = find.byKey(const ValueKey('daily-entry-date'));
    expect(customer, findsOneWidget);
    expect(farm, findsOneWidget);
    expect(flock, findsOneWidget);
    expect(date, findsOneWidget);
    expect(
      tester.getTopLeft(customer).dx,
      lessThan(tester.getTopLeft(farm).dx),
    );
    expect(tester.getTopLeft(farm).dx, lessThan(tester.getTopLeft(flock).dx));
    expect(tester.getTopLeft(flock).dx, lessThan(tester.getTopLeft(date).dx));
  });

  testWidgets('house cards use narrow and wide responsive containers', (
    tester,
  ) async {
    final provider = BroilerDailyEntryProvider.debugWithEntries(
      enteredBy: 'auditor-1',
      entries: [
        HouseDailyEntryState.debug(
          placementId: 'placement-1',
          houseId: 'house-1',
          houseName: 'House 1',
          flockId: 'flock-1',
          flockCode: 'BR-1',
          breed: 'Ross 308',
          entryDate: DateTime.utc(2026, 7, 1),
          placedBirds: 10000,
          recordDate: DateTime.utc(2026, 7, 24),
          previousMortality: 7,
          targetWeightG: 1258,
        ),
        HouseDailyEntryState.debug(
          placementId: 'placement-2',
          houseId: 'house-2',
          houseName: 'House 2',
          flockId: 'flock-1',
          flockCode: 'BR-1',
          breed: 'Ross 308',
          entryDate: DateTime.utc(2026, 7, 1),
          placedBirds: 9000,
          recordDate: DateTime.utc(2026, 7, 24),
        ),
      ],
    );

    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: BroilerDailyEntryScreen(provider: provider)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('daily-entry-narrow-list')),
      findsOneWidget,
    );
    expect(find.byType(HouseDailyEntryCard), findsNWidgets(2));
    expect(find.text('Age 23 days'), findsNWidgets(2));
    expect(find.text('Target 1,258 g'), findsOneWidget);
    expect(find.text('Previous mortality 7'), findsOneWidget);

    tester.view.physicalSize = const Size(1300, 900);
    await tester.pump();
    expect(find.byKey(const ValueKey('daily-entry-wide-grid')), findsOneWidget);
  });

  testWidgets('corrected status reveals a required correction reason', (
    tester,
  ) async {
    final entry = HouseDailyEntryState.debug(
      placementId: 'placement-1',
      houseId: 'house-1',
      houseName: 'House 1',
      flockId: 'flock-1',
      flockCode: 'BR-1',
      breed: 'Cobb500',
      entryDate: DateTime.utc(2026, 7, 1),
      placedBirds: 10000,
      recordDate: DateTime.utc(2026, 7, 24),
    );
    final provider = BroilerDailyEntryProvider.debugWithEntries(
      enteredBy: 'auditor-1',
      entries: [entry],
    );
    provider.updateDraft(
      entry.placement.id,
      entry.draft.copyWith(verificationStatus: VerificationStatus.corrected),
    );

    await tester.pumpWidget(
      MaterialApp(home: BroilerDailyEntryScreen(provider: provider)),
    );
    await tester.pump();

    expect(find.text('Correction reason'), findsOneWidget);
  });
}
