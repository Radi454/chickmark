import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/models/sampling_scope.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/data/models/panel_sampling_state.dart';
import 'package:hatchaudit/data/repositories/panel_sampling_state_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/widgets/sampling_scope_controls.dart';
import 'package:provider/provider.dart';

class _RegisteredHouseRepository extends PoultryHierarchyRepository {
  @override
  Future<List<HouseModel>> listHouses(
    String flockId, {
    bool activeOnly = true,
  }) async => [
    HouseModel(
      id: 'house-1',
      flockId: flockId,
      name: 'North House',
      code: 'N01',
    ),
  ];
}

class _EmptyHouseRepository extends PoultryHierarchyRepository {
  @override
  Future<List<HouseModel>> listHouses(
    String flockId, {
    bool activeOnly = true,
  }) async => const [];
}

class _PickerSamplingRepository extends PanelSamplingStateRepository {
  PanelSamplingState state = PanelSamplingState(
    sessionId: 'session-1',
    panelKey: 'egg_quality',
    serialHighWatermark: 1,
    activeSampleId: 'sample-1',
    nodes: [
      SamplingNode(
        id: 'sample-node-1',
        sessionId: 'session-1',
        panelKey: 'egg_quality',
        level: SamplingScopeLevel.sample,
        identityKey: 'SA1',
        identity: {},
        sampleId: 'sample-1',
        sampleNumber: 1,
      ),
    ],
  );

  @override
  Future<PanelSamplingState> loadOrCreateDefault({
    required String sessionId,
    required String panelKey,
  }) async => state;

  @override
  Future<SamplingNode> addScopeIdentity({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    required SamplingScopeLevel level,
    required Map<String, String> identity,
    bool discardPooledData = false,
  }) async {
    final node = SamplingNode(
      id: 'house-node-1',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: level,
      identityKey: identity['code']!,
      identity: identity,
    );
    state = PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      serialHighWatermark: state.serialHighWatermark,
      activeSampleId: state.activeSampleId,
      nodes: [...state.nodes, node],
    );
    return node;
  }

  @override
  Future<SamplingNode> addTerminalSample({
    required String sessionId,
    required String panelKey,
    required String? parentId,
    Map<String, String>? identity,
  }) async {
    final node = SamplingNode(
      id: 'sample-node-2',
      sessionId: sessionId,
      panelKey: panelKey,
      parentId: parentId,
      level: SamplingScopeLevel.sample,
      identityKey: 'SA2',
      identity: const {},
      sampleId: 'sample-2',
      sampleNumber: 2,
    );
    state = PanelSamplingState(
      sessionId: sessionId,
      panelKey: panelKey,
      serialHighWatermark: 2,
      activeSampleId: node.sampleId!,
      nodes: [...state.nodes, node],
    );
    return node;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSampling(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'registered House picker identity is accepted by the repository',
    (tester) async {
      final samplingRepository = _PickerSamplingRepository();
      final provider =
          AuditProvider(
            autosaveEnabled: false,
            panelSamplingStateRepository: samplingRepository,
          )..initialize(
            AuditContext(
              auditType: 'Egg',
              customerId: 'customer-1',
              flockId: 'flock-1',
              hatcheryId: 'hatchery-1',
              breed: 'Ross308',
              date: '2026-10-05',
            ),
            sessionId: 'session-1',
            notify: false,
          );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SamplingScopeControls(
                  panelKey: 'egg_quality',
                  houseRepository: _RegisteredHouseRepository(),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSampling(tester);
      expect(find.text('Sampling'), findsOneWidget);
      final activeSampleChip = tester.widget<ChoiceChip>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ChoiceChip &&
              widget.selected &&
              widget.label is Text &&
              ((widget.label as Text).data == 'SA1'),
        ),
      );
      expect(
        (activeSampleChip.label as Text).style?.color,
        Theme.of(
          tester.element(find.byType(ChoiceChip).first),
        ).colorScheme.onPrimary,
      );
      await tester.tap(find.byTooltip('Add House'));
      await pumpSampling(tester);
      expect(find.text('Registered houses could not be loaded.'), findsNothing);
      await tester.tap(
        find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
      );
      await pumpSampling(tester);
      await tester.tap(find.text('North House').last);
      await pumpSampling(tester);
      await tester.tap(find.text('Save').last);
      await pumpSampling(tester);

      final state = samplingRepository.state;
      final house = state.nodes.singleWhere(
        (node) => node.level == SamplingScopeLevel.house,
      );
      expect(house.identity['id'], 'house-1');
      expect(house.identity['code'], 'N01');
      expect(house.identity['name'], 'North House');
      expect(state.samples, hasLength(2));
      provider.dispose();
    },
  );

  testWidgets('empty House picker explains how to add registered houses', (
    tester,
  ) async {
    final provider =
        AuditProvider(
          autosaveEnabled: false,
          panelSamplingStateRepository: _PickerSamplingRepository(),
        )..initialize(
          AuditContext(
            auditType: 'Egg',
            customerId: 'customer-1',
            flockId: 'customer-flock-no-houses',
            hatcheryId: 'hatchery-1',
            breed: 'Ross308',
            date: '2026-10-05',
          ),
          sessionId: 'session-empty-houses',
          notify: false,
        );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SamplingScopeControls(
                panelKey: 'egg_quality',
                houseRepository: _EmptyHouseRepository(),
              ),
            ),
          ),
        ),
      ),
    );
    await pumpSampling(tester);
    await tester.tap(find.text('Add House'));
    await pumpSampling(tester);

    expect(
      find.text(
        'No houses are registered for this flock. Add houses in Flock Management, then return here.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    provider.dispose();
  });
}
