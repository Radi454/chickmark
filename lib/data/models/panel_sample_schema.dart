enum SamplingLayer {
  pool('pool'),
  house('house'),
  setter('setter'),
  hatcher('hatcher'),
  setterHatcher('setter_hatcher'),
  trolley('trolley'),
  tray('tray');

  const SamplingLayer(this.dbValue);

  final String dbValue;

  static SamplingLayer fromDbValue(String value) {
    return SamplingLayer.values.firstWhere(
      (layer) => layer.dbValue == value,
      orElse: () => throw ArgumentError('Unknown sampling layer: $value'),
    );
  }
}

class PanelSampleDefinition {
  const PanelSampleDefinition({
    required this.tableName,
    required this.allowedLayers,
  });

  final String tableName;
  final List<SamplingLayer> allowedLayers;

  String get sampleTableName => '${tableName}_samples';
}

class PanelSampleSchema {
  const PanelSampleSchema._();

  static const panels = <PanelSampleDefinition>[
    PanelSampleDefinition(
      tableName: 'egg_storage',
      allowedLayers: [SamplingLayer.pool],
    ),
    PanelSampleDefinition(
      tableName: 'egg_quality',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.house],
    ),
    PanelSampleDefinition(
      tableName: 'egg_weights',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.house],
    ),
    PanelSampleDefinition(
      tableName: 'chick_pasgar',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher],
    ),
    PanelSampleDefinition(
      tableName: 'chick_weights',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.house],
    ),
    PanelSampleDefinition(
      tableName: 'chick_yfbm',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher],
    ),
    PanelSampleDefinition(
      tableName: 'chick_cvt',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher],
    ),
    PanelSampleDefinition(
      tableName: 'chick_pm',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.setterHatcher],
    ),
    PanelSampleDefinition(
      tableName: 'fresh_egg_breakout',
      allowedLayers: [SamplingLayer.pool, SamplingLayer.house],
    ),
    PanelSampleDefinition(
      tableName: 'candled_egg_breakout',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.house,
        SamplingLayer.setter,
        SamplingLayer.tray,
      ],
    ),
    PanelSampleDefinition(
      tableName: 'residue_breakout',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.house,
        SamplingLayer.setterHatcher,
        SamplingLayer.tray,
      ],
    ),
    PanelSampleDefinition(
      tableName: 'setter_optimizing',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.setter,
        SamplingLayer.trolley,
        SamplingLayer.tray,
      ],
    ),
    PanelSampleDefinition(
      tableName: 'hatcher_optimizing',
      allowedLayers: [
        SamplingLayer.pool,
        SamplingLayer.hatcher,
        SamplingLayer.trolley,
        SamplingLayer.tray,
      ],
    ),
  ];

  static PanelSampleDefinition byTable(String tableName) {
    return panels.firstWhere(
      (panel) => panel.tableName == tableName,
      orElse: () => throw ArgumentError('Unknown panel table: $tableName'),
    );
  }
}
