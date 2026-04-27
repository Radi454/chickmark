import 'dart:convert';

class EggBreakoutTrayRollup {
  final int traySize;
  final int infertile;
  final int earlyDead;
  final int midDead;
  final int lateDead;
  final int internalPip;
  final int externalPip;
  final int cracked;
  final int contaminated;
  final int malposition;
  final int exposedBrain;
  final int crossedBeak;
  final int culledDead;

  const EggBreakoutTrayRollup({
    this.traySize = 0,
    this.infertile = 0,
    this.earlyDead = 0,
    this.midDead = 0,
    this.lateDead = 0,
    this.internalPip = 0,
    this.externalPip = 0,
    this.cracked = 0,
    this.contaminated = 0,
    this.malposition = 0,
    this.exposedBrain = 0,
    this.crossedBeak = 0,
    this.culledDead = 0,
  });

  factory EggBreakoutTrayRollup.fromJson(String? source) {
    if (source == null || source.trim().isEmpty) {
      return const EggBreakoutTrayRollup();
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const EggBreakoutTrayRollup();

      var rollup = const EggBreakoutTrayRollup();
      for (final item in decoded) {
        if (item is! Map) continue;
        final counts = item['counts'];
        if (counts is! Map) continue;
        rollup = rollup._add(
          traySize: _readInt(item['traySize']),
          infertile: _readInt(counts['infertile']),
          earlyDead: _readInt(counts['earlyDead']),
          midDead: _readInt(counts['midDead']),
          lateDead: _readInt(counts['lateDead']),
          internalPip: _readInt(counts['internalPip']),
          externalPip: _readInt(counts['externalPip']),
          cracked: _readInt(counts['cracked']),
          contaminated: _readInt(counts['contaminated']),
          malposition: _readInt(counts['malposition']),
          exposedBrain: _readInt(counts['exposedBrain']),
          crossedBeak: _readInt(counts['crossedBeak']),
          culledDead: _readInt(counts['culledDead']),
        );
      }
      return rollup;
    } catch (_) {
      return const EggBreakoutTrayRollup();
    }
  }

  EggBreakoutTrayRollup _add({
    int traySize = 0,
    int infertile = 0,
    int earlyDead = 0,
    int midDead = 0,
    int lateDead = 0,
    int internalPip = 0,
    int externalPip = 0,
    int cracked = 0,
    int contaminated = 0,
    int malposition = 0,
    int exposedBrain = 0,
    int crossedBeak = 0,
    int culledDead = 0,
  }) {
    return EggBreakoutTrayRollup(
      traySize: this.traySize + traySize,
      infertile: this.infertile + infertile,
      earlyDead: this.earlyDead + earlyDead,
      midDead: this.midDead + midDead,
      lateDead: this.lateDead + lateDead,
      internalPip: this.internalPip + internalPip,
      externalPip: this.externalPip + externalPip,
      cracked: this.cracked + cracked,
      contaminated: this.contaminated + contaminated,
      malposition: this.malposition + malposition,
      exposedBrain: this.exposedBrain + exposedBrain,
      crossedBeak: this.crossedBeak + crossedBeak,
      culledDead: this.culledDead + culledDead,
    );
  }

  Map<String, int> toAuditFields() {
    return {
      'ebTraySize': traySize,
      'ebInfertileCount': infertile,
      'ebEarlyDeadCount': earlyDead,
      'ebMidDeadCount': midDead,
      'ebLateDeadCount': lateDead,
      'ebInternalPipCount': internalPip,
      'ebExternalPipCount': externalPip,
      'ebCrackedCount': cracked,
      'ebContaminatedCount': contaminated,
      'ebMalpositionCount': malposition,
      'ebExposedBrainCount': exposedBrain,
      'ebCrossedBeakCount': crossedBeak,
      'ebCulledDeadCount': culledDead,
    };
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
