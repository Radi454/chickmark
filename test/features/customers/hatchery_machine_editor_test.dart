import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_machine_model.dart';
import 'package:hatchaudit/data/repositories/hatchery_machine_repository.dart';
import 'package:hatchaudit/features/customers/widgets/hatchery_machine_editor.dart';

class _MemoryMachineRepository extends HatcheryMachineRepository {
  HatcheryMachineModel? saved;
  List<HatcheryMachineModel> machines = [];

  @override
  Future<void> saveMachine(HatcheryMachineModel machine) async {
    saved = machine;
  }

  @override
  Future<List<HatcheryMachineModel>> getByHatchery(
    String hatcheryId, {
    String? kind,
  }) async => machines
      .where(
        (machine) =>
            machine.hatcheryId == hatcheryId &&
            (kind == null || machine.kind == kind),
      )
      .toList();
}

HatcheryMachineModel _registeredMachine() => HatcheryMachineModel(
  id: 'fixed-machine-id',
  hatcheryId: 'hatchery-1',
  kind: 'setter',
  code: 'S-07',
  name: 'Setter North',
  batchSize: 19200,
  trolleyCapacity: 4800,
  traySize: 150,
  trolleyCount: 4,
  traysPerTrolley: 32,
);

void main() {
  testWidgets('registration calculates stored trolley and tray counts', (
    tester,
  ) async {
    final repository = _MemoryMachineRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => HatcheryMachineEditorDialog(
                  hatcheryId: 'hatchery-1',
                  kind: 'setter',
                  repository: repository,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'S-07');
    await tester.enterText(fields.at(1), 'Setter North');
    await tester.enterText(fields.at(2), '19200');
    await tester.enterText(fields.at(3), '4800');
    await tester.enterText(fields.at(4), '150');
    await tester.pump();

    expect(find.text('Trolleys: 4'), findsOneWidget);
    expect(find.text('Trays per trolley: 32'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.saved?.code, 'S-07');
    expect(repository.saved?.trolleyCount, 4);
    expect(repository.saved?.traysPerTrolley, 32);
  });

  testWidgets('capacity edit keeps the registered machine ID and code', (
    tester,
  ) async {
    final repository = _MemoryMachineRepository();
    final existing = _registeredMachine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => HatcheryMachineEditorDialog(
                  hatcheryId: existing.hatcheryId,
                  kind: existing.kind,
                  repository: repository,
                  machine: existing,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(tester.widget<TextFormField>(fields.first).enabled, isFalse);
    await tester.enterText(fields.at(2), '30001');
    await tester.enterText(fields.at(3), '5000');
    await tester.enterText(fields.at(4), '200');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.saved?.id, existing.id);
    expect(repository.saved?.code, existing.code);
    expect(repository.saved?.trolleyCount, 7);
    expect(repository.saved?.traysPerTrolley, 25);
  });

  testWidgets('read-only machine manager lists machines without edit actions', (
    tester,
  ) async {
    final repository = _MemoryMachineRepository()
      ..machines = [_registeredMachine()];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HatcheryMachineManagementSheet(
            hatcheryId: 'hatchery-1',
            repository: repository,
            readOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('S-07 · Setter North'), findsOneWidget);
    final registerButtons = tester.widgetList<TextButton>(
      find.widgetWithText(TextButton, 'Register'),
    );
    expect(registerButtons, hasLength(2));
    expect(registerButtons.every((button) => button.onPressed == null), isTrue);
    final editButtons = tester.widgetList<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.edit_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(editButtons, hasLength(1));
    final editButton = editButtons.single;
    expect(editButton.onPressed, isNull);
    expect(repository.saved, isNull);
  });
}
