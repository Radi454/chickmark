import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_sector_widget.dart';
import 'package:provider/provider.dart';

class _EmptyScopeRepo extends ScopeComparisonRepository {
  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(sector, filter) async => const [];
}

void main() {
  Future<void> pumpResidue(WidgetTester tester) async {
    final provider = ScopeComparisonProvider(repository: _EmptyScopeRepo());
    await provider.applyFilter();
    await tester.pumpWidget(
      ChangeNotifierProvider<ScopeComparisonProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScopeSectorWidget(sectorId: 'residue_breakout'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('residue renders all 16 leaf columns by default', (tester) async {
    await pumpResidue(tester);
    expect(find.text('H1·S1H1·Tr1·Ty1'), findsWidgets);
    expect(find.text('H2·S2H2·Tr2·Ty2'), findsWidgets);
    expect(find.text('⌀ Avg'), findsWidgets); // pick-chip + header
    expect(find.text('Example data'), findsOneWidget);
  });

  testWidgets('toggling Tray off broadens columns to trolley level', (
    tester,
  ) async {
    await pumpResidue(tester);
    expect(find.text('H1·S1H1·Tr1·Ty1'), findsWidgets);

    await tester.tap(find.text('Tray'));
    await tester.pumpAndSettle();

    expect(find.text('H1·S1H1·Tr1·Ty1'), findsNothing);
    expect(find.text('H1·S1H1·Tr1'), findsWidgets); // trolley-level column header
  });
}
