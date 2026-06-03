class AuditTypeLabels {
  static const String eggAuditType = 'Egg';
  static const String eggStationKey = 'egg';
  static const String eggStationLabel = 'Egg';

  static String forAuditType(String auditType) {
    if (auditType == eggAuditType ||
        auditType == eggStationKey ||
        auditType == 'Egg' ||
        auditType == 'Egg Storage' ||
        auditType == 'Egg Storage & Handling') {
      return eggStationLabel;
    }
    return switch (auditType) {
      'Chick Quality' => 'Chicks',
      'Hatch Analysis' => 'Hatch Analysis & Egg Breakouts',
      'Setter Optimizing' => 'Setters',
      'Hatcher Optimizing' => 'Hatchers',
      _ => auditType,
    };
  }

  static String forStationKey(String stationKey) {
    switch (stationKey) {
      case eggStationKey:
      case 'egg_storage':
        return eggStationLabel;
      case 'chicks':
      case 'chick_quality':
        return 'Chicks';
      case 'hatch_analysis_egg_breakouts':
      case 'hatch_analysis':
        return 'Hatch Analysis & Egg Breakouts';
      case 'setters':
      case 'setter_optimizing':
        return 'Setters';
      case 'hatchers':
      case 'hatcher_optimizing':
        return 'Hatchers';
      default:
        return stationKey;
    }
  }
}
