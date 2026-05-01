import 'dart:convert';

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
    if (currentFlockAgeDays == null || storageDays == null) return null;
    if (storageDays < 0) return null;
    final extraDays = switch (this) {
      EggBreakoutType.freshEggBreakout => 0,
      EggBreakoutType.candledEggBreakout => candlingDay ?? 10,
      EggBreakoutType.residueHatchDay => 21,
    };
    if (extraDays < 0) return null;
    final ageDays = currentFlockAgeDays - storageDays - extraDays;
    return ageDays < 0 ? 0 : ageDays;
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
  EggBreakoutCountField('Early 24h', 'early24h'),
  EggBreakoutCountField('Early 48h', 'early48h'),
  EggBreakoutCountField('Early 72h / Blood ring', 'early72hBloodRing'),
];

const List<EggBreakoutCountField> candledCountFields = [
  ...freshCountFields,
  EggBreakoutCountField('Black eye', 'blackEye'),
  EggBreakoutCountField('Mid dead', 'midDead'),
];

const List<EggBreakoutCountField> residueCountFields = [
  ...candledCountFields,
  EggBreakoutCountField('Late dead', 'lateDead'),
  EggBreakoutCountField('Internal pip', 'internalPip'),
  EggBreakoutCountField('External pip', 'externalPip'),
  EggBreakoutCountField('Cracked', 'cracked'),
  EggBreakoutCountField('Contaminated', 'contaminated'),
  EggBreakoutCountField('Malposition', 'malposition'),
  EggBreakoutCountField('Exposed brain', 'exposedBrain'),
  EggBreakoutCountField('Crossed beak', 'crossedBeak'),
  EggBreakoutCountField('Culled/Dead', 'culledDead'),
];

class EggBreakoutSampleEntry {
  final String id;
  final EggBreakoutSampleMode sampleMode;
  final String label;
  final String? position;
  final int? traySize;
  final int? numberOfTrays;
  final EggBreakoutType breakoutType;
  final Map<String, int> counts;

  const EggBreakoutSampleEntry({
    required this.id,
    required this.sampleMode,
    required this.label,
    this.position,
    this.traySize,
    this.numberOfTrays,
    this.breakoutType = EggBreakoutType.residueHatchDay,
    this.counts = const {},
  });

  factory EggBreakoutSampleEntry.tray({
    required String id,
    required String label,
    String? position,
    int? traySize = 150,
    EggBreakoutType breakoutType = EggBreakoutType.residueHatchDay,
    Map<String, int> counts = const {},
  }) {
    return EggBreakoutSampleEntry(
      id: id,
      sampleMode: EggBreakoutSampleMode.tray,
      label: label,
      position: position,
      traySize: traySize,
      breakoutType: breakoutType,
      counts: counts,
    );
  }

  factory EggBreakoutSampleEntry.pool({
    required String id,
    required String label,
    int? numberOfTrays = 1,
    int? traySize = 150,
    EggBreakoutType breakoutType = EggBreakoutType.residueHatchDay,
    Map<String, int> counts = const {},
  }) {
    return EggBreakoutSampleEntry(
      id: id,
      sampleMode: EggBreakoutSampleMode.pool,
      label: label,
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
    final type = EggBreakoutType.fromStorageValue(
      json['breakoutType'] as String?,
    );
    final label = (json['label'] as String?)?.trim();
    return EggBreakoutSampleEntry(
      id: (json['id'] as String?) ?? 'sample-$index',
      sampleMode: mode,
      label: label?.isNotEmpty == true
          ? label!
          : mode == EggBreakoutSampleMode.tray
          ? 'Tray $index'
          : 'Pool $index',
      position: json['position'] as String?,
      traySize: _readNullableInt(json['traySize']) ?? 150,
      numberOfTrays: _readNullableInt(json['numberOfTrays']) ?? 1,
      breakoutType: fallbackBreakoutType ?? type,
      counts: _readCounts(json['counts']),
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
    return ((counts[countKey] ?? 0) / total) * 100;
  }

  EggBreakoutSampleEntry copyWith({
    String? id,
    EggBreakoutSampleMode? sampleMode,
    String? label,
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
      raw.entries.map(
        (entry) =>
            MapEntry(entry.key.toString(), _readNullableInt(entry.value) ?? 0),
      ),
    );
  }

  static int? _readNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
