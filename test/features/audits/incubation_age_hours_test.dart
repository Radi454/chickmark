import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/sample_mode.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_screen.dart';
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

  AuditContextData setterContext({
    String? setterId = '5',
    String? sessionId,
  }) => AuditContextData(
    auditType: 'Setters',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    setterId: setterId,
    sessionId: sessionId,
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
    AuditModel? initialAudit,
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
            context: setterContext(
              setterId: setterId,
              sessionId: initialAudit?.sessionId,
            ),
            initialAudit: initialAudit,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auditProvider;
  }

  Future<void> addNamedScope(
    WidgetTester tester, {
    required String tooltip,
    required Map<String, String> identities,
  }) async {
    final button = find.byTooltip(tooltip);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    for (final entry in identities.entries) {
      await tester.enterText(
        find.byKey(ValueKey('scope-identity-${entry.key}')),
        entry.value,
      );
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();
  }

  Future<void> openTooltip(WidgetTester tester, String tooltip) async {
    final button = find.byTooltip(tooltip);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('Setter Capture readings launches the capture screen (EST)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpSetterScreen(tester);

    final scanButton = find.widgetWithText(OutlinedButton, 'Capture readings');
    await tester.ensureVisible(scanButton);
    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TemperatureCaptureScreen), findsOneWidget);
    expect(find.text('Step 1 of 9'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TemperatureCaptureScreen), findsNothing);
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

    await addNamedScope(
      tester,
      tooltip: 'Add machine sample',
      identities: const {'setter': '7'},
    );

    expect(provider.sampleCount, 2);
    expect(provider.stationSampleMode, StationSampleModel.sampleModeComparison);
    expect(find.byTooltip('Remove active machine sample'), findsOneWidget);
    expect(find.text('S5'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'S7'), findsOneWidget);
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

      await addNamedScope(
        tester,
        tooltip: 'Add machine sample',
        identities: const {'setter': '12'},
      );

      expect(provider.sampleCount, 2);
      expect(
        tester.widget<TextField>(setterNumberField).controller?.text,
        '12',
      );
      expect(provider.drafts.map((draft) => draft.setterId), ['S', '12']);
      expect(provider.drafts.map((draft) => draft.soSetterId), ['S', '12']);
      expect(find.widgetWithText(ChoiceChip, 'S'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'S12'), findsOneWidget);

      await tester.enterText(setterNumberField, 'S13');
      await tester.pump();

      expect(provider.activeDraft.setterId, 'S13');
      expect(provider.activeDraft.soSetterId, 'S13');
      expect(find.widgetWithText(ChoiceChip, 'S13'), findsOneWidget);
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
      await pumpSetterScreen(tester);

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

      final frontTopCell = find.byKey(
        const ValueKey('est-grid-cell-front_top'),
      );
      await tester.ensureVisible(frontTopCell);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('est-grid-input-front_top')),
        findsNothing,
      );
      await tester.tap(frontTopCell);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TemperatureCaptureScreen), findsOneWidget);
      expect(find.text('Front - Top'), findsOneWidget);
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

  testWidgets('Capture readings launches the reusable capture screen (CVT)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpHatcherScreen(tester);

      final scanButton = find.widgetWithText(
        OutlinedButton,
        'Capture readings',
      );
      await tester.ensureVisible(scanButton);
      await tester.tap(scanButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TemperatureCaptureScreen), findsOneWidget);
      expect(find.text('Step 1 of 9'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TemperatureCaptureScreen), findsNothing);
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
      expect(find.text('Capture readings'), findsOneWidget);
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
        lessThan(tester.getTopLeft(find.text('Capture readings')).dy),
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

      await addNamedScope(
        tester,
        tooltip: 'Add machine sample',
        identities: const {'hatcher': '7'},
      );

      expect(provider.sampleCount, 2);
      expect(
        provider.stationSampleMode,
        StationSampleModel.sampleModeComparison,
      );
      expect(find.text('H01'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'H7'), findsOneWidget);
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

      await addNamedScope(
        tester,
        tooltip: 'Add machine sample',
        identities: const {'hatcher': '12'},
      );

      expect(provider.sampleCount, 2);
      expect(
        tester.widget<TextField>(hatcherNumberField).controller?.text,
        '12',
      );
      expect(provider.drafts.map((draft) => draft.hatcherId), ['H', '12']);
      expect(provider.drafts.map((draft) => draft.hoHatcherId), ['H', '12']);
      expect(find.widgetWithText(ChoiceChip, 'H'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'H12'), findsOneWidget);

      await tester.enterText(hatcherNumberField, 'H13');
      await tester.pump();

      expect(provider.activeDraft.hatcherId, 'H13');
      expect(provider.activeDraft.hoHatcherId, 'H13');
      expect(find.widgetWithText(ChoiceChip, 'H13'), findsOneWidget);
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

      await addNamedScope(
        tester,
        tooltip: 'Add incubation age sample',
        identities: const {'incubationAge': '2', 'incubationHours': '4'},
      );

      expect(find.widgetWithText(ChoiceChip, 'Day 1'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Day 2'), findsOneWidget);
      expect(find.text('Incubation age 1'), findsNothing);
      expect(
        find.byTooltip('Remove active incubation age sample'),
        findsOneWidget,
      );
      final samples =
          jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>;
      expect(samples, hasLength(2));
      expect(samples.last['breed'], 'Ross308');
      expect(samples.last['incubationAge'], 2);
      expect(samples.last['incubationHours'], 4);
    },
  );

  testWidgets(
    'Setter EST display grid opens capture for the active incubation sample',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final provider = await pumpSetterScreen(tester);
        final frontTop = find.byKey(const ValueKey('est-grid-cell-front_top'));

        await tester.ensureVisible(frontTop);
        await tester.tap(frontTop);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(TemperatureCaptureScreen), findsOneWidget);
        expect(find.text('Front - Top'), findsOneWidget);
        final samples =
            jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>;
        expect(samples, hasLength(1));
        expect(samples.first['incubationAge'], 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Setter EST display grid removes inline clear controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpSetterScreen(tester, provider: FailingSaveAuditProvider());
      final frontTop = find.byKey(const ValueKey('est-grid-cell-front_top'));

      await tester.ensureVisible(frontTop);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Clear reading and photo'), findsNothing);
      expect(
        find.byKey(const ValueKey('est-grid-input-front_top')),
        findsNothing,
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

  testWidgets('Setter machine add validates identity and guards result loss', (
    tester,
  ) async {
    final provider = await pumpSetterScreen(tester);

    await openTooltip(tester, 'Add machine sample');
    expect(find.text('Add Machine scope'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-identity-cancel')));
    await tester.pumpAndSettle();
    expect(provider.sampleCount, 1);

    await addNamedScope(
      tester,
      tooltip: 'Add machine sample',
      identities: const {'setter': '7'},
    );
    expect(provider.sampleCount, 2);
    expect(provider.activeDraft.setterId, '7');
    expect(provider.activeDraft.soSetterId, '7');

    await openTooltip(tester, 'Add machine sample');
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-setter')),
      'S7',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();
    expect(
      find.text('A Machine scope with this identity already exists.'),
      findsOneWidget,
    );
    expect(provider.sampleCount, 2);
    await tester.tap(find.byKey(const ValueKey('scope-identity-cancel')));
    await tester.pumpAndSettle();

    provider.updateField('soCo2', 1800.0);
    await tester.pumpAndSettle();
    await openTooltip(tester, 'Remove active machine sample');
    expect(find.text('Remove scope?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-removal-cancel')));
    await tester.pumpAndSettle();
    expect(provider.sampleCount, 2);
    expect(provider.activeDraft.soCo2, 1800);

    await openTooltip(tester, 'Remove active machine sample');
    await tester.tap(find.byKey(const ValueKey('scope-removal-confirm')));
    await tester.pumpAndSettle();
    expect(provider.sampleCount, 1);
  });

  testWidgets('Hatcher machine add validates identity and guards result loss', (
    tester,
  ) async {
    final provider = await pumpHatcherScreen(tester);

    await openTooltip(tester, 'Add machine sample');
    await tester.tap(find.byKey(const ValueKey('scope-identity-cancel')));
    await tester.pumpAndSettle();
    expect(provider.sampleCount, 1);

    await addNamedScope(
      tester,
      tooltip: 'Add machine sample',
      identities: const {'hatcher': '7'},
    );
    expect(provider.activeDraft.hatcherId, '7');
    expect(provider.activeDraft.hoHatcherId, '7');

    await openTooltip(tester, 'Add machine sample');
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-hatcher')),
      'H7',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();
    expect(
      find.text('A Machine scope with this identity already exists.'),
      findsOneWidget,
    );
    expect(provider.sampleCount, 2);
    await tester.tap(find.byKey(const ValueKey('scope-identity-cancel')));
    await tester.pumpAndSettle();

    provider.updateField('hoChickPanting', false);
    await tester.pumpAndSettle();
    await openTooltip(tester, 'Remove active machine sample');
    expect(find.text('Remove scope?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-removal-cancel')));
    await tester.pumpAndSettle();
    expect(provider.sampleCount, 2);
    expect(provider.activeDraft.hoChickPanting, isFalse);

    await openTooltip(tester, 'Remove active machine sample');
    await tester.tap(find.byKey(const ValueKey('scope-removal-confirm')));
    await tester.pumpAndSettle();
    expect(provider.sampleCount, 1);
  });

  testWidgets('Setter EST add validates age and identity before mutation', (
    tester,
  ) async {
    final provider = await pumpSetterScreen(tester);
    final beforeJson = provider.activeDraft.soEstSamplesJson;

    await openTooltip(tester, 'Add incubation age sample');
    expect(find.text('Add Incubation age scope'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-identity-cancel')));
    await tester.pumpAndSettle();
    expect(provider.activeDraft.soEstSamplesJson, beforeJson);

    await addNamedScope(
      tester,
      tooltip: 'Add incubation age sample',
      identities: const {'incubationAge': '2', 'incubationHours': '4'},
    );
    var samples =
        jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>;
    expect(samples, hasLength(2));
    expect(samples.last['incubationAge'], 2);
    expect(samples.last['incubationHours'], 4);

    await openTooltip(tester, 'Add incubation age sample');
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-incubationAge')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-incubationHours')),
      '4',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();
    expect(
      find.text('An incubation age scope with this identity already exists.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('scope-identity-cancel')));
    await tester.pumpAndSettle();

    await openTooltip(tester, 'Remove active incubation age sample');
    expect(find.text('Remove scope?'), findsNothing);
    samples =
        jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>;
    expect(samples, hasLength(1));
  });

  testWidgets('Setter EST removal protects selected readings', (tester) async {
    final now = DateTime(2026, 4, 27, 12);
    final initialAudit = AuditModel(
      id: 'setter-est-results',
      auditType: 'Setters',
      customerId: 'customer-1',
      flockId: 'flock-1',
      setterId: '5',
      soSetterId: '5',
      date: now,
      hatchNumber: 1,
      status: 'active',
      createdBy: 'tester',
      createdAt: now,
      updatedAt: now,
      sessionId: 'session-1',
      soEstSamplesJson: jsonEncode([
        {
          'id': 'est-result',
          'breed': 'Ross308',
          'incubationAge': 1,
          'incubationHours': 0,
          'estReadings': {
            'unit': 'fahrenheit',
            'readings': {'front_top': 100.0},
          },
          'estPhotos': <String, String>{},
          'estAvg': 100.0,
          'estCv': 0.0,
        },
        {
          'id': 'est-empty',
          'breed': 'Ross308',
          'incubationAge': 2,
          'incubationHours': 4,
          'estReadings': <String, double>{},
          'estPhotos': <String, String>{},
          'estAvg': null,
          'estCv': null,
        },
      ]),
    );
    final provider = await pumpSetterScreen(tester, initialAudit: initialAudit);

    await openTooltip(tester, 'Remove active incubation age sample');
    expect(find.text('Remove scope?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-removal-cancel')));
    await tester.pumpAndSettle();
    expect(
      jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>,
      hasLength(2),
    );

    await openTooltip(tester, 'Remove active incubation age sample');
    await tester.tap(find.byKey(const ValueKey('scope-removal-confirm')));
    await tester.pumpAndSettle();
    final remaining =
        jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>;
    expect(remaining, hasLength(1));
    expect(remaining.single['id'], 'est-empty');
  });
}
