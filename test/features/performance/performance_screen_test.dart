import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/broiler_daily_record_models.dart';
import 'package:hatchaudit/features/performance/models/broiler_performance_models.dart';
import 'package:hatchaudit/features/performance/providers/performance_provider.dart';
import 'package:hatchaudit/features/performance/screens/performance_screen.dart';

void main() {
  testWidgets('renders the four monitoring sections and data context', (
    tester,
  ) async {
    var quickEntryOpened = false;
    final provider = PerformanceProvider.debug(
      snapshot: PerformanceWorkspaceSnapshot(
        metrics: const {
          'weight_deviation_pct': PerformanceMetric(
            key: 'weight_deviation_pct',
            value: -5.9,
            unit: '%',
            targetValue: 1350,
            quality: PerformanceDataQuality.complete,
          ),
          'daily_mortality_pct': PerformanceMetric(
            key: 'daily_mortality_pct',
            unit: '%',
            quality: PerformanceDataQuality.unavailable,
            missingReason: 'No current mortality record',
          ),
        },
        trendPoints: [
          PerformanceTrendPoint(
            date: DateTime.utc(2026, 7, 23),
            values: const {'weight_g': 1230},
          ),
          PerformanceTrendPoint(
            date: DateTime.utc(2026, 7, 24),
            values: const {'weight_g': 1270},
          ),
        ],
        concerns: const [],
        visits: const [],
        actions: const [],
        rangeStart: DateTime.utc(2026, 7, 10),
        rangeEnd: DateTime.utc(2026, 7, 24),
        verificationStatus: VerificationStatus.verified,
        reportedData: true,
        targetSourceLabel: 'Ross 308 AP 2022',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PerformanceScreen(
          provider: provider,
          onOpenQuickEntry: () => quickEntryOpened = true,
        ),
      ),
    );

    expect(find.text('Current status'), findsOneWidget);
    expect(find.text('Trends'), findsOneWidget);
    expect(find.text('Reported'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.textContaining('Ross 308 AP 2022'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.textContaining('10-07-2026'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Active concerns'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Active concerns'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Audits and corrective actions'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Audits and corrective actions'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('performance-quick-entry')));
    expect(quickEntryOpened, isTrue);
  });
}
