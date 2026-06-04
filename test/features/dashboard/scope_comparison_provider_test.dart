import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/data/repositories/scope_comparison_repository.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_config.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';

/// Returns no live rows → provider must fall back to dummy data for every sector.
class _EmptyScopeRepo extends ScopeComparisonRepository {
  @override
  Future<List<ScopeLeafRow>> getScopeLeaves(sector, filter) async => const [];
}

void main() {
  late ScopeComparisonProvider provider;

  setUp(() async {
    provider = ScopeComparisonProvider(repository: _EmptyScopeRepo());
    await provider.applyFilter(); // no bmkAge → no DB call for BMK
  });

  test('falls back to dummy data when no live rows', () {
    expect(provider.isDummyFor('residue_breakout'), isTrue);
    expect(provider.isDummyFor('egg_storage'), isTrue);
  });

  test('residue defaults to all layers on → 16 leaf columns + avg', () {
    expect(provider.groupsFor('residue_breakout'), hasLength(16));
    expect(provider.showAvg('residue_breakout'), isTrue);
    expect(provider.isAvgVisible('residue_breakout'), isTrue);
  });

  test('toggling all residue layers off collapses to Pool', () {
    for (final l in const [
      SamplingLayer.house,
      SamplingLayer.setterHatcher,
      SamplingLayer.trolley,
      SamplingLayer.tray,
    ]) {
      provider.toggleLayer('residue_breakout', l);
    }
    expect(
      provider.groupsFor('residue_breakout').map((g) => g.label),
      ['Pool'],
    );
    expect(provider.showAvg('residue_breakout'), isFalse);
  });

  test('House+Machine nests into 4 columns', () {
    // start all-on (16) → drop trolley + tray → House·Machine
    provider.toggleLayer('residue_breakout', SamplingLayer.trolley);
    provider.toggleLayer('residue_breakout', SamplingLayer.tray);
    expect(
      provider.groupsFor('residue_breakout').map((g) => g.label),
      ['H1·S1H1', 'H1·S2H2', 'H2·S1H1', 'H2·S2H2'],
    );
  });

  test('single-scope sector yields one pooled group', () {
    expect(provider.groupsFor('egg_storage'), hasLength(1));
    expect(provider.showAvg('egg_storage'), isFalse);
  });

  test('pick-chip hides a column', () {
    expect(provider.visibleColumnIndexes('chick_quality'), [0, 1]);
    provider.toggleColumn('chick_quality', 0);
    expect(provider.visibleColumnIndexes('chick_quality'), [1]);
  });

  test('demo BMK drives severity flags on dummy data', () {
    final groups = provider.groupsFor('residue_breakout');
    final anyFlagged =
        groups.any((g) => g.severity != ScopeSeverity.good && g.severity != ScopeSeverity.pool);
    expect(anyFlagged, isTrue);
  });

  test('all 11 sectors load', () {
    for (final s in ScopeConfigRegistry.sectors) {
      expect(provider.groupsFor(s.id), isNotEmpty, reason: s.id);
    }
  });
}
