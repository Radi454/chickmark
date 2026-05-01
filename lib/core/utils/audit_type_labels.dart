class AuditTypeLabels {
  static const String eggAuditType = 'Egg Storage';
  static const String eggStationKey = 'egg_storage';
  static const String eggStationLabel = 'Egg';

  static String forAuditType(String auditType) {
    if (auditType == eggAuditType ||
        auditType == eggStationKey ||
        auditType == 'Egg Storage & Handling') {
      return eggStationLabel;
    }
    return auditType;
  }

  static String forStationKey(String stationKey) {
    switch (stationKey) {
      case eggStationKey:
        return eggStationLabel;
      case 'chick_quality':
        return 'Chick Quality';
      case 'hatch_analysis':
        return 'Hatch Analysis';
      case 'setter_optimizing':
        return 'Setter Optimizing';
      case 'hatcher_optimizing':
        return 'Hatcher Optimizing';
      default:
        return stationKey;
    }
  }
}
