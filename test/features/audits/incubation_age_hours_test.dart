import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/station_sample_model.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/hatcher_optimizing_screen.dart';
import 'package:hatchaudit/features/audits/screens/setter_optimizing_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

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

  AuditContextData hatcherContext() => AuditContextData(
    auditType: 'Hatchers',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    hatcherId: 'H-01',
    date: '2026-04-27',
  );

  AuditContextData setterContext() => AuditContextData(
    auditType: 'Setters',
    customerId: 'customer-1',
    flockId: 'flock-1',
    breed: 'Ross 308',
    setterId: '5',
    date: '2026-04-27',
  );

  Future<AuditProvider> pumpHatcherScreen(WidgetTester tester) async {
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
          home: HatcherOptimizingScreen(context: hatcherContext()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  Future<AuditProvider> pumpSetterScreen(WidgetTester tester) async {
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
          home: SetterOptimizingScreen(context: setterContext()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  testWidgets('Hatcher incubation age includes a selectable hour offset', (
    tester,
  ) async {
    final provider = await pumpHatcherScreen(tester);

    expect(find.text('Incubation Age: 18 days'), findsOneWidget);
    expect(find.text('Incubation Hours: 0 hours'), findsOneWidget);

    final hoursSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('hatcher-incubation-hours-slider')),
    );
    hoursSlider.onChanged!(6);
    await tester.pump();

    expect(find.text('Incubation Hours: 6 hours'), findsOneWidget);
    expect(provider.activeDraft.toMap()['hoIncubationHours'], 6);
  });

  testWidgets('Setter incubation age includes a selectable hour offset', (
    tester,
  ) async {
    final provider = await pumpSetterScreen(tester);

    expect(find.text('Incubation Age: 1 days'), findsOneWidget);
    expect(find.text('Incubation Hours: 0 hours'), findsOneWidget);

    final hoursSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('setter-incubation-hours-slider')),
    );
    hoursSlider.onChanged!(12);
    await tester.pump();

    expect(find.text('Incubation Hours: 12 hours'), findsOneWidget);
    expect(provider.activeDraft.toMap()['soIncubationHours'], 12);
  });

  testWidgets('Setter screen can add setter tabs labeled by setter number', (
    tester,
  ) async {
    final provider = await pumpSetterScreen(tester);

    expect(find.text('S5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('setter-add-sample-button')));
    await tester.pump();

    expect(provider.sampleCount, 2);
    expect(provider.stationSampleMode, StationSampleModel.sampleModeComparison);
    expect(find.text('S5'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
  });

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
        expect(find.text('Setpoint RH (%)'), findsOneWidget);
        expect(find.text('Actual RH (%)'), findsOneWidget);
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
        await tester.enterText(
          find.byKey(const ValueKey('setter-actual-rh-field')),
          '57.5',
        );
        await tester.pump();

        expect(provider.activeDraft.soSetpointRh, 55.0);
        expect(provider.activeDraft.soActualRh, 57.5);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Setter controls use clean selectors and inline media actions', (
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
      expect(setterTab.showCheckmark, isFalse);

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

  testWidgets('Hatcher screen uses setter-style hatcher hierarchy', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final provider = await pumpHatcherScreen(tester);

      expect(find.text('Hatchers'), findsWidgets);
      expect(find.text('H01'), findsOneWidget);
      expect(find.text('Hatcher settings'), findsOneWidget);
      expect(find.text('Hatcher number'), findsOneWidget);
      expect(find.text('Setpoint (°F)'), findsOneWidget);
      expect(find.text('Setpoint RH (%)'), findsOneWidget);
      expect(find.text('CVT sample 1'), findsNothing);
      expect(find.text('Add hatcher'), findsOneWidget);
      expect(find.text('Add sample'), findsNothing);
      expect(find.text('Guided CVT capture'), findsOneWidget);
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
        tester.getTopLeft(find.text('Hatcher settings')).dy,
        lessThan(tester.getTopLeft(find.text('Guided CVT capture')).dy),
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

      final co2FieldCenterY = tester.getCenter(co2Field).dy;
      final inlineCameraIcons = find.byIcon(Icons.camera_alt).evaluate().where((
        element,
      ) {
        final iconFinder = find.byWidget(element.widget);
        return (tester.getCenter(iconFinder).dy - co2FieldCenterY).abs() < 2;
      }).toList();
      expect(inlineCameraIcons, hasLength(1));

      await tester.ensureVisible(
        find.byKey(const ValueKey('hatcher-add-sample-button')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hatcher-add-sample-button')));
      await tester.pump();

      expect(provider.sampleCount, 2);
      expect(
        provider.stationSampleMode,
        StationSampleModel.sampleModeComparison,
      );
      expect(find.text('H01'), findsOneWidget);
      expect(find.text('H2'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

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

  testWidgets('Multi setter adds independent age breed EST samples', (
    tester,
  ) async {
    final provider = await pumpSetterScreen(tester);

    expect(find.text('EST sample 1'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('setter-est-sample-add-button')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('setter-est-sample-add-button')),
    );
    await tester.pump();

    expect(find.text('EST sample 2'), findsWidgets);
    final samples =
        jsonDecode(provider.activeDraft.soEstSamplesJson!) as List<dynamic>;
    expect(samples, hasLength(2));
    expect(samples.last['breed'], 'Ross308');
    expect(samples.last['incubationAge'], 1);
    expect(samples.last['incubationHours'], 0);
  });

  testWidgets('Hatchers do not show sample mode controls', (tester) async {
    await pumpHatcherScreen(tester);

    expect(find.text('Add setter'), findsNothing);

    expect(find.text('Sample Mode'), findsNothing);
    expect(find.text('Single Sample'), findsNothing);
    expect(find.text('Compare Samples'), findsNothing);
  });
}
