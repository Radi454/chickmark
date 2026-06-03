class BmkEggBreakoutModel {
  final String id;
  final int ageWeek;
  final double infertilePct;
  final double early24hPct;
  final double early48hPct;
  final double bloodRingPct;
  final double blackEyePct;
  final double earlyDeadPct;
  final double midDeadPct;
  final double lateDeadPct;
  final double externalPipPct;
  final double crackedPct;
  final double contamPct;

  BmkEggBreakoutModel({
    required this.id,
    required this.ageWeek,
    this.infertilePct = 0.0,
    this.early24hPct = 0.0,
    this.early48hPct = 0.0,
    this.bloodRingPct = 0.0,
    this.blackEyePct = 0.0,
    this.earlyDeadPct = 0.0,
    this.midDeadPct = 0.0,
    this.lateDeadPct = 0.0,
    this.externalPipPct = 0.0,
    this.crackedPct = 0.0,
    this.contamPct = 0.0,
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
      earlyDeadPct: map['earlyDeadPct']?.toDouble() ?? 0.0,
      midDeadPct: map['midDeadPct']?.toDouble() ?? 0.0,
      lateDeadPct: map['lateDeadPct']?.toDouble() ?? 0.0,
      externalPipPct:
          map['externalPipPct']?.toDouble() ??
          map['pippedExternalPct']?.toDouble() ??
          0.0,
      crackedPct: map['crackedPct']?.toDouble() ?? 0.0,
      contamPct: map['contamPct']?.toDouble() ?? 0.0,
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
      'earlyDeadPct': earlyDeadPct,
      'midDeadPct': midDeadPct,
      'lateDeadPct': lateDeadPct,
      'externalPipPct': externalPipPct,
      'crackedPct': crackedPct,
      'contamPct': contamPct,
    };
  }
}
