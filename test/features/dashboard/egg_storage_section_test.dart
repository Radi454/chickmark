import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/egg_storage_section.dart';
import 'package:provider/provider.dart';

class _StaticDashboardProvider extends DashboardProvider {
  final EggStorageTrend? _latest;
  final EggStorageEstEvidence? _evidence;

  _StaticDashboardProvider({
    EggStorageTrend? latest,
    EggStorageEstEvidence? evidence,
  }) : _latest = latest,
       _evidence = evidence;

  @override
  List<CustomerModel> get customers => const [];

  @override
  bool get isLoading => false;

  @override
  EggStorageTrend? get eggStorageLatest => _latest;

  @override
  List<EggStorageTrend> get eggStorageTrend =>
      _latest == null ? const [] : [_latest];

  @override
  EggStorageEstEvidence? get eggStorageEstEvidence => _evidence;

  @override
  Future<void> init({UserModel? currentUser}) async {}
}

void main() {
  testWidgets('storage and handling metadata render in one Storage Info card', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DashboardProvider>(
        create: (_) => _StaticDashboardProvider(
          latest: EggStorageTrend.fromMap(const {
            'date': '2026-05-18',
            'storageDays': 6,
            'turningTimes': 4,
            'traySpacing': 'Adequate',
            'coolerProximity': 'Far',
            'condensationPresent': 0,
          }),
          evidence: EggStorageEstEvidence.fromJsonStrings(
            readingsJson:
                '{"front_top":28.7,"middle_top":28.5,"back_top":27.8,"front_middle":29.0,"middle_middle":23.0,"back_middle":27.4,"front_bottom":28.7,"middle_bottom":23.0,"back_bottom":27.4}',
          ),
        ),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EggStorageSection()),
          ),
        ),
      ),
    );

    expect(find.text('Storage Info'), findsOneWidget);
    expect(find.text('Storage Checklist'), findsNothing);
    expect(find.text('Handling Metadata'), findsNothing);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('6 days'), findsOneWidget);
    expect(find.text('Turning'), findsOneWidget);
    expect(find.text('4 times'), findsOneWidget);
    expect(find.text('Tray spacing'), findsOneWidget);
    expect(find.text('Adequate'), findsOneWidget);
    expect(find.text('Cooler'), findsOneWidget);
    expect(find.text('Far'), findsOneWidget);
    expect(find.text('Condensation'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Recorded'), findsOneWidget);
  });
}
