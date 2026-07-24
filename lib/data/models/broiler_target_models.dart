import 'poultry_hierarchy_models.dart';

class BroilerTargetProfile {
  const BroilerTargetProfile({
    required this.id,
    required this.brand,
    required this.breed,
    required this.sexProfile,
    required this.publicationVersion,
    required this.sourceTitle,
    required this.sourceUrl,
    this.featheringVariant,
    this.publicationDate,
    this.sourceFilePath,
    this.region,
    this.languageCode = 'en',
    this.activeFrom,
    this.activeTo,
    this.isOfficial = false,
    this.isActive = true,
    this.supersedesProfileId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  final String id;
  final String brand;
  final String breed;
  final String? featheringVariant;
  final FlockSexProfile sexProfile;
  final String publicationVersion;
  final DateTime? publicationDate;
  final String sourceTitle;
  final String sourceUrl;
  final String? sourceFilePath;
  final String? region;
  final String languageCode;
  final DateTime? activeFrom;
  final DateTime? activeTo;
  final bool isOfficial;
  final bool isActive;
  final String? supersedesProfileId;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory BroilerTargetProfile.fromMap(Map<String, Object?> map) {
    return BroilerTargetProfile(
      id: map['id']! as String,
      brand: map['brand']! as String,
      breed: map['breed']! as String,
      featheringVariant: map['featheringVariant'] as String?,
      sexProfile: FlockSexProfile.fromStorage(map['sexProfile']?.toString()),
      publicationVersion: map['publicationVersion']! as String,
      publicationDate: _date(map['publicationDate']),
      sourceTitle: map['sourceTitle']! as String,
      sourceUrl: map['sourceUrl']! as String,
      sourceFilePath: map['sourceFilePath'] as String?,
      region: map['region'] as String?,
      languageCode: map['languageCode']?.toString() ?? 'en',
      activeFrom: _date(map['activeFrom']),
      activeTo: _date(map['activeTo']),
      isOfficial: _bool(map['isOfficial']),
      isActive: _bool(map['isActive'], fallback: true),
      supersedesProfileId: map['supersedesProfileId'] as String?,
      createdBy: map['createdBy'] as String?,
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'pending',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'brand': brand,
      'breed': breed,
      'featheringVariant': featheringVariant,
      'sexProfile': sexProfile.storageKey,
      'publicationVersion': publicationVersion,
      'publicationDate': publicationDate?.toIso8601String(),
      'sourceTitle': sourceTitle,
      'sourceUrl': sourceUrl,
      'sourceFilePath': sourceFilePath,
      'region': region,
      'languageCode': languageCode,
      'activeFrom': activeFrom?.toIso8601String(),
      'activeTo': activeTo?.toIso8601String(),
      'isOfficial': isOfficial ? 1 : 0,
      'isActive': isActive ? 1 : 0,
      'supersedesProfileId': supersedesProfileId,
      'createdBy': createdBy,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
    };
  }

  BroilerTargetProfile copyWith({
    String? id,
    String? brand,
    String? breed,
    String? featheringVariant,
    FlockSexProfile? sexProfile,
    String? publicationVersion,
    DateTime? publicationDate,
    String? sourceTitle,
    String? sourceUrl,
    String? sourceFilePath,
    String? region,
    String? languageCode,
    DateTime? activeFrom,
    DateTime? activeTo,
    bool? isOfficial,
    bool? isActive,
    String? supersedesProfileId,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    DateTime? dirtyAt,
    DateTime? lastSyncedAt,
    String? syncError,
    bool clearActiveFrom = false,
    bool clearActiveTo = false,
  }) {
    return BroilerTargetProfile(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      breed: breed ?? this.breed,
      featheringVariant: featheringVariant ?? this.featheringVariant,
      sexProfile: sexProfile ?? this.sexProfile,
      publicationVersion: publicationVersion ?? this.publicationVersion,
      publicationDate: publicationDate ?? this.publicationDate,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceFilePath: sourceFilePath ?? this.sourceFilePath,
      region: region ?? this.region,
      languageCode: languageCode ?? this.languageCode,
      activeFrom: clearActiveFrom ? null : activeFrom ?? this.activeFrom,
      activeTo: clearActiveTo ? null : activeTo ?? this.activeTo,
      isOfficial: isOfficial ?? this.isOfficial,
      isActive: isActive ?? this.isActive,
      supersedesProfileId: supersedesProfileId ?? this.supersedesProfileId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: dirtyAt ?? this.dirtyAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncError: syncError ?? this.syncError,
    );
  }
}

class BroilerTargetRow {
  const BroilerTargetRow({
    required this.id,
    required this.profileId,
    required this.ageDay,
    this.bodyWeightG,
    this.dailyGainG,
    this.averageDailyGainG,
    this.dailyFeedIntakeGPerLivingBird,
    this.cumulativeFeedIntakeGPerLivingBird,
    this.fcr,
    this.waterMlPerLivingBird,
    this.metricMethodNotes,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) : assert(ageDay >= 0);

  final String id;
  final String profileId;
  final int ageDay;
  final double? bodyWeightG;
  final double? dailyGainG;
  final double? averageDailyGainG;
  final double? dailyFeedIntakeGPerLivingBird;
  final double? cumulativeFeedIntakeGPerLivingBird;
  final double? fcr;
  final double? waterMlPerLivingBird;
  final String? metricMethodNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  factory BroilerTargetRow.fromMap(Map<String, Object?> map) {
    return BroilerTargetRow(
      id: map['id']! as String,
      profileId: map['profileId']! as String,
      ageDay: _integer(map['ageDay']),
      bodyWeightG: _number(map['bodyWeightG']),
      dailyGainG: _number(map['dailyGainG']),
      averageDailyGainG: _number(map['averageDailyGainG']),
      dailyFeedIntakeGPerLivingBird: _number(
        map['dailyFeedIntakeGPerLivingBird'],
      ),
      cumulativeFeedIntakeGPerLivingBird: _number(
        map['cumulativeFeedIntakeGPerLivingBird'],
      ),
      fcr: _number(map['fcr']),
      waterMlPerLivingBird: _number(map['waterMlPerLivingBird']),
      metricMethodNotes: map['metricMethodNotes'] as String?,
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      syncStatus: map['syncStatus']?.toString() ?? 'pending',
      dirtyAt: _date(map['dirtyAt']),
      lastSyncedAt: _date(map['lastSyncedAt']),
      syncError: map['syncError'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'profileId': profileId,
      'ageDay': ageDay,
      'bodyWeightG': bodyWeightG,
      'dailyGainG': dailyGainG,
      'averageDailyGainG': averageDailyGainG,
      'dailyFeedIntakeGPerLivingBird': dailyFeedIntakeGPerLivingBird,
      'cumulativeFeedIntakeGPerLivingBird': cumulativeFeedIntakeGPerLivingBird,
      'fcr': fcr,
      'waterMlPerLivingBird': waterMlPerLivingBird,
      'metricMethodNotes': metricMethodNotes,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
    };
  }

  BroilerTargetRow copyWith({
    String? id,
    String? profileId,
    int? ageDay,
    double? bodyWeightG,
    double? dailyGainG,
    double? averageDailyGainG,
    double? dailyFeedIntakeGPerLivingBird,
    double? cumulativeFeedIntakeGPerLivingBird,
    double? fcr,
    double? waterMlPerLivingBird,
    String? metricMethodNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    DateTime? dirtyAt,
    DateTime? lastSyncedAt,
    String? syncError,
  }) {
    return BroilerTargetRow(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      ageDay: ageDay ?? this.ageDay,
      bodyWeightG: bodyWeightG ?? this.bodyWeightG,
      dailyGainG: dailyGainG ?? this.dailyGainG,
      averageDailyGainG: averageDailyGainG ?? this.averageDailyGainG,
      dailyFeedIntakeGPerLivingBird:
          dailyFeedIntakeGPerLivingBird ?? this.dailyFeedIntakeGPerLivingBird,
      cumulativeFeedIntakeGPerLivingBird:
          cumulativeFeedIntakeGPerLivingBird ??
          this.cumulativeFeedIntakeGPerLivingBird,
      fcr: fcr ?? this.fcr,
      waterMlPerLivingBird: waterMlPerLivingBird ?? this.waterMlPerLivingBird,
      metricMethodNotes: metricMethodNotes ?? this.metricMethodNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: dirtyAt ?? this.dirtyAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncError: syncError ?? this.syncError,
    );
  }
}

class BroilerTargetCatalogueEntry {
  const BroilerTargetCatalogueEntry({
    required this.profile,
    required this.rows,
  });

  final BroilerTargetProfile profile;
  final List<BroilerTargetRow> rows;
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

double? _number(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _integer(Object? value) {
  if (value is int) return value;
  return int.parse(value.toString());
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value == null) return fallback;
  return value == true || value == 1 || value.toString() == '1';
}
