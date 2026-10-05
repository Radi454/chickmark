import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/data/repositories/benchmark_lookup.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatch_analysis_screen.dart';
import 'package:hatchaudit/features/audits/widgets/photo_button.dart';
import 'package:hatchaudit/features/audits/widgets/sampling_scope_controls.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'support/memory_panel_sampling_state_repository.dart';

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
  var screenSession = 0;
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
    sessionId: 'hatch-screen-${screenSession++}',
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
    final provider = AuditProvider(
      autosaveEnabled: false,
      panelSamplingStateRepository: MemoryPanelSamplingStateRepository(),
    );
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
    await provider.activateSamplingPanel(switch (breakoutType) {
      EggBreakoutType.freshEggBreakout => 'fresh_egg_breakout',
      EggBreakoutType.candledEggBreakout => 'candled_egg_breakout',
      EggBreakoutType.residueHatchDay => 'residue_breakout',
    });
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
    final provider = Provider.of<AuditProvider>(
      tester.element(find.byType(HatchAnalysisScreen)),
      listen: false,
    );
    final type = EggBreakoutType.fromStorageValue(
      provider.activeDraft.ebBreakoutType,
    );
    final panelKey = switch (type) {
      EggBreakoutType.freshEggBreakout => 'fresh_egg_breakout',
      EggBreakoutType.candledEggBreakout => 'candled_egg_breakout',
      EggBreakoutType.residueHatchDay => 'residue_breakout',
    };
    final state = await provider.loadPanelSamplingState(panelKey);
    final number = state.serialHighWatermark + 1;
    late String sampleId;
    if (type == EggBreakoutType.freshEggBreakout) {
      final house = await provider.addPanelScopeIdentity(
        panelKey,
        level: SamplingScopeLevel.house,
        parentId: null,
        discardPooledData: true,
        identity: {
          'id': 'test-house-$number',
          'code': 'H$number',
          'name': 'House $number',
        },
      );
      final terminal = await provider.addPanelTerminalSample(
        panelKey,
        parentId: house.id,
      );
      sampleId = terminal.sampleId!;
    } else {
      final tray = await provider.addPanelScopeIdentity(
        panelKey,
        level: SamplingScopeLevel.tray,
        parentId: null,
        identity: {'code': 'Tray $number'},
      );
      sampleId = tray.sampleId!;
    }
    await provider.selectPanelSample(panelKey, sampleId);
    final path = provider.samplingStateFor(panelKey)!.pathFor(sampleId);
    final label = [
      if (path.house != null) 'H${path.house}',
      if (path.setter != null) 'S${path.setter}',
      if (path.hatcher != null) 'HT${path.hatcher}',
      if (path.trolley != null) 'TR${path.trolley}',
      if (path.tray != null) 'T${path.tray}',
      'SA${path.sampleNumber}',
    ].join(' · ');
    final entry = type == EggBreakoutType.freshEggBreakout
        ? EggBreakoutSampleEntry.pool(
            id: sampleId,
            label: label,
            house: path.house,
            setter: path.setter,
            hatcher: path.hatcher,
            trolley: path.trolley,
            traySize: 30,
            breakoutType: type,
          )
        : EggBreakoutSampleEntry.tray(
            id: sampleId,
            label: label,
            house: path.house,
            setter: path.setter,
            hatcher: path.hatcher,
            trolley: path.trolley,
            tray: path.tray,
            breakoutType: type,
          );
    provider.updateHatchField(
      0,
      'ebTrayBreakoutJson',
      EggBreakoutSampleEntry.encodeList([entry]),
    );
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

  String panelKeyFor(EggBreakoutType type) => switch (type) {
    EggBreakoutType.freshEggBreakout => 'fresh_egg_breakout',
    EggBreakoutType.candledEggBreakout => 'candled_egg_breakout',
    EggBreakoutType.residueHatchDay => 'residue_breakout',
  };

  EggBreakoutSampleEntry activeBreakoutSample(AuditProvider provider) {
    final type = EggBreakoutType.fromStorageValue(
      provider.activeDraft.ebBreakoutType,
    );
    final panelKey = panelKeyFor(type);
    final sampleId = provider.activeSampleIdFor(panelKey)!;
    final entries = EggBreakoutSampleEntry.decodeList(
      provider.draftForSample(panelKey, sampleId)?.ebTrayBreakoutJson,
      fallbackBreakoutType: type,
    );
    if (entries.isNotEmpty) return entries.single;
    final state = provider.samplingStateFor(panelKey)!;
    final path = state.pathFor(sampleId);
    return type == EggBreakoutType.freshEggBreakout
        ? EggBreakoutSampleEntry.pool(
            id: sampleId,
            label: 'Sample ${path.sampleNumber}',
            house: path.house,
            setter: path.setter,
            hatcher: path.hatcher,
            traySize: 30,
            breakoutType: type,
          )
        : EggBreakoutSampleEntry.tray(
            id: sampleId,
            label: 'Sample ${path.sampleNumber}',
            house: path.house,
            setter: path.setter,
            hatcher: path.hatcher,
            tray: path.tray,
            breakoutType: type,
          );
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
    expect(find.text('Dead at Hatch'), findsNothing);
    expect(find.text('Candling Day'), findsNothing);
    expect(find.text('BMK Age 289 days'), findsNothing);

    for (final field in freshCountFields) {
      expect(find.byKey(ValueKey('breakout-row-${field.key}')), findsOneWidget);
    }
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

    for (final field in candledCountFields) {
      expect(find.byKey(ValueKey('breakout-row-${field.key}')), findsOneWidget);
    }
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
    expect(find.byType(SamplingScopeControls), findsOneWidget);
    expect(find.textContaining('Active sample:'), findsOneWidget);
    expect(find.byKey(const ValueKey('breakout-add-sample')), findsNothing);
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
      provider.samplingPhotoRowId('residue_breakout'),
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

  testWidgets('residue leaves use shared controls and retain hatch metrics', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    provider.updateHatchField(0, 'haTotalEggsSet', 19200);
    provider.updateHatchField(0, 'haHatched', 16500);
    provider.updateHatchField(0, 'haCulled', 120);
    provider.updateHatchField(0, 'haDead', 30);
    await tester.pumpAndSettle();

    expect(find.byType(SamplingScopeControls), findsOneWidget);
    final residueState = provider.samplingStateFor('residue_breakout')!;
    final firstId = provider.activeSampleIdFor('residue_breakout')!;
    expect(residueState.pathFor(firstId).tray, 'Tray1');
    expect(
      find.byKey(const ValueKey('hatch-performance-summary-card')),
      findsOneWidget,
    );
    expect(find.text('85.9%'), findsOneWidget);
    expect(find.text('0.6%'), findsOneWidget);
    expect(find.text('0.2%'), findsWidgets);

    await addVisibleSample(tester);
    final secondId = provider.activeSampleIdFor('residue_breakout')!;
    expect(secondId, isNot(firstId));
    expect(
      provider.samplingStateFor('residue_breakout')!.pathFor(secondId).tray,
      'Tray 2',
    );
    await provider.selectPanelSample('residue_breakout', firstId);
    await tester.pumpAndSettle();

    expect(provider.activeSampleIdFor('residue_breakout'), firstId);
    expect(
      find.byKey(const ValueKey('hatch-performance-summary-card')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('residue-batch-tabs')), findsNothing);
  });

  testWidgets('Residue exposes the shared terminal identity and metrics', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    final initialId = provider.activeSampleIdFor('residue_breakout')!;
    expect(
      provider.samplingStateFor('residue_breakout')!.pathFor(initialId).tray,
      'Tray1',
    );
    expect(find.byType(SamplingScopeControls), findsOneWidget);
    expect(find.byTooltip('Add Tray'), findsOneWidget);
    expect(find.byKey(const ValueKey('residue-batch-tabs')), findsNothing);
    expect(
      find.byKey(const ValueKey('hatch-performance-summary-card')),
      findsOneWidget,
    );
    expect(
      find.byType(MultiPhotoButton),
      findsNWidgets(residueCountFields.length),
    );

    await addVisibleSample(tester);
    final secondId = provider.activeSampleIdFor('residue_breakout')!;
    expect(secondId, isNot(initialId));
    final state = provider.samplingStateFor('residue_breakout')!;
    expect(state.pathFor(secondId).tray, 'Tray 2');
    expect(state.samples, hasLength(2));
    expect(
      find.byKey(const ValueKey('hatch-performance-summary-card')),
      findsOneWidget,
    );
  });

  testWidgets(
    'residue sampling uses shared controls and a real Tray identity',
    (tester) async {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );
      expect(find.byType(SamplingScopeControls), findsOneWidget);
      expect(find.text('Tray1'), findsWidgets);
      expect(find.byKey(const ValueKey('residue-add-batch')), findsNothing);
      expect(find.byKey(const ValueKey('residue-add-house')), findsNothing);
      final initialId = provider.activeSampleIdFor('residue_breakout');
      expect(initialId, isNotNull);
      expect(
        activeBreakoutSample(provider).sampleMode,
        EggBreakoutSampleMode.tray,
      );
    },
  );

  testWidgets('residue leaf does not invent machine or house identity', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    await addVisibleSample(tester);
    final sample = activeBreakoutSample(provider);
    expect(sample.house, isNull);
    expect(sample.setter, isNull);
    expect(sample.hatcher, isNull);
    expect(find.byKey(const ValueKey('residue-add-batch')), findsNothing);
  });

  testWidgets('breakout controls stay in the workbench without legacy tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    expect(find.byType(SamplingScopeControls), findsOneWidget);
    expect(find.byKey(const ValueKey('residue-add-batch')), findsNothing);
    expect(find.byKey(const ValueKey('residue-trolley-tabs')), findsNothing);
    expect(find.byKey(const ValueKey('breakout-add-sample')), findsNothing);
    expect(
      find.byKey(const ValueKey('residue-hatched-chicks-0')),
      findsOneWidget,
    );
  });

  testWidgets('legacy machine removal controls are not shown', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );

      expect(provider.activeSampleIdFor('residue_breakout'), isNotNull);
      expect(find.byKey(const ValueKey('residue-remove-batch')), findsNothing);
      expect(find.byKey(const ValueKey('residue-house-tab-0')), findsNothing);
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

  testWidgets(
    'residue samples expose the managed leaf and preserve tray data',
    (tester) async {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );
      await addVisibleSample(tester);
      final active = activeBreakoutSample(provider);
      expect(active.sampleMode, EggBreakoutSampleMode.tray);
      expect(active.house, isNull);
      expect(active.setter, isNull);
      expect(active.hatcher, isNull);
      expect(find.byType(SamplingScopeControls), findsOneWidget);
      expect(find.byKey(const ValueKey('residue-house-tabs')), findsNothing);
      expect(find.byKey(const ValueKey('residue-machine-tabs')), findsNothing);
    },
  );

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
      final firstId = provider.activeSampleIdFor('residue_breakout')!;
      expect(
        provider.draftForSample('residue_breakout', firstId)?.haHatched,
        11111,
      );

      await addVisibleSample(tester);
      final secondId = provider.activeSampleIdFor('residue_breakout')!;
      expect(
        provider.draftForSample('residue_breakout', secondId)?.haHatched,
        isNull,
      );
      expect(
        editableNumberText(tester, const ValueKey('residue-hatched-chicks-0')),
        isEmpty,
      );

      await enterVisibleNumber(
        tester,
        const ValueKey('residue-hatched-chicks-0'),
        '22222',
      );
      expect(
        provider.draftForSample('residue_breakout', secondId)?.haHatched,
        22222,
      );

      await provider.selectPanelSample('residue_breakout', firstId);
      await tester.pumpAndSettle();
      expect(
        editableNumberText(tester, const ValueKey('residue-hatched-chicks-0')),
        '11111',
      );
      expect(
        provider.draftForSample('residue_breakout', firstId)?.haHatched,
        11111,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('uses breakout type as the main card and removes old regions', (
    tester,
  ) async {
    await pumpScreen(tester, breakoutType: EggBreakoutType.residueHatchDay);

    expect(
      find.byKey(const ValueKey('hatch-analysis-breakout-header')),
      findsOneWidget,
    );
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

  testWidgets('residue count input is isolated between managed Tray leaves', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );

    expect(find.byType(SamplingScopeControls), findsOneWidget);
    expect(find.text('Tray1'), findsWidgets);
    expect(
      find.byKey(const ValueKey('breakout-count-infertile')),
      findsOneWidget,
    );

    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-count-infertile'),
      '12',
    );

    final firstId = provider.activeSampleIdFor('residue_breakout')!;
    expect(
      EggBreakoutSampleEntry.decodeList(
        provider
            .draftForSample('residue_breakout', firstId)!
            .ebTrayBreakoutJson,
      ).single.counts['infertile'],
      12,
    );
    await addVisibleSample(tester);
    final secondId = provider.activeSampleIdFor('residue_breakout')!;
    expect(secondId, isNot(firstId));
    expect(
      EggBreakoutSampleEntry.decodeList(
        provider
            .draftForSample('residue_breakout', secondId)!
            .ebTrayBreakoutJson,
      ).single.counts['infertile'],
      isNull,
    );
    expect(
      find.byKey(const ValueKey('breakout-count-infertile')),
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

    final state = provider.samplingStateFor('residue_breakout')!;
    final firstId = state.activeSampleId;
    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-count-infertile'),
      '12',
    );
    await addVisibleSample(tester);
    final secondId = provider.activeSampleIdFor('residue_breakout')!;
    expect(
      EggBreakoutSampleEntry.decodeList(
        provider
            .draftForSample('residue_breakout', firstId)!
            .ebTrayBreakoutJson,
      ).single.counts['infertile'],
      12,
    );
    expect(
      EggBreakoutSampleEntry.decodeList(
        provider
            .draftForSample('residue_breakout', secondId)!
            .ebTrayBreakoutJson,
      ).single.counts['infertile'],
      isNull,
    );
    expect(
      editableNumberText(tester, const ValueKey('breakout-count-infertile')),
      isEmpty,
    );
  });

  testWidgets('distinct sampling leaves have distinct immutable ids', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);
    final firstId = provider.activeSampleIdFor('residue_breakout')!;
    await addVisibleSample(tester);
    final secondId = provider.activeSampleIdFor('residue_breakout')!;
    final state = provider.samplingStateFor('residue_breakout')!;
    expect(firstId, isNot(secondId));
    expect(
      state.samples.map((sample) => sample.sampleId).toSet(),
      hasLength(3),
    );
    expect(state.samples.any((sample) => sample.sampleId == firstId), isTrue);
    expect(state.samples.any((sample) => sample.sampleId == secondId), isTrue);
  });

  testWidgets(
    'Tray identities remain separate from breakout measurement fields',
    (tester) async {
      final provider = await pumpScreen(
        tester,
        breakoutType: EggBreakoutType.residueHatchDay,
        benchmarkLookup: mockBenchmarkLookup(),
      );
      await addVisibleSample(tester);
      final firstId = provider.activeSampleIdFor('residue_breakout')!;
      await addVisibleSample(tester);
      final secondId = provider.activeSampleIdFor('residue_breakout')!;
      expect(firstId, isNot(secondId));
      expect(find.byType(SamplingScopeControls), findsOneWidget);
      expect(
        find.byKey(const ValueKey('residue-hatched-chicks-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('breakout-count-infertile')),
        findsOneWidget,
      );
    },
  );

  testWidgets('managed Tray identity and breakout metrics share the panel', (
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
    expect(sample.id, provider.activeSampleIdFor('residue_breakout'));
    expect(sample.sampleMode, EggBreakoutSampleMode.tray);
    expect(find.byType(SamplingScopeControls), findsOneWidget);
    expect(find.byKey(ValueKey('breakout-row-infertile')), findsOneWidget);
    expect(find.byKey(ValueKey('breakout-row-midDead')), findsOneWidget);
    expect(
      find.byType(MultiPhotoButton),
      findsNWidgets(residueCountFields.length),
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

  testWidgets('breakout count input retains focus and updates active leaf', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.freshEggBreakout,
      benchmarkLookup: mockBenchmarkLookup(),
    );
    await addVisibleSample(tester);

    const infertileKey = ValueKey('breakout-count-infertile');
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

    expect(provider.activeSampleIdFor('fresh_egg_breakout'), isNotNull);
  });

  testWidgets('hatch screen uses shared sampling controls', (tester) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
    );
    final sampleId = provider.activeSampleIdFor('residue_breakout');
    expect(sampleId, isNotNull);
    expect(find.byType(SamplingScopeControls), findsOneWidget);
    expect(find.text('Tray1'), findsWidgets);
    expect(find.byKey(const ValueKey('residue-add-house')), findsNothing);
    expect(find.byKey(const ValueKey('residue-add-batch')), findsNothing);
    expect(find.byKey(const ValueKey('residue-add-trolley')), findsNothing);
    expect(find.byKey(const ValueKey('breakout-add-sample')), findsNothing);
    expect(
      find.byKey(const ValueKey('residue-hatched-chicks-0')),
      findsOneWidget,
    );
  });

  testWidgets('managed leaf delete control replaces old house removal', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
    );
    await addVisibleSample(tester);
    expect(provider.activeSampleIdFor('residue_breakout'), isNotNull);
    expect(find.byType(SamplingScopeControls), findsOneWidget);
    expect(find.byKey(const ValueKey('residue-remove-house')), findsNothing);
  });

  testWidgets('residue managed sample retains measurement values in its leaf', (
    tester,
  ) async {
    final provider = await pumpScreen(
      tester,
      breakoutType: EggBreakoutType.residueHatchDay,
    );
    await enterVisibleNumber(
      tester,
      const ValueKey('breakout-count-infertile'),
      '12',
    );
    final sampleId = provider.activeSampleIdFor('residue_breakout')!;
    final stored = provider.draftForSample('residue_breakout', sampleId)!;
    expect(
      EggBreakoutSampleEntry.decodeList(
        stored.ebTrayBreakoutJson,
      ).single.counts,
      {'infertile': 12},
    );
    expect(find.byType(SamplingScopeControls), findsOneWidget);
    expect(find.byKey(const ValueKey('breakout-remove-sample')), findsNothing);
  });
}
