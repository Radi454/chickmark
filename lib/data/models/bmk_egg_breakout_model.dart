class BmkEggBreakoutModel {
  final String id;
  final int ageWeek;
  final double infertilePct;
  final double early24hPct;
  final double early48hPct;
  final double bloodRingPct;
  final double blackEyePct;
  final double midDeadPct;
  final double lateDeadPct;
  final double pippedInternalPct;
  final double pippedExternalPct;
  final double explodedPct;
  final double mushyPct;
  final double contamPct;
  final double cullPct;
  final double seeperPct;
  final double otherPct;
  final double feathersPct;
  final double turnedPct;
  final double exposedBrainPct;
  final double crossedBeakPct;
  final double crackedPct;
  final double earlyDeadPct;
  final double midBlackEyePct;
  final double internalPipPct;
  final double externalPipPct;

  BmkEggBreakoutModel({
    required this.id,
    required this.ageWeek,
    this.infertilePct = 0.0,
    this.early24hPct = 0.0,
    this.early48hPct = 0.0,
    this.bloodRingPct = 0.0,
    this.blackEyePct = 0.0,
    this.midDeadPct = 0.0,
    this.lateDeadPct = 0.0,
    this.pippedInternalPct = 0.0,
    this.pippedExternalPct = 0.0,
    this.explodedPct = 0.0,
    this.mushyPct = 0.0,
    this.contamPct = 0.0,
    this.cullPct = 0.0,
    this.seeperPct = 0.0,
    this.otherPct = 0.0,
    this.feathersPct = 0.0,
    this.turnedPct = 0.0,
    this.exposedBrainPct = 0.0,
    this.crossedBeakPct = 0.0,
    this.crackedPct = 0.0,
    this.earlyDeadPct = 0.0,
    this.midBlackEyePct = 0.0,
    this.internalPipPct = 0.0,
    this.externalPipPct = 0.0,
  });

  factory BmkEggBreakoutModel.fromMap(Map<String, dynamic> map) {
    return BmkEggBreakoutModel(
      id: map['id'],
      ageWeek: map['ageWeek'],
      infertilePct: map['infertilePct']?.toDouble() ?? 0.0,
      early24hPct: map['early24hPct']?.toDouble() ?? 0.0,
      early48hPct: map['early48hPct']?.toDouble() ?? 0.0,
      bloodRingPct: map['bloodRingPct']?.toDouble() ?? 0.0,
      blackEyePct: map['blackEyePct']?.toDouble() ?? 0.0,
      midDeadPct: map['midDeadPct']?.toDouble() ?? 0.0,
      lateDeadPct: map['lateDeadPct']?.toDouble() ?? 0.0,
      pippedInternalPct: map['pippedInternalPct']?.toDouble() ?? 0.0,
      pippedExternalPct: map['pippedExternalPct']?.toDouble() ?? 0.0,
      explodedPct: map['explodedPct']?.toDouble() ?? 0.0,
      mushyPct: map['mushyPct']?.toDouble() ?? 0.0,
      contamPct: map['contamPct']?.toDouble() ?? 0.0,
      cullPct: map['cullPct']?.toDouble() ?? 0.0,
      seeperPct: map['seeperPct']?.toDouble() ?? 0.0,
      otherPct: map['otherPct']?.toDouble() ?? 0.0,
      feathersPct: map['feathersPct']?.toDouble() ?? 0.0,
      turnedPct: map['turnedPct']?.toDouble() ?? 0.0,
      exposedBrainPct: map['exposedBrainPct']?.toDouble() ?? 0.0,
      crossedBeakPct: map['crossedBeakPct']?.toDouble() ?? 0.0,
      crackedPct: map['crackedPct']?.toDouble() ?? 0.0,
      earlyDeadPct:
          map['earlyDeadPct']?.toDouble() ??
          map['midDeadPct']?.toDouble() ??
          0.0,
      midBlackEyePct:
          map['midBlackEyePct']?.toDouble() ??
          map['blackEyePct']?.toDouble() ??
          0.0,
      internalPipPct:
          map['internalPipPct']?.toDouble() ??
          map['pippedInternalPct']?.toDouble() ??
          0.0,
      externalPipPct:
          map['externalPipPct']?.toDouble() ??
          map['pippedExternalPct']?.toDouble() ??
          0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ageWeek': ageWeek,
      'infertilePct': infertilePct,
      'early24hPct': early24hPct,
      'early48hPct': early48hPct,
      'bloodRingPct': bloodRingPct,
      'blackEyePct': blackEyePct,
      'midDeadPct': midDeadPct,
      'lateDeadPct': lateDeadPct,
      'pippedInternalPct': pippedInternalPct,
      'pippedExternalPct': pippedExternalPct,
      'explodedPct': explodedPct,
      'mushyPct': mushyPct,
      'contamPct': contamPct,
      'cullPct': cullPct,
      'seeperPct': seeperPct,
      'otherPct': otherPct,
      'feathersPct': feathersPct,
      'turnedPct': turnedPct,
      'exposedBrainPct': exposedBrainPct,
      'crossedBeakPct': crossedBeakPct,
      'crackedPct': crackedPct,
      'earlyDeadPct': earlyDeadPct,
      'midBlackEyePct': midBlackEyePct,
      'internalPipPct': internalPipPct,
      'externalPipPct': externalPipPct,
    };
  }
}
