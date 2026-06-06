import '../providers/scope_comparison_provider.dart';
import 'scope_config.dart';
import 'scope_models.dart';

/// One named "audit item" rolled up under a station header. An item maps to a
/// curated subset of a sector's columns (empty `columns` = the whole sector).
/// Used to show, at a glance, which checks have actually been recorded.
class StationItem {
  final String label;
  final String sectorId;

  /// Sector column names this item covers. Empty → every param of the sector.
  final List<String> columns;

  const StationItem({
    required this.label,
    required this.sectorId,
    this.columns = const [],
  });
}

/// Item taxonomy per station (finer than sectors). Order is display order.
const Map<String, List<StationItem>> _byStation = {
  ScopeConfigRegistry.stationStorage: [
    StationItem(
      label: 'EST',
      sectorId: 'egg_storage',
      columns: ['estAvg', 'estCvPct', 'shellTemp'],
    ),
    StationItem(
      label: 'Upside score',
      sectorId: 'egg_storage',
      columns: ['upsideDownPct'],
    ),
    StationItem(
      label: 'Storage checklist',
      sectorId: 'egg_storage',
      columns: [
        'storagePeriodDays',
        'turningTimes',
        'traySpacing',
        'coolerProximity',
        'condensationPresent',
      ],
    ),
    StationItem(
      label: 'Egg quality',
      sectorId: 'egg_quality',
      columns: ['eggSampleSize', 'eggAvgWeight', 'eggUniformityPct', 'eggCvPct'],
    ),
    StationItem(
      label: 'Shell UV',
      sectorId: 'egg_quality',
      columns: [
        'uvAffectedPct',
        'uvCuticleDamagePct',
        'uvWashedPct',
        'uvDirtyPct',
      ],
    ),
  ],
  ScopeConfigRegistry.stationChicks: [
    StationItem(
      label: 'Pasgar',
      sectorId: 'chick_quality',
      columns: [
        'pasgarFinalScore',
        'pasgarReflexesPct',
        'pasgarBeakPct',
        'pasgarNavelPct',
        'pasgarBellyPct',
        'pasgarLegPct',
        'pasgarFeatherDevPct',
      ],
    ),
    StationItem(
      label: 'CVT',
      sectorId: 'chick_quality',
      columns: ['cvtAvgTemp', 'cvtCvPct'],
    ),
    StationItem(
      label: 'YFBM',
      sectorId: 'chick_quality',
      columns: ['yfbmAvgPct'],
    ),
    StationItem(label: 'Chick weights', sectorId: 'chick_weights'),
  ],
  ScopeConfigRegistry.stationHatch: [
    StationItem(
      label: 'Hatch result',
      sectorId: 'hatch_results',
      columns: ['hatchabilityPct', 'fertilityPct', 'hofPct'],
    ),
    StationItem(label: 'Fresh breakout', sectorId: 'fresh_egg_breakout'),
    StationItem(label: 'Candled breakout', sectorId: 'candled_egg_breakout'),
    StationItem(label: 'Residue breakout', sectorId: 'residue_breakout'),
  ],
  ScopeConfigRegistry.stationSetters: [
    StationItem(
      label: 'Setpoint vs actual',
      sectorId: 'setter_optimizing',
      columns: ['setpointF', 'actualF', 'setpointRh', 'actualRh'],
    ),
    StationItem(
      label: 'EST',
      sectorId: 'setter_optimizing',
      columns: ['estAvg', 'estCvPct'],
    ),
    StationItem(
      label: 'CO₂ / turning',
      sectorId: 'setter_optimizing',
      columns: ['co2Ppm', 'turningAngle'],
    ),
  ],
  ScopeConfigRegistry.stationHatchers: [
    StationItem(
      label: 'Setpoint',
      sectorId: 'hatcher_optimizing',
      columns: ['setpointF', 'setpointRh'],
    ),
    StationItem(
      label: 'CVT',
      sectorId: 'hatcher_optimizing',
      columns: ['cvtAvg', 'cvtCvPct'],
    ),
    StationItem(
      label: 'CO₂',
      sectorId: 'hatcher_optimizing',
      columns: ['co2Ppm'],
    ),
    StationItem(
      label: 'Transfer',
      sectorId: 'hatcher_optimizing',
      columns: ['transferDay', 'chickPanting', 'meconium'],
    ),
  ],
};

List<StationItem> stationItems(String station) => _byStation[station] ?? const [];

/// Labels of the station's items that have at least one real recorded value for
/// the current filter. Example/empty sectors never count as done.
List<String> completedItemsFor(ScopeComparisonProvider provider, String station) {
  final out = <String>[];
  for (final item in stationItems(station)) {
    if (provider.isDummyFor(item.sectorId) ||
        provider.isEmptyFor(item.sectorId)) {
      continue;
    }
    final groups = provider.groupsFor(item.sectorId);
    if (groups.isEmpty) continue;
    final sector = ScopeConfigRegistry.byId(item.sectorId);

    final indexes = item.columns.isEmpty
        ? [for (var i = 0; i < sector.params.length; i++) i]
        : [
            for (final col in item.columns)
              sector.params.indexWhere((p) => p.column == col),
          ].where((i) => i >= 0).toList();

    if (_anyRecorded(groups, sector, indexes)) out.add(item.label);
  }
  return out;
}

bool _anyRecorded(
  List<ScopeGroup> groups,
  ScopeSectorConfig sector,
  List<int> indexes,
) {
  for (final group in groups) {
    final cells = group.cells;
    for (final i in indexes) {
      if (i >= cells.length) continue;
      final cell = cells[i];
      final isText = sector.params[i].format == ScopeValueFormat.text;
      final recorded = isText
          ? (cell.text.trim().isNotEmpty && cell.text.trim() != '—')
          : cell.value != null;
      if (recorded) return true;
    }
  }
  return false;
}
