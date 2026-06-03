import 'dart:convert';

import '../../../core/utils/bmk_age_calculator.dart';
import '../../../core/utils/calculation_utils.dart';

enum EggBreakoutType {
  freshEggBreakout('freshEggBreakout', 'Fresh Egg'),
  candledEggBreakout('candledEggBreakout', 'Candled Egg'),
  residueHatchDay('residueHatchDay', 'Residue / Hatch Day');

  const EggBreakoutType(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  bool get showsHatchability => this == EggBreakoutType.residueHatchDay;

  List<EggBreakoutCountField> get countFields {
    return switch (this) {
      EggBreakoutType.freshEggBreakout => freshCountFields,
      EggBreakoutType.candledEggBreakout => candledCountFields,
      EggBreakoutType.residueHatchDay => residueCountFields,
    };
  }

  int? calculateBmkAgeDays({
    required int? currentFlockAgeDays,
    required int? storageDays,
    int? candlingDay,
  }) {
    if (currentFlockAgeDays == null) return null;
    final effectiveStorageDays = storageDays ?? 0;
    if (effectiveStorageDays < 0) return null;
    final extraDays = switch (this) {
      EggBreakoutType.freshEggBreakout => 0,
      EggBreakoutType.candledEggBreakout => candlingDay ?? 10,
      EggBreakoutType.residueHatchDay => 21,
    };
    if (extraDays < 0) return null;
    return BmkAgeCalculator.calculateDaysFromFlockAge(
      currentFlockAgeDays: currentFlockAgeDays,
      storageDays: effectiveStorageDays,
      incubationOffsetDays: extraDays,
    );
  }

  static EggBreakoutType fromStorageValue(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return EggBreakoutType.residueHatchDay;
    }
    if (normalized == 'fresheggbreakout' ||
        normalized == 'fresh_egg_breakout' ||
        normalized == 'fresh' ||
        normalized.contains('fresh')) {
      return EggBreakoutType.freshEggBreakout;
    }
    if (normalized == 'candledeggbreakout' ||
        normalized == 'candled_egg_breakout' ||
        normalized == 'candled_10d' ||
        normalized == 'candled' ||
        normalized.contains('candled') ||
        normalized.contains('10d')) {
      return EggBreakoutType.candledEggBreakout;
    }
    if (normalized == 'residuehatchday' ||
        normalized == 'residue_hatch_day' ||
        normalized == 'residue_21d' ||
        normalized == 'residue' ||
        normalized.contains('residue') ||
        normalized.contains('hatch')) {
      return EggBreakoutType.residueHatchDay;
    }
    return EggBreakoutType.residueHatchDay;
  }
}

enum EggBreakoutSampleMode {
  tray('tray', 'Tray sample'),
  pool('pool', 'Pool sample');

  const EggBreakoutSampleMode(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  static EggBreakoutSampleMode fromStorageValue(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == EggBreakoutSampleMode.pool.storageValue ||
        normalized == 'pooled') {
      return EggBreakoutSampleMode.pool;
    }
    return EggBreakoutSampleMode.tray;
  }
}

class EggBreakoutCountField {
  final String label;
  final String key;

  const EggBreakoutCountField(this.label, this.key);
}

const List<EggBreakoutCountField> freshCountFields = [
  EggBreakoutCountField('Infertile', 'infertile'),
  EggBreakoutCountField('24 hours', 'early24h'),
  EggBreakoutCountField('48 hours', 'early48h'),
  EggBreakoutCountField('Blood Ring', 'early72hBloodRing'),
];

const List<EggBreakoutCountField> candledCountFields = [
  ...freshCountFields,
  EggBreakoutCountField('Black Eye', 'blackEye'),
];

const List<EggBreakoutCountField> residueCountFields = [
  EggBreakoutCountField('Infertile', 'infertile'),
  EggBreakoutCountField('Early Dead', 'earlyDead'),
  EggBreakoutCountField('Mid Dead', 'midDead'),
  EggBreakoutCountField('Late Dead', 'lateDead'),
  EggBreakoutCountField('External Pip', 'externalPip'),
  EggBreakoutCountField('Cracked', 'cracked'),
  EggBreakoutCountField('Contaminated', 'contaminated'),
];

class EggBreakoutSampleEntry {
  final String id;
  final EggBreakoutSampleMode sampleMode;
  final String label;
  final String? house;
  final String? setter;
  final String? hatcher;
  final String? trolley;
  final String? tray;
  final String? position;
  final int? traySize;
  final int? numberOfTrays;
  final EggBreakoutType breakoutType;
  final Map<String, int> counts;

  const EggBreakoutSampleEntry({
    required this.id,
    required this.sampleMode,
    required this.label,
    this.house,
    this.setter,
    this.hatcher,
    this.trolley,
    this.tray,
    this.position,
    this.traySize,
    this.numberOfTrays,
    this.breakoutType = EggBreakoutType.residueHatchDay,
    this.counts = const {},
  });

  factory EggBreakoutSampleEntry.tray({
    required String id,
    required String label,
    String? house,
    String? setter,
    String? hatcher,
    String? trolley,
    String? tray,
    String? position,
    int? traySize = 150,
    EggBreakoutType breakoutType = EggBreakoutType.residueHatchDay,
    Map<String, int> counts = const {},
  }) {
    return EggBreakoutSampleEntry(
      id: id,
      sampleMode: EggBreakoutSampleMode.tray,
      label: label,
      house: house,
      setter: setter,
      hatcher: hatcher,
      trolley: trolley,
      tray: tray ?? label,
      position: position,
      traySize: traySize,
      breakoutType: breakoutType,
      counts: counts,
    );
  }

