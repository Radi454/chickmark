import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/sample_mode.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_capture_screen.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatcher_optimizing_screen.dart';
import 'package:hatchaudit/features/audits/screens/setter_optimizing_screen.dart';
import 'package:hatchaudit/features/audits/widgets/audit_numeric_keyboard.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class FailingSaveAuditProvider extends AuditProvider {
  FailingSaveAuditProvider() : super(autosaveEnabled: false);

  @override
  Future<bool> saveSamplesWithResult({
    int? tabIndex,
    bool markAllTabsSaved = false,
  }) async {
    return false;
  }
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

  AuditContextData hatcherContext({
    String? hatcherId = 'H-01',
    String? sessionId,
  }) => AuditContextData(
    auditType: 'Hatchers',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    hatcherId: hatcherId,
    sessionId: sessionId,
    date: '2026-04-27',
  );

  AuditContextData setterContext({String? setterId = '5'}) => AuditContextData(
    auditType: 'Setters',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    setterId: setterId,
    date: '2026-04-27',
  );

  Future<AuditProvider> pumpHatcherScreen(
    WidgetTester tester, {
    String? hatcherId = 'H-01',
    String? sessionId,
    List<AuditModel> initialAudits = const [],
    List<StationSampleModel> initialStationSamples = const [],
  }) async {
    final provider = AuditProvider(autosaveEnabled: false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuditProvider>.value(value: provider),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
        ],
        child: MaterialApp(
          home: HatcherOptimizingScreen(
            context: hatcherContext(hatcherId: hatcherId, sessionId: sessionId),
            initialAudits: initialAudits,
            initialStationSamples: initialStationSamples,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  AuditModel hatcherAudit({
    required String id,
    required String hatcherId,
    required int hatchNumber,
    required int incubationAge,
    required int incubationHours,
    required double co2,
  }) {
    final now = DateTime(2026, 4, 27, 12);
    return AuditModel(
      id: id,
      auditType: 'Hatchers',
      customerId: 'customer-1',
      flockId: null,
      hatcherId: hatcherId,
      hoHatcherId: hatcherId,
      date: now,
      hatchNumber: hatchNumber,
      status: 'active',
      createdBy: 'tester',
      createdAt: now,
      updatedAt: now,
      sampleMode: SampleMode.compare,
      compareGroupKey: 'hatcher-group-1',
      hoIncubationAge: incubationAge,
      hoIncubationHours: incubationHours,
      hoCo2: co2,
    );
  }

  Future<AuditProvider> pumpSetterScreen(
    WidgetTester tester, {
    String? setterId = '5',
    AuditProvider? provider,
  }) async {
    final auditProvider = provider ?? AuditProvider(autosaveEnabled: false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuditProvider>.value(value: auditProvider),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(supabaseService: MockSupabaseService()),
          ),
        ],
        child: MaterialApp(
          home: SetterOptimizingScreen(
            context: setterContext(setterId: setterId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auditProvider;
  }

  testWidgets('Setter Scan readings launches the OCR capture screen (EST)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpSetterScreen(tester);

    final scanButton = find.widgetWithText(OutlinedButton, 'Scan readings');
    await tester.ensureVisible(scanButton);
    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(OcrCaptureScreen), findsOneWidget);
    expect(find.text('Step 1 of 9'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(OcrCaptureScreen), findsNothing);
  });

  testWidgets('Setter and Hatcher temperature units default to Fahrenheit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpSetterScreen(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('setter-est-unit-selector')),
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('setter-est-unit-f')))
          .selected,
      isTrue,
    );

    await pumpHatcherScreen(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('hatcher-cvt-unit-selector')),
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('hatcher-cvt-unit-f')))
          .selected,
      isTrue,
    );
  });

  testWidgets('Hatcher incubation age and hours use entry fields', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpHatcherScreen(tester);

      expect(find.text('Incubation Age: 18 days'), findsNothing);
      expect(find.text('Incubation Hours: 0 hours'), findsNothing);
      expect(
        find.byKey(const ValueKey('hatcher-incubation-hours-slider')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('hatcher-incubation-age-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('hatcher-incubation-hours-field')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('hatcher-incubation-age-field')),
        '20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('hatcher-incubation-hours-field')),
        '6',
      );
      await tester.pump();

      expect(provider.activeDraft.toMap()['hoIncubationAge'], 20);
      expect(provider.activeDraft.toMap()['hoIncubationHours'], 6);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Hatcher reopens multiple machine rows as machine chips', (
    tester,
  ) async {
    final first = hatcherAudit(
      id: 'hatcher-audit-5',
      hatcherId: 'H5',
      hatchNumber: 1,
      incubationAge: 18,
      incubationHours: 4,
      co2: 2150,
    );
    final second = hatcherAudit(
      id: 'hatcher-audit-7',
      hatcherId: 'H7',
      hatchNumber: 2,
      incubationAge: 19,
      incubationHours: 9,
      co2: 2875,
    );

    final provider = await pumpHatcherScreen(
      tester,
      sessionId: 'session-1',
      initialAudits: [first, second],
    );

    expect(provider.sampleCount, 2);
    expect(find.widgetWithText(ChoiceChip, 'H5'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'H7'), findsOneWidget);

    final h7Chip = find.widgetWithText(ChoiceChip, 'H7');
    await tester.ensureVisible(h7Chip);
    await tester.pumpAndSettle();
    await tester.tap(h7Chip);
    await tester.pump();

    expect(provider.activeDraft.id, 'hatcher-audit-7');
    expect(
      tester
          .widget<AuditNumericField>(
            find.byKey(const ValueKey('hatcher-incubation-age-field')),
          )
          .controller
          .text,
      '19',
    );
    expect(
      tester
          .widget<AuditNumericField>(
            find.byKey(const ValueKey('hatcher-incubation-hours-field')),
          )
          .controller
          .text,
      '9',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('hatcher-co2-field')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('hatcher-co2-field')))
          .controller
          ?.text,
      '2875',
    );
  });

  testWidgets(
    'Setter incubation age uses entry fields and updates scope label',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final provider = await pumpSetterScreen(tester);

        expect(find.text('Incubation age samples'), findsOneWidget);
        expect(find.text('Incubation age'), findsNothing);
        expect(find.widgetWithText(ChoiceChip, 'Pool'), findsOneWidget);
        expect(find.text('IAS1'), findsNothing);
        expect(
          find.byKey(const ValueKey('setter-incubation-age-field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('setter-incubation-hours-field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('setter-incubation-hours-slider')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const ValueKey('setter-incubation-age-field')),
          '7',
        );
        await tester.enterText(
          find.byKey(const ValueKey('setter-incubation-hours-field')),
          '12',
        );
        await tester.pump();

        expect(find.widgetWithText(ChoiceChip, 'Pool'), findsOneWidget);
        expect(find.text('IAS7'), findsNothing);
        expect(provider.activeDraft.toMap()['soIncubationAge'], 7);
        expect(provider.activeDraft.toMap()['soIncubationHours'], 12);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Setter screen uses machine scope with S-only tabs', (
    tester,
  ) async {
    final provider = await pumpSetterScreen(tester);

    expect(find.text('Machine scope'), findsOneWidget);
    expect(find.byTooltip('Add machine sample'), findsOneWidget);
    expect(find.text('Add machine'), findsNothing);
    expect(find.text('Add setter'), findsNothing);
    expect(find.text('S5'), findsOneWidget);
    expect(find.text('SH'), findsNothing);

    await tester.tap(find.byTooltip('Add machine sample'));
    await tester.pump();

    expect(provider.sampleCount, 2);
    expect(provider.stationSampleMode, StationSampleModel.sampleModeComparison);
    expect(find.byTooltip('Remove active machine sample'), findsOneWidget);
    expect(find.text('S5'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'S'), findsOneWidget);
    expect(find.text('SH'), findsNothing);
  });

  testWidgets(
    'Setter machine scope owns setter number and defaults blank samples to S',
    (tester) async {
      final provider = await pumpSetterScreen(tester, setterId: null);

      final setterNumberField = find.byKey(
        const ValueKey('setter-machine-scope-number-field'),
      );

      expect(
        find.byKey(const ValueKey('setter-machine-scope-card')),
        findsOneWidget,
      );
      expect(setterNumberField, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('setter-machine-scope-card')),
          matching: setterNumberField,
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(setterNumberField).controller?.text, 'S');
      expect(find.widgetWithText(ChoiceChip, 'S'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'S1'), findsNothing);
      expect(provider.activeDraft.setterId, 'S');
      expect(provider.activeDraft.soSetterId, 'S');

      await tester.ensureVisible(find.byTooltip('Add machine sample'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add machine sample'));
      await tester.pump();

      expect(provider.sampleCount, 2);
      expect(tester.widget<TextField>(setterNumberField).controller?.text, 'S');
      expect(provider.drafts.map((draft) => draft.setterId), ['S', 'S']);
      expect(provider.drafts.map((draft) => draft.soSetterId), ['S', 'S']);
      expect(find.widgetWithText(ChoiceChip, 'S'), findsNWidgets(2));

      await tester.enterText(setterNumberField, 'S12');
      await tester.pump();

      expect(provider.activeDraft.setterId, 'S12');
      expect(provider.activeDraft.soSetterId, 'S12');
      expect(find.widgetWithText(ChoiceChip, 'S12'), findsOneWidget);
    },
  );

  testWidgets(
    'Setter machine fields default to multi and calculate total eggs',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final provider = await pumpSetterScreen(tester);

        expect(provider.activeDraft.flockId, isNull);
        expect(provider.activeDraft.soBreed, isNull);
        expect(find.text('Breed from flock'), findsNothing);
        expect(find.text('Setter type'), findsOneWidget);
        expect(find.byKey(const ValueKey('setter-type-multi')), findsOneWidget);
        expect(find.text('Setpoint (°F)'), findsOneWidget);
        expect(find.text('Actual (°F)'), findsNothing);
        expect(find.text('Setpoint RH (%)'), findsOneWidget);
        expect(find.text('Actual RH (%)'), findsNothing);
        expect(
          find.byKey(const ValueKey('setter-actual-rh-field')),
          findsNothing,
        );
        expect(provider.activeDraft.soMachineType, 'Multi');
        expect(find.text('Setter settings'), findsNothing);

        await tester.enterText(
          find.byKey(const ValueKey('setter-batch-count-field')),
          '3',
        );
        await tester.pump();

        expect(find.text('Total set eggs: 57600'), findsOneWidget);
        expect(provider.activeDraft.soBatchSize, 19200);
        expect(provider.activeDraft.soBatchCount, 3);
        expect(provider.activeDraft.soTotalEggsSet, 57600);

        await tester.enterText(
          find.byKey(const ValueKey('setter-setpoint-rh-field')),
          '55',
        );
        await tester.pump();

        expect(provider.activeDraft.soSetpointRh, 55.0);
        expect(provider.activeDraft.soActualRh, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Setter controls use machine-scope selectors and media actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpSetterScreen(tester);

      final setterTab = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'S5'),
      );
      expect(setterTab.showCheckmark, isNull);

      expect(
        tester.getSize(find.byTooltip('Add machine sample')),
        const Size(48, 48),
      );
      expect(find.widgetWithIcon(InkResponse, Icons.add), findsWidgets);

      final multiType = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('setter-type-multi')),
      );
      expect(multiType.showCheckmark, isFalse);

      expect(find.text('Allowed 99.5-102°F'), findsNothing);
      expect(find.text('Optimum 100-101°F'), findsNothing);

      final turningAngleField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Turning Angle (°)',
        ),
      );
      expect(
        turningAngleField.decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(
        turningAngleField.decoration?.floatingLabelStyle?.color,
        const Color(0xFF1769D8),
      );
      expect(turningAngleField.decoration?.floatingLabelStyle?.fontSize, 14);
      final turningAnglePhotoButton = find.byKey(
        const ValueKey('setter-turning-angle-photo-button'),
      );
      expect(turningAnglePhotoButton, findsOneWidget);
      expect(
        (tester
                    .getCenter(
                      find.byWidgetPredicate(
                        (widget) =>
                            widget is TextField &&
                            widget.decoration?.labelText == 'Turning Angle (°)',
                      ),
                    )
                    .dy -
                tester.getCenter(turningAnglePhotoButton).dy)
            .abs(),
        lessThan(2),
      );

      final co2Field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'CO2 Level (ppm)',
      );
      final co2TextField = tester.widget<TextField>(co2Field);
      expect(
        co2TextField.decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(
        co2TextField.decoration?.floatingLabelStyle?.color,
        const Color(0xFF1769D8),
      );
      expect(co2TextField.decoration?.floatingLabelStyle?.fontSize, 14);
      final co2PhotoButton = find.byKey(
        const ValueKey('setter-co2-photo-button'),
      );
      expect(co2Field, findsOneWidget);
      expect(co2PhotoButton, findsOneWidget);
      expect(
        (tester.getCenter(co2Field).dy - tester.getCenter(co2PhotoButton).dy)
            .abs(),
        lessThan(2),
      );

      final frontTopField = find.byKey(
        const ValueKey('est-grid-input-front_top'),
      );
      await tester.ensureVisible(frontTopField);
      await tester.pumpAndSettle();

      await tester.enterText(frontTopField, '100');
      await tester.enterText(
        find.byKey(const ValueKey('est-grid-input-middle_top')),
        '102',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('AVG'));
      await tester.pumpAndSettle();

      expect(find.text('AVG'), findsOneWidget);
      expect(provider.activeDraft.soEstAvg, closeTo(101.0, 0.01));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Hatcher machine draft clears flock-scoped identity', (
    tester,
  ) async {
    final provider = await pumpHatcherScreen(tester);

    expect(provider.activeDraft.flockId, isNull);
    expect(provider.activeDraft.hoBreed, isNull);
    expect(find.text('Breed from flock'), findsNothing);
  });

  testWidgets('Scan readings launches the reusable OCR capture screen (CVT)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpHatcherScreen(tester);

      final scanButton = find.widgetWithText(OutlinedButton, 'Scan readings');
      await tester.ensureVisible(scanButton);
      await tester.tap(scanButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(OcrCaptureScreen), findsOneWidget);
      expect(find.text('Step 1 of 9'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(OcrCaptureScreen), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Hatcher screen uses setter-style hatcher hierarchy', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpHatcherScreen(tester);

      expect(find.text('Machine scope'), findsOneWidget);
      expect(find.text('H01'), findsOneWidget);
      expect(find.text('Hatcher settings'), findsOneWidget);
      expect(find.text('Hatcher number'), findsOneWidget);
      expect(find.text('Setpoint (°F)'), findsOneWidget);
      expect(find.text('Setpoint RH (%)'), findsOneWidget);
      expect(find.text('CVT sample 1'), findsNothing);
      expect(find.byTooltip('Add machine sample'), findsOneWidget);
      expect(find.text('Add hatcher'), findsNothing);
      expect(find.text('Add sample'), findsNothing);
      expect(find.text('Scan readings'), findsOneWidget);
      expect(find.text('CVT BMK 103-105°F'), findsNothing);
      expect(find.text('Chick vent temp.'), findsNothing);
      expect(find.text('Hatcher type'), findsNothing);
      expect(find.text('Turning Angle (°)'), findsNothing);
      expect(find.text('Transfer Day'), findsNothing);
      expect(find.text('Dark greenish'), findsOneWidget);
      expect(find.text('Water'), findsOneWidget);
      expect(find.text('Greenish'), findsNothing);
      expect(find.text('Watery'), findsNothing);
      expect(
        tester.getTopLeft(find.text('H01')).dy,
        lessThan(tester.getTopLeft(find.text('Hatcher settings')).dy),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('hatcher-machine-scope-card')),
          matching: find.byKey(
            const ValueKey('hatcher-machine-scope-number-field'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Hatcher settings')).dy,
        lessThan(tester.getTopLeft(find.text('Scan readings')).dy),
      );

      await tester.enterText(
        find.byKey(const ValueKey('hatcher-setpoint-f-field')),
        '99.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('hatcher-setpoint-rh-field')),
        '58',
      );
      await tester.pump();

      expect(provider.activeDraft.hoSetpointF, 99.5);
      expect(provider.activeDraft.hoSetpointRh, 58.0);

      final co2Field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'CO2 Level (ppm)',
      );
      await tester.ensureVisible(co2Field);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('hatcher-co2-field')),
        '2450',
      );
      await tester.pump();

      expect(provider.activeDraft.hoCo2, 2450.0);

      final co2FieldCenterY = tester.getCenter(co2Field).dy;
      final inlineCameraIcons = find.byIcon(Icons.camera_alt).evaluate().where((
        element,
      ) {
        final iconFinder = find.byWidget(element.widget);
        return (tester.getCenter(iconFinder).dy - co2FieldCenterY).abs() < 2;
      }).toList();
      expect(inlineCameraIcons, hasLength(1));

      await tester.ensureVisible(find.byTooltip('Add machine sample'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add machine sample'));
      await tester.pump();

      expect(provider.sampleCount, 2);
      expect(
        provider.stationSampleMode,
        StationSampleModel.sampleModeComparison,
      );
      expect(find.text('H01'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'H'), findsOneWidget);
      expect(find.byTooltip('Remove active machine sample'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Hatcher machine scope owns hatcher number and defaults blank samples to H',
    (tester) async {
      final provider = await pumpHatcherScreen(tester, hatcherId: null);

      final hatcherNumberField = find.byKey(
        const ValueKey('hatcher-machine-scope-number-field'),
      );

      expect(
        find.byKey(const ValueKey('hatcher-machine-scope-card')),
        findsOneWidget,
      );
      expect(hatcherNumberField, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('hatcher-machine-scope-card')),
          matching: hatcherNumberField,
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(hatcherNumberField).controller?.text,
        'H',
      );
      expect(find.widgetWithText(ChoiceChip, 'H'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'H1'), findsNothing);
      expect(provider.activeDraft.hatcherId, 'H');
      expect(provider.activeDraft.hoHatcherId, 'H');

      await tester.ensureVisible(find.byTooltip('Add machine sample'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add machine sample'));
      await tester.pump();

      expect(provider.sampleCount, 2);
      expect(
        tester.widget<TextField>(hatcherNumberField).controller?.text,
        'H',
      );
      expect(provider.drafts.map((draft) => draft.hatcherId), ['H', 'H']);
      expect(provider.drafts.map((draft) => draft.hoHatcherId), ['H', 'H']);
      expect(find.widgetWithText(ChoiceChip, 'H'), findsNWidgets(2));

      await tester.enterText(hatcherNumberField, 'H12');
      await tester.pump();

      expect(provider.activeDraft.hatcherId, 'H12');
      expect(provider.activeDraft.hoHatcherId, 'H12');
      expect(find.widgetWithText(ChoiceChip, 'H12'), findsOneWidget);
    },
  );

  testWidgets('Hatcher meconium assessment includes a photo action', (
    tester,
  ) async {
    await pumpHatcherScreen(tester);

    await tester.ensureVisible(find.text('Meconium Assessment'));
    await tester.pumpAndSettle();

    final meconiumCard = find.byKey(const ValueKey('hatcher-meconium-card'));
    expect(meconiumCard, findsOneWidget);
    expect(
      find.descendant(
        of: meconiumCard,
        matching: find.byKey(const ValueKey('hatcher-meconium-photo-button')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: meconiumCard,
        matching: find.byIcon(Icons.camera_alt),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Hatcher chick panting uses compact choices and header photo', (
    tester,
  ) async {
    final provider = await pumpHatcherScreen(tester);

    await tester.ensureVisible(find.text('Chick Panting'));
    await tester.pumpAndSettle();

    final pantingCard = find.byKey(
      const ValueKey('hatcher-chick-panting-card'),
    );
    expect(pantingCard, findsOneWidget);
    expect(
      find.descendant(
        of: pantingCard,
        matching: find.byType(SegmentedButton<bool>),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: pantingCard,
        matching: find.widgetWithText(ChoiceChip, 'No'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: pantingCard,
        matching: find.widgetWithText(ChoiceChip, 'Yes'),
      ),
      findsOneWidget,
    );
    final noChip = find.descendant(
      of: pantingCard,
      matching: find.widgetWithText(ChoiceChip, 'No'),
    );
    final yesChip = find.descendant(
      of: pantingCard,
      matching: find.widgetWithText(ChoiceChip, 'Yes'),
    );
    expect(tester.widget<ChoiceChip>(noChip).selected, isFalse);
    expect(tester.widget<ChoiceChip>(yesChip).selected, isFalse);
    expect(
      find.descendant(
        of: pantingCard,
        matching: find.byKey(
          const ValueKey('hatcher-chick-panting-photo-button'),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: pantingCard,
        matching: find.widgetWithText(ChoiceChip, 'Yes'),
      ),
    );
    await tester.pump();

    expect(provider.activeDraft.hoChickPanting, isTrue);
  });

  testWidgets(
    'Multi setter adds independent incubation age samples without breed picker',
    (tester) async {
      final provider = await pumpSetterScreen(tester);

      expect(find.text('Incubation age samples'), findsOneWidget);
      expect(find.text('Incubation age'), findsNothing);
      expect(find.text('EST sample 1'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Pool'), findsOneWidget);
      final poolChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Pool'),
      );
      expect(poolChip.selectedColor, AppColors.primary.withAlpha(30));
      expect(poolChip.labelStyle?.color, AppColors.primary);
      expect(poolChip.showCheckmark, isFalse);
      expect(find.text('Add IAS'), findsNothing);
      expect(find.byTooltip('Add incubation age sample'), findsOneWidget);
      expect(
        find.byTooltip('Remove active incubation age sample'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('setter-est-breed-dropdown')),
        findsNothing,
      );

      await tester.ensureVisible(find.byTooltip('Add incubation age sample'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add incubation age sample'));
      await tester.pump();

      expect(find.widgetWithText(ChoiceChip, 'Day 1 · 1'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Day 1 · 2'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Day 1'), findsNothing);
      expect(find.text('Incubation age 1'), findsNothing);
      expect(
        find.byTooltip('Remove active incubation age sample'),
        findsOneWidget,
      );
      final samples =
          jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>;
      expect(samples, hasLength(2));
      expect(samples.last['breed'], 'Ross308');
      expect(samples.last['incubationAge'], 1);
      expect(samples.last['incubationHours'], 0);
    },
  );

  testWidgets(
    'Setter EST readings stay attached to their incubation age sample',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final provider = await pumpSetterScreen(tester);
        final frontTop = find.byKey(const ValueKey('est-grid-input-front_top'));

        await tester.ensureVisible(frontTop);
        await tester.enterText(frontTop, '100.2');
        await tester.pump();

        await tester.ensureVisible(find.byTooltip('Add incubation age sample'));
        await tester.pump();
        await tester.tap(find.byTooltip('Add incubation age sample'));
        await tester.pump();

        expect(
          tester.widget<AuditNumericField>(frontTop).controller.text,
          isEmpty,
        );

        await tester.enterText(
          find.byKey(const ValueKey('setter-incubation-age-field')),
          '7',
        );
        await tester.enterText(frontTop, '101.4');
        await tester.pump();

        await tester.tap(find.widgetWithText(ChoiceChip, 'Day 1').first);
        await tester.pump();

        expect(
          tester.widget<AuditNumericField>(frontTop).controller.text,
          '100.2',
        );
        expect(provider.activeDraft.soIncubationAge, 1);
        expect(
          jsonDecode(provider.activeDraft.soEstReadings!)['front_top'],
          100.2,
        );

        await tester.tap(find.widgetWithText(ChoiceChip, 'Day 7'));
        await tester.pump();

        expect(
          tester.widget<AuditNumericField>(frontTop).controller.text,
          '101.4',
        );
        expect(provider.activeDraft.soIncubationAge, 7);
        expect(
          jsonDecode(provider.activeDraft.soEstReadings!)['front_top'],
          101.4,
        );
        final samples =
            jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>;
        expect(samples, hasLength(2));
        expect(samples.first['estReadings']['front_top'], 100.2);
        expect(samples.last['incubationAge'], 7);
        expect(samples.last['estReadings']['front_top'], 101.4);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Failed EST clear restores active incubation sample payload', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpSetterScreen(
        tester,
        provider: FailingSaveAuditProvider(),
      );
      final frontTop = find.byKey(const ValueKey('est-grid-input-front_top'));

      await tester.ensureVisible(frontTop);
      await tester.enterText(frontTop, '100.2');
      await tester.pump();

      expect(
        jsonDecode(
          provider.activeDraft.soEstSamplesJson!,
        ).first['estReadings']['front_top'],
        100.2,
      );

      await tester.tap(find.byTooltip('Clear reading and photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AuditNumericField>(frontTop).controller.text,
        '100.2',
      );
      expect(
        jsonDecode(
          provider.activeDraft.soEstSamplesJson!,
        ).first['estReadings']['front_top'],
        100.2,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Hatchers do not show sample mode controls', (tester) async {
    await pumpHatcherScreen(tester);

    expect(find.text('Add setter'), findsNothing);

    expect(find.text('Sample Mode'), findsNothing);
    expect(find.text('Single Sample'), findsNothing);
    expect(find.text('Compare Samples'), findsNothing);
  });
}
