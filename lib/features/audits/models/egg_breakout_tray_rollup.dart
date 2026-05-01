import 'dart:convert';

import 'egg_breakout_sample.dart';

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
      for (final entry in decoded.asMap().entries) {
        final item = entry.value;
        if (item is! Map) continue;
        final sample = EggBreakoutSampleEntry.fromJson(
          Map<String, dynamic>.from(item),
          index: entry.key + 1,
        );
        final counts = sample.counts;
        rollup = rollup._add(
          traySize: sample.totalSample ?? 0,
          infertile: _readCount(counts, 'infertile'),
          earlyDead:
              _readCount(counts, 'earlyDead') +
              _readCount(counts, 'early24h') +
              _readCount(counts, 'early48h') +
              _readCount(counts, 'early72hBloodRing'),
          midDead:
              _readCount(counts, 'midDead') + _readCount(counts, 'blackEye'),
          lateDead: _readCount(counts, 'lateDead'),
          internalPip: _readCount(counts, 'internalPip'),
          externalPip: _readCount(counts, 'externalPip'),
          cracked: _readCount(counts, 'cracked'),
          contaminated: _readCount(counts, 'contaminated'),
          malposition: _readCount(counts, 'malposition'),
          exposedBrain: _readCount(counts, 'exposedBrain'),
          crossedBeak: _readCount(counts, 'crossedBeak'),
          culledDead: _readCount(counts, 'culledDead'),
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

  static int _readCount(Map<String, int> counts, String key) =>
      counts[key] ?? 0;
}