  factory EggBreakoutSampleEntry.pool({
    required String id,
    required String label,
    String? house,
    String? setter,
    String? hatcher,
    String? trolley,
    String? tray,
    int? numberOfTrays = 1,
    int? traySize = 150,
    EggBreakoutType breakoutType = EggBreakoutType.residueHatchDay,
    Map<String, int> counts = const {},
  }) {
    return EggBreakoutSampleEntry(
      id: id,
      sampleMode: EggBreakoutSampleMode.pool,
      label: label,
      house: house,
      setter: setter,
      hatcher: hatcher,
      trolley: trolley,
      tray: tray,
      numberOfTrays: numberOfTrays,
      traySize: traySize,
      breakoutType: breakoutType,
      counts: counts,
    );
  }

  factory EggBreakoutSampleEntry.fromJson(
    Map<String, dynamic> json, {
    required int index,
    EggBreakoutType? fallbackBreakoutType,
  }) {
    final mode = EggBreakoutSampleMode.fromStorageValue(
      json['sampleMode'] as String?,
    );
    final rawBreakoutType = json['breakoutType'] as String?;
    final type = rawBreakoutType == null
        ? fallbackBreakoutType ?? EggBreakoutType.fromStorageValue(null)
        : EggBreakoutType.fromStorageValue(rawBreakoutType);
    final label = (json['label'] as String?)?.trim();
    final counts = _normalizeCountsForType(type, _readCounts(json['counts']));
    return EggBreakoutSampleEntry(
      id: (json['id'] as String?) ?? 'sample-$index',
      sampleMode: mode,
      label: label?.isNotEmpty == true
          ? label!
          : mode == EggBreakoutSampleMode.tray
          ? 'Tray $index'
          : 'Pool $index',
      house: _readText(json['house']),
      setter: _readText(json['setter']),
      hatcher: _readText(json['hatcher']),
      trolley: _readText(json['trolley']),
      tray:
          _readText(json['tray']) ??
          (mode == EggBreakoutSampleMode.tray ? label : null),
      position: json['position'] as String?,
      traySize: _readNullableInt(json['traySize']) ?? 150,
      numberOfTrays: _readNullableInt(json['numberOfTrays']) ?? 1,
      breakoutType: type,
      counts: counts,
    );
  }

  int? get totalSample {
    final size = traySize;
    if (size == null || size <= 0) return null;
    if (sampleMode == EggBreakoutSampleMode.tray) return size;
    final trays = numberOfTrays;
    if (trays == null || trays <= 0) return null;
    return size * trays;
  }

  double? percentageFor(String countKey) {
    final total = totalSample;
    if (total == null || total <= 0) return null;
    return CalculationUtils.percentOf(counts[countKey] ?? 0, total);
  }

  EggBreakoutSampleEntry copyWith({
    String? id,
    EggBreakoutSampleMode? sampleMode,
    String? label,
    String? house,
    String? setter,
    String? hatcher,
    String? trolley,
    String? tray,
    String? position,
    int? traySize,
    int? numberOfTrays,
    EggBreakoutType? breakoutType,
    Map<String, int>? counts,
  }) {
    return EggBreakoutSampleEntry(
      id: id ?? this.id,
      sampleMode: sampleMode ?? this.sampleMode,
      label: label ?? this.label,
      house: house ?? this.house,
      setter: setter ?? this.setter,
      hatcher: hatcher ?? this.hatcher,
      trolley: trolley ?? this.trolley,
      tray: tray ?? this.tray,
      position: position ?? this.position,
      traySize: traySize ?? this.traySize,
      numberOfTrays: numberOfTrays ?? this.numberOfTrays,
      breakoutType: breakoutType ?? this.breakoutType,
      counts: counts ?? this.counts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sampleMode': sampleMode.storageValue,
      'label': label,
      if (house != null) 'house': house,
      if (setter != null) 'setter': setter,
      if (hatcher != null) 'hatcher': hatcher,
      if (trolley != null) 'trolley': trolley,
      if (tray != null) 'tray': tray,
      if (position != null) 'position': position,
      'traySize': traySize,
      if (sampleMode == EggBreakoutSampleMode.pool)
        'numberOfTrays': numberOfTrays,
      'breakoutType': breakoutType.storageValue,
      'counts': counts,
    };
  }

  static List<EggBreakoutSampleEntry> decodeList(
    String? source, {
    EggBreakoutType? fallbackBreakoutType,
  }) {
    if (source == null || source.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .toList()
          .asMap()
          .entries
          .map(
            (entry) => EggBreakoutSampleEntry.fromJson(
              Map<String, dynamic>.from(entry.value),
              index: entry.key + 1,
              fallbackBreakoutType: fallbackBreakoutType,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<EggBreakoutSampleEntry> samples) {
    return jsonEncode(samples.map((sample) => sample.toJson()).toList());
  }

  static Map<String, int> _readCounts(Object? raw) {
    if (raw is! Map) return {};
    return Map<String, int>.fromEntries(
      raw.entries.expand((entry) {
        final count = _readNullableInt(entry.value);
        if (count == null || count <= 0) return const <MapEntry<String, int>>[];
        return [MapEntry(entry.key.toString(), count)];
      }),
    );
  }

  static Map<String, int> _normalizeCountsForType(
    EggBreakoutType type,
    Map<String, int> counts,
  ) {
    if (type != EggBreakoutType.residueHatchDay) return counts;
    final normalized = Map<String, int>.from(counts);
    if (normalized.containsKey('earlyDead')) return normalized;
    final legacyEarlyDead =
        (counts['early24h'] ?? 0) +
        (counts['early48h'] ?? 0) +
        (counts['early72hBloodRing'] ?? 0);
    if (legacyEarlyDead > 0) normalized['earlyDead'] = legacyEarlyDead;
    return normalized;
  }

  static int? _readNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _readText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
