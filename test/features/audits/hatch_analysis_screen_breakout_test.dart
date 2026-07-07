import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatch_analysis_screen.dart';
import 'package:hatchaudit/features/audits/widgets/photo_button.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class MockBenchmarkLookup extends Mock implements BenchmarkLookup {}

MockBenchmarkLookup mockBenchmarkLookup() {
  final lookup = MockBenchmarkLookup();
  when(
    () => lookup.nearestBreedBenchmark(
      calculatedBmkAgeDays: any(named: 'calculatedBmkAgeDays'),
      breed: any(named: 'breed'),
    ),
  ).thenAnswer(
    (_) async => {
      'ageWeek': 38,
      'breed': 'Ross 308',
      'hatchabilityPct': 90.0,
      'fertilityPct': 88.0,
      'hofPct': 96.0,
    },
  );
  when(
    () => lookup.nearestBreakoutBenchmark(
      calculatedBmkAgeDays: any(named: 'calculatedBmkAgeDays'),
    ),
  ).thenAnswer(
    (_) async => {
      'ageWeek': 41,
      'infertilePct': 3.0,
      'early24hPct': 2.0,
      'early48hPct': 1.5,
      'bloodRingPct': 2.5,
      'blackEyePct': 0.5,
      'earlyDeadPct': 3.5,
      'midDeadPct': 1.3,
      'lateDeadPct': 1.8,
      'externalPipPct': 0.7,
      'crackedPct': 0.4,
      'contamPct': 0.2,
    },
  );
  return lookup;
}

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

  AuditContextData contextData({
    String flockId = 'flock-1',
    String? breed = 'Ross 308',
    int? flockAgeWeeks = 42,
    DateTime? flockEntryDate,
    String date = '2026-04-27',
  }) => AuditContextData(
    auditType: 'Hatch Analysis & Egg Breakouts',
    customerId: 'customer-1',
    flockId: flockId,
    breed: breed,
    flockEntryDate: flockEntryDate,
    flockAgeWeeks: flockAgeWeeks,
    date: date,
  );

  Future<AuditProvider> pumpScreen(
    WidgetTester tester, {
    required EggBreakoutType breakoutType,
    int? storageDays = 5,
    int? candlingDay,
    AuditContextData? contextOverride,
    BenchmarkLookup? benchmarkLookup,
  }) async {
    final provider = AuditProvider(autosaveEnabled: false);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: HatchAnalysisScreen(
            context: contextOverride ?? contextData(),
            benchmarkLookup: benchmarkLookup ?? mockBenchmarkLookup(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    provider.updateHatchField(0, 'ebBreakoutType', breakoutType.storageValue);
    if (storageDays != null) {
      provider.updateHatchField(0, 'haStorageDays', storageDays);
      provider.updateHatchField(0, 'ebStorageDays', storageDays);
    }
    provider.updateHatchField(0, 'haTotalEggsSet', 100);
    if (candlingDay != null) {
      provider.updateHatchField(0, 'ebBreakoutAgeDays', candlingDay);
    }
    await tester.pumpAndSettle();
    return provider;
  }

  Future<void> addVisibleSample(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('breakout-add-sample')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('breakout-add-sample')));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisibleKey(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterVisibleNumber(
    WidgetTester tester,
    Key key,
    String value,
  ) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    var textField = find.descendant(
      of: finder,
      matching: find.byType(TextField),
    );
    if (textField.evaluate().isEmpty) {
      textField = find.descendant(
        of: finder,
        matching: find.byType(EditableText),
      );
    }
    await tester.enterText(textField, value);
    await tester.pumpAndSettle();
  }

  Finder numericEditableFinder(Key key) {
    return find.descendant(
      of: find.byKey(key),
      matching: find.byType(EditableText),
    );
  }

  bool numericFieldHasFocus(WidgetTester tester, Key key) {
    final editable = tester.widget<EditableText>(numericEditableFinder(key));
    return editable.focusNode.hasFocus;
  }

  String editableNumberText(WidgetTester tester, Key key) {
    final editable = tester.widget<EditableText>(numericEditableFinder(key));
    return editable.controller.text;
  }

  String numericFieldText(WidgetTester tester, Key key) {
    final textField = find.descendant(
      of: find.byKey(key),
      matching: find.byType(TextField),
    );
    return tester.widget<TextField>(textField).controller?.text ?? '';
  }

  double mainScrollOffset(WidgetTester tester) {
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.controller, isNotNull);
    return listView.controller!.offset;
  }

  Future<void> pinFinderNearViewportBottom(
    WidgetTester tester,
    Finder finder,
  ) async {
    await Scrollable.ensureVisible(
      tester.element(finder),
      duration: Duration.zero,
      alignment: 0.95,
    );
    await tester.pumpAndSettle();
  }

  RenderBox smallestDecoratedAncestorBox(WidgetTester tester, Finder finder) {
    final boxes =
        find
            .ancestor(
              of: finder,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container && widget.decoration is BoxDecoration,
              ),
            )
            .evaluate()
            .map((element) => element.renderObject)
            .whereType<RenderBox>()
            .where((box) => box.hasSize)
            .toList()
          ..sort((a, b) {
            final aArea = a.size.width * a.size.height;
            final bArea = b.size.width * b.size.height;
            return aArea.compareTo(bArea);
          });

    return boxes.first;
  }

  BoxDecoration containerDecoration(WidgetTester tester, Key key) {
    final container = tester.widget<Container>(find.byKey(key));
    return container.decoration! as BoxDecoration;
  }

  EggBreakoutSampleEntry activeBreakoutSample(AuditProvider provider) {
    return EggBreakoutSampleEntry.decodeList(
      provider.drafts.single.ebTrayBreakoutJson,
      fallbackBreakoutType: EggBreakoutType.residueHatchDay,
    ).single;
  }

  Future<void> tapVisibleText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('fresh egg breakout hides hatchability and shows fresh items', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.freshEggBreakout);
    await addVisibleSample(tester);

    expect(find.text('Hatchability Results'), findsNothing);
    expect(find.text('Healthy Hatched'), findsNothing);
    expect(find.text('Culled'), findsNothing);
    expect(find.text('Dead at Hatch'), findsNothing);
    expect(find.text('Candling Day'), findsNothing);
    expect(find.text('BMK Age 289 days'), findsNothing);

    expect(find.text('Infertile'), findsOneWidget);
    expect(find.text('24 hours'), findsOneWidget);
    expect(find.text('48 hours'), findsOneWidget);
    expect(find.text('Blood Ring'), findsOneWidget);
    expect(find.text('Position'), findsNothing);
    expect(find.text('Black eye'), findsNothing);
    expect(find.text('Mid dead'), findsNothing);
    expect(
      find.byType(MultiPhotoButton),
      findsNWidgets(freshCountFields.length),
    );
  });

  testWidgets('fresh egg tray samples default tray size to thirty', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
    );

    await addVisibleSample(tester);

    expect(
      EggBreakoutSampleEntry.decodeList(
        provider.drafts.single.ebTrayBreakoutJson,
      ).single.traySize,
      30,
    );
  });

  testWidgets('candled egg breakout shows candling day and candled items', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.candledEggBreakout);
    await addVisibleSample(tester);

    expect(find.text('Hatchability Results'), findsNothing);
    expect(find.text('Candling Day'), findsNothing);
    expect(find.text('BMK Age 279 days'), findsNothing);

    expect(find.text('Infertile'), findsOneWidget);
    expect(find.text('24 hours'), findsOneWidget);
    expect(find.text('48 hours'), findsOneWidget);
    expect(find.text('Blood Ring'), findsOneWidget);
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Black Eye'), findsOneWidget);
    expect(find.text('Mid dead'), findsNothing);
    expect(
      find.byType(MultiPhotoButton),
      findsNWidgets(candledCountFields.length),
    );
  });

  testWidgets('residue hatch day shows hatchability and breakout samples', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.residueHatchDay);
    await addVisibleSample(tester);

    expect(find.text('Hatch Results'), findsOneWidget);
    final resultsCard = find.byKey(
      const ValueKey('residue-batch-results-card'),
    );
    expect(
      find.descendant(
        of: resultsCard,
        matching: find.byIcon(Icons.analytics_outlined),
      ),
      findsNothing,
    );
    expect(find.text('Batch Results'), findsNothing);
    expect(find.text('Hatched chicks'), findsOneWidget);
    expect(find.text('Hatchability'), findsOneWidget);
    expect(find.text('Fertility'), findsOneWidget);
    expect(find.text('HOF'), findsOneWidget);
    expect(find.text('Breakout Samples'), findsOneWidget);
    expect(find.byKey(const ValueKey('breakout-add-sample')), findsOneWidget);
    expect(
      find.byType(MultiPhotoButton),
      findsNWidgets(residueCountFields.length),
    );
    expect(find.text('Delta --'), findsNothing);
    expect(find.text('Gap --'), findsWidgets);
    expect(find.text('BMK Age 268 days'), findsNothing);
    expect(find.text('Infertile'), findsOneWidget);
    expect(find.text('Early Dead'), findsOneWidget);
    expect(find.text('Mid Dead'), findsOneWidget);
    expect(find.text('Late Dead'), findsOneWidget);
    expect(find.text('External Pip'), findsOneWidget);
    expect(find.text('Cracked'), findsOneWidget);
    expect(find.text('Contaminated'), findsOneWidget);
    expect(find.text('Internal pip'), findsNothing);
    expect(find.text('Malposition'), findsNothing);
    expect(find.text('Exposed brain'), findsNothing);
    expect(find.text('Crossed beak'), findsNothing);
    expect(find.text('Culled %'), findsOneWidget);
    expect(find.text('Dead %'), findsOneWidget);
  });

  testWidgets('breakout items keep metric photos beside their rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
    );
    await addVisibleSample(tester);

    var sample = activeBreakoutSample(provider);
    sample = sample.copyWith(
      photos: const {'midDead:photo-1': '/tmp/chickmark-mid-dead-breakout.jpg'},
    );
    provider.updateHatchField(
      0,
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList([sample]),
    );
    await tester.pumpAndSettle();

    final buttons = tester
        .widgetList<MultiPhotoButton>(find.byType(MultiPhotoButton))
        .toList();
    expect(buttons, hasLength(residueCountFields.length));
    expect(
      buttons.map((button) => button.fieldKey),
      containsAll(<String>[
        'breakout_infertile_photo',
        'breakout_earlyDead_photo',
        'breakout_midDead_photo',
        'breakout_lateDead_photo',
        'breakout_externalPip_photo',
        'breakout_cracked_photo',
        'breakout_contaminated_photo',
      ]),
    );
    expect(
      buttons
          .singleWhere((button) => button.fieldKey == 'breakout_midDead_photo')
          .panelRowId,
      endsWith(':residue_breakout:${sample.id}:midDead'),
    );

    buttons
        .singleWhere((button) => button.fieldKey == 'breakout_earlyDead_photo')
        .onPhotoCaptured(0, '/tmp/chickmark-early-dead-breakout.jpg');
    await tester.pumpAndSettle();
    expect(
      activeBreakoutSample(provider).photos.entries,
      contains(
        isA<MapEntry<String, String>>()
            .having((entry) => entry.key, 'key', startsWith('earlyDead:photo_'))
            .having(
              (entry) => entry.value,
              'value',
              '/tmp/chickmark-early-dead-breakout.jpg',
            ),
      ),
    );

    final midDeadRow = find.byKey(const ValueKey('breakout-row-midDead'));
    final midDeadPhotos = find.byKey(
      ValueKey('breakout-photo-${sample.id}-midDead'),
    );
    expect(midDeadPhotos, findsOneWidget);
    expect(
      find.descendant(
        of: midDeadPhotos,
        matching: find.byKey(const ValueKey('multi-photo-thumbnail-0')),
      ),
      findsOneWidget,
    );
    expect(
      (tester.getCenter(midDeadRow).dy - tester.getCenter(midDeadPhotos).dy)
          .abs(),
      lessThan(1),
    );
  });

  testWidgets('residue performance metrics render as one summary card', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.residueHatchDay);

    final performanceCard = find.byKey(
      const ValueKey('hatch-performance-summary-card'),
    );
    expect(performanceCard, findsOneWidget);

    final metricLabels = [
      'Hatchability',
      'Fertility',
      'HOF',
      'Culled %',
      'Dead %',
    ];
    double previousTop = -1;
    for (final label in metricLabels) {
      final labelFinder = find.descendant(
        of: performanceCard,
        matching: find.text(label),
      );
      expect(labelFinder, findsOneWidget);
      final top = tester.getTopLeft(labelFinder).dy;
      expect(top, greaterThan(previousTop));
      previousTop = top;
    }

    for (final text in [
      'BMK 90.0%',
      'BMK 88.0%',
      'BMK 96.0%',
      'Limit 1.0%',
      'Limit 0.2%',
    ]) {
      expect(
        find.descendant(of: performanceCard, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: performanceCard, matching: find.text('Gap --')),
      findsNWidgets(5),
    );
  });

  testWidgets('residue batches use automatic setter hatcher tabs and metrics', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    provider.updateHatchField(0, 'setterId', '1');
    provider.updateHatchField(0, 'hatcherId', '1');
    provider.updateHatchField(0, 'haTotalEggsSet', 19200);
    provider.updateHatchField(0, 'haHatched', 16500);
    provider.updateHatchField(0, 'haCulled', 120);
    provider.updateHatchField(0, 'haDead', 30);
    provider.updateHatchField(
      0,
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList([
        EggBreakoutSampleEntry.tray(
          id: 'tray-1',
          label: 'Tray 1',
          traySize: 150,
          breakoutType: EggBreakoutType.residueHatchDay,
          counts: const {'infertile': 15},
        ),
        EggBreakoutSampleEntry.tray(
          id: 'tray-2',
          label: 'Tray 2',
          traySize: 150,
          breakoutType: EggBreakoutType.residueHatchDay,
          counts: const {'infertile': 30},
        ),
      ]),
    );
    provider.addHatch();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('residue-batch-tabs')), findsOneWidget);
    expect(find.text('S1H1'), findsOneWidget);
    expect(find.text('S2H2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('residue-batch-results-card')),
      findsOneWidget,
    );
    expect(find.text('Hatch totals'), findsOneWidget);
    final entryBottom = tester
        .getBottomLeft(
          find.byKey(const ValueKey('hatch-analysis-required-entry-card')),
        )
        .dy;
    final tabsTop = tester
        .getTopLeft(find.byKey(const ValueKey('residue-batch-tabs')))
        .dy;
    final resultsTop = tester
        .getTopLeft(find.byKey(const ValueKey('residue-batch-results-card')))
        .dy;
    expect(tabsTop, greaterThan(entryBottom));
    expect(resultsTop, greaterThan(tabsTop));

    await tapVisibleKey(tester, const ValueKey('residue-batch-tab-0'));

    expect(find.text('Hatch S1H1'), findsOneWidget);
    expect(find.text('Batch S1H1'), findsNothing);
    expect(find.text('Batch totals'), findsNothing);
    expect(find.text('85.9%'), findsOneWidget);
    expect(find.text('85.0%'), findsOneWidget);
    expect(find.text('101.1%'), findsOneWidget);
    expect(find.text('0.6%'), findsOneWidget);
    expect(find.text('0.2%'), findsWidgets);

    await tapVisibleKey(tester, const ValueKey('residue-batch-tab-1'));
    provider.updateHatchField(1, 'setterId', '4');
    provider.updateHatchField(1, 'hatcherId', '7');
    await tester.pumpAndSettle();

    expect(provider.activeDraft.setterId, '4');
    expect(provider.activeDraft.hatcherId, '7');
    expect(find.text('S4H7'), findsOneWidget);
  });

  testWidgets('residue hierarchy controls start pooled until activated', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('residue-batch-tabs')),
    );
    await tester.pumpAndSettle();

    expect(provider.isCompareMode, isFalse);
    expect(find.text('House scope'), findsOneWidget);
    expect(find.text('Machine scope'), findsOneWidget);
    expect(find.text('Trolley scope'), findsOneWidget);
    expect(find.byKey(const ValueKey('residue-trolley-tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('residue-add-trolley')), findsOneWidget);
    expect(find.text('Pool'), findsAtLeastNWidgets(3));
    expect(find.byKey(const ValueKey('residue-house-number-0')), findsNothing);
    expect(find.byKey(const ValueKey('residue-setter-number-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('residue-hatcher-number-0')),
      findsNothing,
    );

    await tapVisibleKey(tester, const ValueKey('residue-add-trolley'));

    expect(provider.isCompareMode, isFalse);
    expect(provider.hatchCount, 1);
    expect(
      find.byKey(const ValueKey('residue-trolley-number-0')),
      findsOneWidget,
    );
    expect(
      editableNumberText(tester, const ValueKey('residue-trolley-number-0')),
      isEmpty,
    );
    final pooledTrolleySamples = EggBreakoutSampleEntry.decodeList(
      provider.activeDraft.ebTrayBreakoutJson,
      fallbackBreakoutType: EggBreakoutType.residueHatchDay,
    );
    expect(pooledTrolleySamples, hasLength(1));
    expect(pooledTrolleySamples.single.trolley, 'T');
    expect(pooledTrolleySamples.single.house, isNull);
    expect(pooledTrolleySamples.single.setter, isNull);
    expect(pooledTrolleySamples.single.hatcher, isNull);

    await tapVisibleKey(tester, const ValueKey('residue-add-house'));

    expect(provider.isCompareMode, isTrue);
    expect(provider.hatchCount, 1);
    expect(provider.activeDraft.houseId, 'H');
    expect(find.text('H'), findsOneWidget);
    expect(find.text('Pool'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('residue-remove-house')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('residue-house-number-0')),
      findsOneWidget,
    );
    expect(
      editableNumberText(tester, const ValueKey('residue-house-number-0')),
      isEmpty,
    );
    expect(find.byKey(const ValueKey('residue-setter-number-0')), findsNothing);

    await tapVisibleKey(tester, const ValueKey('residue-remove-house'));

    expect(provider.isCompareMode, isFalse);
    expect(find.text('Pool'), findsAtLeastNWidgets(2));
    expect(find.byKey(const ValueKey('residue-house-number-0')), findsNothing);

    await tapVisibleKey(tester, const ValueKey('residue-add-house'));
    await tapVisibleKey(tester, const ValueKey('residue-add-batch'));

    expect(provider.hatchCount, 1);
    expect(provider.activeDraft.setterId, 'S');
    expect(provider.activeDraft.hatcherId, 'H');
    expect(find.text('SH'), findsOneWidget);
    expect(find.text('Trolley scope'), findsOneWidget);
    expect(find.byKey(const ValueKey('residue-trolley-tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('residue-remove-batch')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('residue-setter-number-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('residue-hatcher-number-0')),
      findsOneWidget,
    );
    expect(
      editableNumberText(tester, const ValueKey('residue-setter-number-0')),
      isEmpty,
    );
    expect(
      editableNumberText(tester, const ValueKey('residue-hatcher-number-0')),
      isEmpty,
    );

    await tapVisibleKey(tester, const ValueKey('residue-add-batch'));

    expect(provider.hatchCount, 2);
    expect(provider.activeDraft.setterId, '1');
    expect(provider.activeDraft.hatcherId, '1');
    expect(find.text('SH'), findsOneWidget);
    expect(find.text('S1H1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('residue-setter-number-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('residue-hatcher-number-1')),
      findsOneWidget,
    );
    expect(
      editableNumberText(tester, const ValueKey('residue-setter-number-1')),
      '1',
    );
    expect(
      editableNumberText(tester, const ValueKey('residue-hatcher-number-1')),
      '1',
    );

    await tapVisibleKey(tester, const ValueKey('residue-remove-batch'));

    expect(provider.hatchCount, 1);
    expect(provider.activeDraft.setterId, 'S');
    expect(provider.activeDraft.hatcherId, 'H');
    expect(find.text('H'), findsOneWidget);
    expect(find.text('SH'), findsOneWidget);
    expect(find.text('S1H1'), findsNothing);
    expect(
      find.byKey(const ValueKey('residue-setter-number-0')),
      findsOneWidget,
    );
  });

  testWidgets('adding house or machine scope keeps Tray and Trolley pooled', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );

      // Pooled baseline: Tray scope and Trolley scope both show Pool.
      expect(
        find.byKey(const ValueKey('breakout-pool-sample-tab')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('breakout-sample-tab-0')), findsNothing);
      expect(find.byKey(const ValueKey('residue-trolley-tab-0')), findsNothing);

      // Adding a machine scope must not flip Tray or Trolley out of Pool.
      await tapVisibleKey(tester, const ValueKey('residue-add-batch'));
      expect(
        find.byKey(const ValueKey('breakout-pool-sample-tab')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('breakout-sample-tab-0')), findsNothing);
      expect(find.byKey(const ValueKey('residue-trolley-tab-0')), findsNothing);

      // Adding a house scope must not flip Tray or Trolley out of Pool either.
      await tapVisibleKey(tester, const ValueKey('residue-add-house'));
      expect(
        find.byKey(const ValueKey('breakout-pool-sample-tab')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('breakout-sample-tab-0')), findsNothing);
      expect(find.byKey(const ValueKey('residue-trolley-tab-0')), findsNothing);

      expect(provider.isCompareMode, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('machine scope from pool does not create house scope', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    await tapVisibleKey(tester, const ValueKey('residue-add-batch'));

    expect(find.text('Pool'), findsAtLeastNWidgets(1));
    expect(find.text('H1'), findsNothing);
    expect(find.byKey(const ValueKey('residue-house-number-0')), findsNothing);
    expect(find.byKey(const ValueKey('residue-remove-house')), findsNothing);
    expect(provider.activeDraft.houseId, isNull);
    expect(provider.activeDraft.setterId, 'S');
    expect(provider.activeDraft.hatcherId, 'H');
  });

  testWidgets('trolley scope belongs to the active machine', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );

      await tapVisibleKey(tester, const ValueKey('residue-add-batch'));

      expect(find.text('Trolley scope'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('residue-trolley-tabs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('residue-trolley-number-0')),
        findsNothing,
      );

      await tapVisibleKey(tester, const ValueKey('residue-add-trolley'));

      expect(
        find.byKey(const ValueKey('residue-trolley-number-0')),
        findsOneWidget,
      );
      expect(
        editableNumberText(tester, const ValueKey('residue-trolley-number-0')),
        isEmpty,
      );
      var firstMachineSamples = EggBreakoutSampleEntry.decodeList(
        provider.drafts[0].ebTrayBreakoutJson,
        fallbackBreakoutType: EggBreakoutType.residueHatchDay,
      );
      // Adding a trolley keeps the breakout pooled (Tray scope stays Pool).
      expect(firstMachineSamples.single.sampleMode, EggBreakoutSampleMode.pool);
      expect(firstMachineSamples.single.trolley, 'T');
      expect(
        find.byKey(ValueKey('${firstMachineSamples.single.id}-trolley')),
        findsNothing,
      );

      await enterVisibleNumber(
        tester,
        const ValueKey('residue-trolley-number-0'),
        '7',
      );

      firstMachineSamples = EggBreakoutSampleEntry.decodeList(
        provider.drafts[0].ebTrayBreakoutJson,
        fallbackBreakoutType: EggBreakoutType.residueHatchDay,
      );
      expect(firstMachineSamples.map((sample) => sample.trolley), ['7']);
      expect(find.text('T7'), findsOneWidget);

      await tapVisibleKey(tester, const ValueKey('residue-add-batch'));

      expect(provider.activeHatchIndex, 1);
      expect(find.text('T7'), findsNothing);
      expect(
        find.byKey(const ValueKey('residue-trolley-number-1')),
        findsNothing,
      );

      await tapVisibleKey(tester, const ValueKey('residue-add-trolley'));
      await enterVisibleNumber(
        tester,
        const ValueKey('residue-trolley-number-1'),
        '2',
      );

      firstMachineSamples = EggBreakoutSampleEntry.decodeList(
        provider.drafts[0].ebTrayBreakoutJson,
        fallbackBreakoutType: EggBreakoutType.residueHatchDay,
      );
      final secondMachineSamples = EggBreakoutSampleEntry.decodeList(
        provider.drafts[1].ebTrayBreakoutJson,
        fallbackBreakoutType: EggBreakoutType.residueHatchDay,
      );
      expect(firstMachineSamples.map((sample) => sample.trolley), ['7']);
      expect(secondMachineSamples.map((sample) => sample.trolley), ['2']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'adding and selecting trolley and tray chips does not scroll to tray fields',
    (tester) async {
      tester.view.physicalSize = const Size(500, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final provider = await pumpScreen(
          tester,
          breakoutType: EggBreakoutType.residueHatchDay,
          benchmarkLookup: mockBenchmarkLookup(),
        );

        await tapVisibleKey(tester, const ValueKey('residue-add-batch'));
        await tapVisibleKey(tester, const ValueKey('residue-add-trolley'));
        await enterVisibleNumber(
          tester,
          const ValueKey('residue-trolley-number-0'),
          '7',
        );

        await pinFinderNearViewportBottom(
          tester,
          find.byKey(const ValueKey('residue-trolley-tabs')),
        );
        final beforeTrolleyAdd = mainScrollOffset(tester);

        await tester.tap(find.byKey(const ValueKey('residue-add-trolley')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          mainScrollOffset(tester),
          moreOrLessEquals(beforeTrolleyAdd, epsilon: 0.1),
        );
        expect(
          editableNumberText(
            tester,
            const ValueKey('residue-trolley-number-0'),
          ),
          '8',
        );

        final beforeTrolleyTap = mainScrollOffset(tester);

        await tester.tap(find.byKey(const ValueKey('residue-trolley-tab-0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          mainScrollOffset(tester),
          moreOrLessEquals(beforeTrolleyTap, epsilon: 0.1),
        );
        expect(
          find.byKey(const ValueKey('residue-trolley-number-0')),
          findsOneWidget,
        );
        expect(
          editableNumberText(
            tester,
            const ValueKey('residue-trolley-number-0'),
          ),
          '7',
        );

        await pinFinderNearViewportBottom(
          tester,
          find.byKey(const ValueKey('breakout-add-sample')),
        );
        final beforeTrayAdd = mainScrollOffset(tester);

        // The first Tray + converts the active pooled trolley into Tray 1; the
        // second adds Tray 2. Neither should scroll to the tray entry fields.
        await tester.tap(find.byKey(const ValueKey('breakout-add-sample')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('breakout-add-sample')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          mainScrollOffset(tester),
          moreOrLessEquals(beforeTrayAdd, epsilon: 0.1),
        );
        final samples = EggBreakoutSampleEntry.decodeList(
          provider.drafts.single.ebTrayBreakoutJson,
          fallbackBreakoutType: EggBreakoutType.residueHatchDay,
        );
        expect(samples, hasLength(2));
        expect(
          samples.every(
            (sample) => sample.sampleMode == EggBreakoutSampleMode.tray,
          ),
          isTrue,
        );
        final secondSampleCountKey = ValueKey(
          'breakout-count-${samples[1].id}-infertile',
        );

        // Select Tray 1 so Tray 2's fields are hidden, then select Tray 2.
        await tester.tap(find.byKey(const ValueKey('breakout-sample-tab-0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await pinFinderNearViewportBottom(
          tester,
          find.byKey(const ValueKey('breakout-sample-tab-0')),
        );
        final beforeTrayTap = mainScrollOffset(tester);
        expect(find.byKey(secondSampleCountKey), findsNothing);

        await tester.tap(find.byKey(const ValueKey('breakout-sample-tab-1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          mainScrollOffset(tester),
          moreOrLessEquals(beforeTrayTap, epsilon: 0.1),
        );
        expect(
          find.byKey(const ValueKey('breakout-sample-tab-1')),
          findsOneWidget,
        );
        expect(find.byKey(secondSampleCountKey), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('remove machine is hidden when pool house chip is selected', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );

      await enterVisibleNumber(
        tester,
        const ValueKey('residue-hatched-chicks-0'),
        '11111',
      );
      expect(provider.drafts[0].haHatched, 11111);

      await tapVisibleKey(tester, const ValueKey('residue-add-batch'));

      expect(provider.activeHatchIndex, 1);
      expect(
        find.byKey(const ValueKey('residue-remove-batch')),
        findsOneWidget,
      );

      await tapVisibleKey(tester, const ValueKey('residue-house-tab-0'));

      expect(provider.activeHatchIndex, 0);
      expect(find.byKey(const ValueKey('residue-remove-batch')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'tray scope from pooled context stays free of house and machine hierarchy',
    (tester) async {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );

      await addVisibleSample(tester);

      final savedSample = EggBreakoutSampleEntry.decodeList(
        provider.drafts.single.ebTrayBreakoutJson,
      ).single;
      expect(savedSample.house, isNull);
      expect(savedSample.setter, isNull);
      expect(savedSample.hatcher, isNull);
    },
  );

  testWidgets('residue hierarchy tabs share house machine context with trays', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );
      await addVisibleSample(tester);
      await tapVisibleKey(tester, const ValueKey('residue-add-house'));
      await tapVisibleKey(tester, const ValueKey('residue-add-batch'));

      final sample = activeBreakoutSample(provider);
      expect(find.text('House scope'), findsOneWidget);
      expect(find.text('Machine scope'), findsOneWidget);
      expect(find.text('Trolley scope'), findsOneWidget);
      expect(find.byKey(const ValueKey('residue-house-tabs')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('residue-machine-tabs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('residue-trolley-tabs')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('${sample.id}-house')), findsNothing);
      expect(find.byKey(ValueKey('${sample.id}-setter')), findsNothing);
      expect(find.byKey(ValueKey('${sample.id}-hatcher')), findsNothing);
      expect(find.byKey(ValueKey('${sample.id}-trolley')), findsNothing);
      expect(find.byKey(ValueKey('${sample.id}-tray')), findsOneWidget);
      expect(find.byKey(ValueKey('${sample.id}-position')), findsOneWidget);

      await enterVisibleNumber(
        tester,
        const ValueKey('residue-house-number-0'),
        '2',
      );
      await enterVisibleNumber(
        tester,
        const ValueKey('residue-setter-number-0'),
        '3',
      );
      await enterVisibleNumber(
        tester,
        const ValueKey('residue-hatcher-number-0'),
        '4',
      );

      final savedSample = EggBreakoutSampleEntry.decodeList(
        provider.drafts.single.ebTrayBreakoutJson,
      ).single;
      expect(provider.drafts.single.toMap()['houseId'], '2');
      expect(provider.drafts.single.setterId, '3');
      expect(provider.drafts.single.hatcherId, '4');
      expect(savedSample.house, '2');
      expect(savedSample.setter, '3');
      expect(savedSample.hatcher, '4');
      expect(find.text('H2'), findsOneWidget);
      expect(find.text('House 2'), findsNothing);
      expect(find.text('S3H4'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('hatch total fields stay isolated between hatch tabs', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );

      await enterVisibleNumber(
        tester,
        const ValueKey('residue-hatched-chicks-0'),
        '11111',
      );
      expect(provider.drafts[0].haHatched, 11111);

      await tapVisibleKey(tester, const ValueKey('residue-add-batch'));
      expect(provider.activeHatchIndex, 1);
      expect(provider.drafts[1].haHatched, isNull);
      expect(
        editableNumberText(tester, const ValueKey('residue-hatched-chicks-1')),
        isEmpty,
      );

      await enterVisibleNumber(
        tester,
        const ValueKey('residue-hatched-chicks-1'),
        '22222',
      );
      expect(provider.drafts[1].haHatched, 22222);

      await tapVisibleKey(tester, const ValueKey('residue-house-tab-0'));
      expect(
        editableNumberText(tester, const ValueKey('residue-hatched-chicks-0')),
        '11111',
      );
      expect(provider.drafts[0].haHatched, 11111);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('uses breakout type as the main card and removes old regions', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.residueHatchDay);

    expect(find.text('Hatch Analysis & Egg Breakouts'), findsOneWidget);
    expect(find.text('Breakout Type'), findsOneWidget);
    expect(find.text('HATCHING & BREAKOUT'), findsNothing);
    expect(find.text('Fresh Egg'), findsOneWidget);
    expect(find.text('Candled Egg'), findsOneWidget);
    expect(find.text('Residue / Hatch Day'), findsOneWidget);
    expect(find.text('Breakout Samples'), findsOneWidget);

    expect(find.text('Batch / hatch group'), findsNothing);
    expect(find.text('Batch / Hatch Group 1'), findsNothing);
    expect(find.text('Batch Info'), findsNothing);
    expect(find.text('Hatch Results'), findsOneWidget);
    expect(find.text('Batch Results'), findsNothing);
    expect(find.text('100% Budget Categories'), findsNothing);
  });

  testWidgets('uses compact professional workbench structure', (tester) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.residueHatchDay);

    final workbench = find.byKey(
      const ValueKey('hatch-analysis-workbench-shell'),
    );
    final header = find.byKey(const ValueKey('hatch-analysis-breakout-header'));
    final samplesPanel = find.byKey(
      const ValueKey('hatch-analysis-samples-panel'),
    );

    expect(workbench, findsOneWidget);
    expect(header, findsOneWidget);
    expect(samplesPanel, findsOneWidget);
    expect(tester.getSize(header).height, lessThan(260));
    expect(
      tester.getSize(samplesPanel).width,
      equals(tester.getSize(header).width),
    );
  });

  testWidgets('main card shows flock breed storage and calculated bmk age', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    expect(find.text('FLOCK'), findsOneWidget);
    expect(find.text('flock-1'), findsOneWidget);
    expect(find.text('BREED'), findsOneWidget);
    expect(find.text('Ross 308'), findsOneWidget);
    expect(find.text('STORAGE DAYS'), findsOneWidget);
    expect(find.text('BMK AGE'), findsOneWidget);
    expect(find.text('42 wks'), findsOneWidget);
    expect(find.text('CANDLED AGE'), findsNothing);

    final storageEntryCard = find.byKey(
      const ValueKey('breakout-storage-days-entry-card'),
    );
    final bmkDisplayCard = find.byKey(
      const ValueKey('breakout-bmk-age-display-card'),
    );
    expect(storageEntryCard, findsOneWidget);
    expect(bmkDisplayCard, findsOneWidget);
    expect(
      tester.getSize(storageEntryCard).width,
      greaterThan(tester.getSize(bmkDisplayCard).width),
    );
    expect(
      find.descendant(of: storageEntryCard, matching: find.text('BMK AGE')),
      findsNothing,
    );
    expect(
      find.descendant(of: bmkDisplayCard, matching: find.text('STORAGE DAYS')),
      findsNothing,
    );
  });

  testWidgets(
    'breakout metadata tiles stay one equal row with wrapped values',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const longFlockName = 'flock-demo-all-sections-ross308-long-name';
      await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        contextOverride: contextData(flockId: longFlockName, flockAgeWeeks: 38),
      );

      final breakoutTypeCard = find.byKey(
        const ValueKey('hatch-analysis-breakout-header'),
      );
      final contextCard = find.byKey(
        const ValueKey('hatch-analysis-context-card'),
      );
      final flockTile = smallestDecoratedAncestorBox(
        tester,
        find.text('FLOCK'),
      );
      final breedTile = smallestDecoratedAncestorBox(
        tester,
        find.text('BREED'),
      );
      final bmkTile = smallestDecoratedAncestorBox(
        tester,
        find.text('BMK AGE'),
      );

      expect(
        tester.getTopLeft(find.text('FLOCK')).dy,
        tester.getTopLeft(find.text('BREED')).dy,
      );
      expect(
        tester.getTopLeft(find.text('FLOCK')).dy,
        tester.getTopLeft(find.text('BMK AGE')).dy,
      );
      expect(
        tester.getSize(breakoutTypeCard).height,
        closeTo(tester.getSize(contextCard).height, 0.1),
      );
      expect(flockTile.size.width, closeTo(breedTile.size.width, 0.1));
      expect(flockTile.size.width, closeTo(bmkTile.size.width, 0.1));
      expect(flockTile.size.height, closeTo(breedTile.size.height, 0.1));
      expect(flockTile.size.height, closeTo(bmkTile.size.height, 0.1));

      final flockValueText = tester.widget<Text>(find.text(longFlockName));
      expect(flockValueText.maxLines, greaterThanOrEqualTo(2));
    },
  );

  testWidgets('storage days defaults to zero and calculates bmk age', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      storageDays: null,
      contextOverride: contextData(flockAgeWeeks: 40),
      benchmarkLookup: mockBenchmarkLookup(),
    );

    expect(provider.drafts.single.haStorageDays, 0);
    expect(provider.drafts.single.ebStorageDays, 0);
    expect(
      editableNumberText(tester, const ValueKey('breakout-storage-days')),
      '0',
    );

    final bmkDisplayCard = find.byKey(
      const ValueKey('breakout-bmk-age-display-card'),
    );
    expect(
      find.descendant(of: bmkDisplayCard, matching: find.text('37 wks')),
      findsOneWidget,
    );
  });

  testWidgets('storage days is a separate entry card that clears zero', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      storageDays: null,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    final contextCard = find.byKey(
      const ValueKey('hatch-analysis-context-card'),
    );
    final breakoutTypeCard = find.byKey(
      const ValueKey('hatch-analysis-breakout-header'),
    );
    final requiredCard = find.byKey(
      const ValueKey('hatch-analysis-required-entry-card'),
    );
    final storageEntryCard = find.byKey(
      const ValueKey('breakout-storage-days-entry-card'),
    );

    expect(requiredCard, findsOneWidget);
    expect(find.text('Entry Fields'), findsNothing);
    expect(
      find.descendant(of: contextCard, matching: storageEntryCard),
      findsNothing,
    );
    expect(
      find.descendant(of: requiredCard, matching: storageEntryCard),
      findsOneWidget,
    );
    expect(
      find.descendant(of: requiredCard, matching: find.text('REQUIRED')),
      findsNothing,
    );
    expect(
      tester.getSize(requiredCard).height,
      lessThan(tester.getSize(contextCard).height),
    );
    expect(
      tester.getSize(contextCard).height,
      closeTo(tester.getSize(breakoutTypeCard).height, 0.1),
    );
    final requiredDecoration = containerDecoration(
      tester,
      const ValueKey('hatch-analysis-required-entry-card'),
    );
    expect(requiredDecoration.gradient, isNull);
    expect(requiredDecoration.color, AppColors.surfaceRaised);

    final storageTileDecoration = containerDecoration(
      tester,
      const ValueKey('breakout-storage-days-entry-card'),
    );
    expect(storageTileDecoration.color, AppColors.surface);
    final storageLabel = tester.widget<Text>(
      find.descendant(
        of: storageEntryCard,
        matching: find.text('STORAGE DAYS'),
      ),
    );
    expect(storageLabel.style?.color, AppColors.textSecondary);

    await tester.tap(
      numericEditableFinder(const ValueKey('breakout-storage-days')),
    );
    await tester.pump();

    expect(
      editableNumberText(tester, const ValueKey('breakout-storage-days')),
      isEmpty,
    );
    expect(provider.drafts.single.haStorageDays, 0);
    expect(provider.drafts.single.ebStorageDays, 0);
  });

  testWidgets('falls back to flock entry date when stored age is zero', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      storageDays: 0,
      contextOverride: contextData(
        flockAgeWeeks: 0,
        flockEntryDate: DateTime(2025, 8, 1),
        date: '2026-05-08',
      ),
      benchmarkLookup: mockBenchmarkLookup(),
    );

    final bmkDisplayCard = find.byKey(
      const ValueKey('breakout-bmk-age-display-card'),
    );
    expect(
      find.descendant(of: bmkDisplayCard, matching: find.text('37 wks')),
      findsOneWidget,
    );
  });

  testWidgets('shows dash when bmk age cannot be calculated', (tester) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      contextOverride: contextData(flockAgeWeeks: null),
      benchmarkLookup: mockBenchmarkLookup(),
    );

    final bmkDisplayCard = find.byKey(
      const ValueKey('breakout-bmk-age-display-card'),
    );
    expect(
      find.descendant(of: bmkDisplayCard, matching: find.text('--')),
      findsOneWidget,
    );
  });

  testWidgets('storage days field updates persisted values and bmk weeks', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      storageDays: 5,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-storage-days'),
      '8',
    );

    expect(provider.drafts.single.haStorageDays, 8);
    expect(provider.drafts.single.ebStorageDays, 8);
    expect(find.text('41 wks'), findsOneWidget);
  });

  testWidgets('candled breakout exposes candled age and updates bmk age', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.candledEggBreakout,
      storageDays: 5,
      candlingDay: 9,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    expect(find.text('CANDLED AGE'), findsOneWidget);
    expect(find.text('40 wks'), findsOneWidget);
  });

  testWidgets('breakout counts are scoped by breakout type', (tester) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);
    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-count-infertile'),
      '12',
    );
    expect(
      EggBreakoutSampleEntry.decodeList(
        provider.drafts.single.ebTrayBreakoutJson,
      ).single.counts['infertile'],
      12,
    );

    await tapVisibleText(tester, 'Residue / Hatch Day');

    expect(
      numericFieldText(tester, const ValueKey('breakout-count-infertile')),
      isEmpty,
    );

    await addVisibleSample(tester);
    expect(
      numericFieldText(tester, const ValueKey('breakout-count-infertile')),
      isEmpty,
    );

    await tapVisibleText(tester, 'Fresh Egg');

    expect(
      numericFieldText(tester, const ValueKey('breakout-count-infertile')),
      '12',
    );
  });

  testWidgets('tray chips and add remove controls manage samples', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    expect(find.text('Tray scope'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('breakout-pool-sample-tab')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('breakout-sample-tab-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('breakout-count-infertile')),
      findsOneWidget,
    );

    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-count-infertile'),
      '12',
    );

    var savedSamples = EggBreakoutSampleEntry.decodeList(
      provider.drafts.single.ebTrayBreakoutJson,
    );
    expect(savedSamples, hasLength(1));
    expect(savedSamples.single.sampleMode, EggBreakoutSampleMode.pool);
    expect(savedSamples.single.counts['infertile'], 12);

    await addVisibleSample(tester);
    expect(find.byKey(const ValueKey('breakout-sample-tab-0')), findsOneWidget);
    expect(find.text('Tray 1'), findsWidgets);
    savedSamples = EggBreakoutSampleEntry.decodeList(
      provider.drafts.single.ebTrayBreakoutJson,
    );
    expect(savedSamples.single.sampleMode, EggBreakoutSampleMode.tray);

    await addVisibleSample(tester);

    expect(find.byKey(const ValueKey('breakout-sample-tab-1')), findsOneWidget);
    expect(find.text('Tray 2'), findsWidgets);
    savedSamples = EggBreakoutSampleEntry.decodeList(
      provider.drafts.single.ebTrayBreakoutJson,
    );
    expect(
      find.byKey(ValueKey('breakout-count-${savedSamples[0].id}-infertile')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('breakout-count-${savedSamples[1].id}-infertile')),
      findsOneWidget,
    );

    await tapVisibleKey(tester, const ValueKey('breakout-remove-sample'));

    expect(find.byKey(const ValueKey('breakout-sample-tab-1')), findsNothing);

    await tapVisibleKey(tester, const ValueKey('breakout-remove-sample'));

    expect(find.byKey(const ValueKey('breakout-sample-tab-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('breakout-pool-sample-tab')),
      findsOneWidget,
    );
  });

  testWidgets('editing one tray count does not update other tray fields', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);
    await addVisibleSample(tester);

    final samples = EggBreakoutSampleEntry.decodeList(
      provider.drafts.single.ebTrayBreakoutJson,
    );
    final firstCountKey = ValueKey('breakout-count-${samples[0].id}-infertile');
    final secondCountKey = ValueKey(
      'breakout-count-${samples[1].id}-infertile',
    );

    await tapVisibleKey(tester, const ValueKey('breakout-sample-tab-0'));
    await tester.ensureVisible(find.byKey(firstCountKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(firstCountKey), '12');
    await tester.pumpAndSettle();

    final savedSamples = EggBreakoutSampleEntry.decodeList(
      provider.drafts.single.ebTrayBreakoutJson,
    );
    expect(savedSamples[0].counts['infertile'], 12);
    expect(savedSamples[1].counts['infertile'], isNull);
    expect(editableNumberText(tester, firstCountKey), '12');
    expect(find.byKey(secondCountKey), findsNothing);

    await tapVisibleKey(tester, const ValueKey('breakout-sample-tab-1'));

    expect(find.byKey(firstCountKey), findsNothing);
    expect(editableNumberText(tester, secondCountKey), isEmpty);
  });

  testWidgets('duplicate saved tray ids are isolated before editing', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    provider.updateHatchField(
      0,
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList([
        EggBreakoutSampleEntry.tray(
          id: 'duplicate-tray',
          label: 'Tray 1',
          traySize: 150,
          breakoutType: EggBreakoutType.residueHatchDay,
        ),
        EggBreakoutSampleEntry.tray(
          id: 'duplicate-tray',
          label: 'Tray 2',
          traySize: 150,
          breakoutType: EggBreakoutType.residueHatchDay,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    const firstCountKey = ValueKey('breakout-count-duplicate-tray-infertile');
    const secondCountKey = ValueKey(
      'breakout-count-duplicate-tray-2-infertile',
    );

    await tester.ensureVisible(find.byKey(firstCountKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(firstCountKey), '12');
    await tester.pumpAndSettle();

    final savedSamples = EggBreakoutSampleEntry.decodeList(
      provider.drafts.single.ebTrayBreakoutJson,
    );
    expect(savedSamples.map((sample) => sample.id), [
      'duplicate-tray',
      'duplicate-tray-2',
    ]);
    expect(savedSamples[0].counts['infertile'], 12);
    expect(savedSamples[1].counts['infertile'], isNull);
    expect(editableNumberText(tester, firstCountKey), '12');
    expect(find.byKey(secondCountKey), findsNothing);

    await tapVisibleKey(tester, const ValueKey('breakout-sample-tab-1'));

    expect(find.byKey(firstCountKey), findsNothing);
    expect(editableNumberText(tester, secondCountKey), isEmpty);
  });

  testWidgets('editing one tray header does not update other tray headers', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );
      await addVisibleSample(tester);
      await addVisibleSample(tester);

      final samples = EggBreakoutSampleEntry.decodeList(
        provider.drafts.single.ebTrayBreakoutJson,
      );
      final firstTrayKey = ValueKey('${samples[0].id}-tray');
      final secondTrayKey = ValueKey('${samples[1].id}-tray');
      final firstTraySizeKey = ValueKey('${samples[0].id}-Tray size');
      final secondTraySizeKey = ValueKey('${samples[1].id}-Tray size');

      await tapVisibleKey(tester, const ValueKey('breakout-sample-tab-0'));
      await tester.ensureVisible(find.byKey(firstTrayKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(firstTrayKey), 'Left tray');
      await enterVisibleNumber(tester, firstTraySizeKey, '155');
      await tester.pumpAndSettle();

      final savedSamples = EggBreakoutSampleEntry.decodeList(
        provider.drafts.single.ebTrayBreakoutJson,
      );
      expect(savedSamples[0].label, 'Left tray');
      expect(savedSamples[0].tray, 'Left tray');
      expect(savedSamples[0].traySize, 155);
      expect(savedSamples[1].label, 'Tray 2');
      expect(savedSamples[1].tray, 'Tray 2');
      expect(savedSamples[1].traySize, 150);
      expect(editableNumberText(tester, firstTraySizeKey), '155');
      expect(find.byKey(secondTraySizeKey), findsNothing);
      expect(find.byKey(secondTrayKey), findsNothing);

      await tapVisibleKey(tester, const ValueKey('breakout-sample-tab-1'));

      expect(find.byKey(firstTraySizeKey), findsNothing);
      expect(find.byKey(firstTrayKey), findsNothing);
      expect(editableNumberText(tester, secondTraySizeKey), '150');
      expect(
        tester.widget<TextFormField>(find.byKey(secondTrayKey)).initialValue,
        'Tray 2',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('sample card keeps header fields in one balanced row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(540, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);
    final sample = activeBreakoutSample(provider);

    final trayField = find.byKey(ValueKey('${sample.id}-tray'));
    final positionField = find.byKey(ValueKey('${sample.id}-position'));
    final traySizeField = find.byKey(ValueKey('${sample.id}-Tray size'));

    expect(find.text('Tray 1'), findsNWidgets(2));
    expect(find.text('Tray sample'), findsNothing);
    expect(find.text('Pool sample'), findsNothing);
    expect(find.text('Total sample'), findsNothing);
    expect(find.byKey(ValueKey('${sample.id}-house')), findsNothing);
    expect(find.byKey(ValueKey('${sample.id}-setter')), findsNothing);
    expect(find.byKey(ValueKey('${sample.id}-hatcher')), findsNothing);
    expect(find.byKey(ValueKey('${sample.id}-trolley')), findsNothing);
    expect(trayField, findsOneWidget);
    expect(positionField, findsOneWidget);
    expect(traySizeField, findsOneWidget);
    final randomPositionText = tester.widget<Text>(
      find.descendant(of: positionField, matching: find.text('Random')),
    );
    expect(randomPositionText.style?.fontWeight, FontWeight.w400);
    expect(randomPositionText.style?.color, AppColors.textPrimary);
    expect(
      tester.getTopRight(find.text('Random')).dx,
      lessThan(tester.getTopRight(positionField).dx - 36),
    );
    for (final field in [trayField, positionField, traySizeField]) {
      expect(tester.getSize(field).height, greaterThan(40));
    }
    expect(
      tester.getSize(trayField).height,
      closeTo(tester.getSize(traySizeField).height, 0.1),
    );
  });

  testWidgets('breakout rows show count and one readable metric summary', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('breakout-count-infertile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('breakout-alert-infertile')),
      findsNothing,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(
      find.byKey(const ValueKey('breakout-summary-infertile')),
      findsOneWidget,
    );
    expect(find.text('0.0% | BMK 3.0% | Gap -3.0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('breakout-percent-infertile')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('breakout-bmk-infertile')), findsNothing);
    expect(find.byKey(const ValueKey('breakout-diff-infertile')), findsNothing);
  });

  testWidgets('breakout rows alert when calculated percent is above bmk', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);

    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-count-infertile'),
      '10',
    );

    expect(
      find.byKey(const ValueKey('breakout-alert-infertile')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('breakout count fields keep focus and advance on next action', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);

    const infertileKey = ValueKey('breakout-count-infertile');
    const early24hKey = ValueKey('breakout-count-early24h');
    await tester.ensureVisible(find.byKey(infertileKey));
    await tester.pumpAndSettle();
    await tester.tap(numericEditableFinder(infertileKey));
    await tester.pumpAndSettle();

    tester.testTextInput.enterText('2');
    await tester.pumpAndSettle();

    expect(numericFieldHasFocus(tester, infertileKey), isTrue);

    tester.testTextInput.enterText('21');
    await tester.pumpAndSettle();

    expect(
      EggBreakoutSampleEntry.decodeList(
        provider.drafts.single.ebTrayBreakoutJson,
      ).single.counts['infertile'],
      21,
    );
    expect(numericFieldHasFocus(tester, infertileKey), isTrue);

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(numericFieldHasFocus(tester, early24hKey), isTrue);
  });
}
