import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/features/audits/providers/audits_list_provider.dart';
import 'package:hatchaudit/features/audits/widgets/session_card.dart';

const _resolver = SessionDisplayResolver(
  customerName: _name,
  hatcheryName: _hatchery,
  flockLabel: _flock,
  flockBreed: _breed,
);
String _name(String id) => 'Acme';
String _hatchery(String? id) => 'Demo Hatchery';
String _flock(String? id) => 'DEMO-F1';
String? _breed(String? id) => 'Ross 308';

AuditSessionModel _session() => AuditSessionModel(
  id: 's1',
  customerId: 'c1',
  flockId: 'f1',
  hatcheryId: 'h1',
  date: DateTime(2026, 6, 1),
  status: 'in_progress',
  syncStatus: 'synced',
  selectedStationKeys: const ['egg'],
  stationsCompleted: const [],
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

SessionView _view({required int goveeCount, required String goveeSync}) {
  return SessionView(
    session: _session(),
    stations: const [
      StationView(
        key: 'egg',
        label: 'Egg',
        status: StationDataStatus.inProgress,
        sync: 'synced',
      ),
    ],
    sync: 'synced',
    completed: 0,
    total: 1,
    goveeCaptureCount: goveeCount,
    goveeSync: goveeSync,
  );
}

Future<void> _pumpExpanded(WidgetTester tester, SessionView view) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SessionCard(
          view: view,
          resolver: _resolver,
          canEdit: true,
          onResumeVisit: () {},
          onOpenStation: (_) {},
          onDelete: () {},
          onClearStation: (_) {},
        ),
      ),
    ),
  );
  // Expand the card to reveal the sector rows.
  await tester.tap(find.byType(InkWell).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a Govee sector row with the reading count when captured', (
    tester,
  ) async {
    await _pumpExpanded(tester, _view(goveeCount: 3, goveeSync: 'pending'));

    expect(find.text('Govee Readings'), findsOneWidget);
    expect(find.text('3 readings'), findsOneWidget);
    expect(find.byIcon(Icons.device_thermostat), findsOneWidget);
  });

  testWidgets('singular label for a single reading', (tester) async {
    await _pumpExpanded(tester, _view(goveeCount: 1, goveeSync: 'synced'));

    expect(find.text('1 reading'), findsOneWidget);
  });

  testWidgets('Govee sector reports None when no captures', (tester) async {
    await _pumpExpanded(tester, _view(goveeCount: 0, goveeSync: 'none'));

    expect(find.text('Govee Readings'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });
}
