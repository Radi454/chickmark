import 'dart:collection';
import 'dart:convert';

import '../../core/utils/calculation_utils.dart';
import '../agent/station_registry.dart';

enum AgentIntakeState {
  collecting('collecting'),
  awaitingClarification('awaiting_clarification'),
  paused('paused'),
  readyForSummary('ready_for_summary'),
  awaitingUserConfirmation('awaiting_user_confirmation'),
  awaitingAdminReview('awaiting_admin_review'),
  approved('approved'),
  rejected('rejected'),
  cancelled('cancelled');

  const AgentIntakeState(this.storageKey);

  final String storageKey;

  static AgentIntakeState fromStorage(Object? value) {
    return values.firstWhere(
      (state) => state.storageKey == value?.toString(),
      orElse: () => collecting,
    );
  }
}

enum AgentIntakeLanguage {
  english('en'),
  arabic('ar'),
  mixed('mixed');

  const AgentIntakeLanguage(this.storageKey);

  final String storageKey;

  static AgentIntakeLanguage fromStorage(Object? value) {
    return values.firstWhere(
      (language) => language.storageKey == value?.toString(),
      orElse: () => english,
    );
  }
}

enum AgentIntakeScope {
  pool('pool'),
  house('house'),
  setter('setter'),
  hatcher('hatcher'),
  setterHatcher('setter_hatcher'),
  trolley('trolley'),
  tray('tray');

  const AgentIntakeScope(this.storageKey);

  final String storageKey;

  static AgentIntakeScope? fromStorage(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    for (final scope in values) {
      if (scope.storageKey == text) return scope;
    }
    return null;
  }
}

enum AgentIntakeTurnDirection {
  inbound('inbound'),
  outbound('outbound');

  const AgentIntakeTurnDirection(this.storageKey);

  final String storageKey;

  static AgentIntakeTurnDirection fromStorage(Object? value) {
    return values.firstWhere(
      (direction) => direction.storageKey == value?.toString(),
      orElse: () => inbound,
    );
  }
}

class AgentIntakeSession {
  AgentIntakeSession({
    required this.id,
    required this.staffLinkId,
    required this.telegramChatId,
    required this.schemaKey,
    required this.schemaVersion,
    required this.state,
    required this.language,
    required this.auditDate,
    required Map<String, Object?> workingValues,
    required this.summaryVersion,
    required this.createdAt,
    required this.updatedAt,
    this.customerId,
    this.customerName,
    this.flockId,
    this.flockName,
    this.hatcheryId,
    this.hatcheryName,
    this.scope,
    this.setterIdentity,
    this.hatcherIdentity,
    this.pendingClarification,
    this.summary,
    this.userConfirmedAt,
    this.approvedSessionId,
    this.approvedPanelRowId,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  }) : workingValues = _immutableJsonMap(workingValues);

  final String id;
  final String staffLinkId;
  final String telegramChatId;
  final String schemaKey;
  final int schemaVersion;
  final AgentIntakeState state;
  final AgentIntakeLanguage language;
  final String? customerId;
  final String? customerName;
  final String? flockId;
  final String? flockName;
  final String? hatcheryId;
  final String? hatcheryName;
  final DateTime auditDate;
  final AgentIntakeScope? scope;
  final String? setterIdentity;
  final String? hatcherIdentity;
  final Map<String, Object?> workingValues;
  final Map<String, dynamic>? pendingClarification;
  final int summaryVersion;
  final AgentIntakeSummary? summary;
  final DateTime? userConfirmedAt;
  final String? approvedSessionId;
  final String? approvedPanelRowId;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AgentIntakeSession.fromMap(Map<String, Object?> map) {
    final schemaKey = _requiredText(map['schemaKey'], 'schemaKey');
    final schemaVersion = _integer(map['schemaVersion']) ?? 0;
    final workingValues = _jsonObject(map['workingValuesJson']) ?? const {};
    final snapshot = _jsonObject(map['summarySnapshotJson']);
    return AgentIntakeSession(
      id: _requiredText(map['id'], 'id'),
      staffLinkId: _requiredText(map['staffLinkId'], 'staffLinkId'),
      telegramChatId: _requiredText(map['telegramChatId'], 'telegramChatId'),
      schemaKey: schemaKey,
      schemaVersion: schemaVersion,
      state: AgentIntakeState.fromStorage(map['state']),
      language: AgentIntakeLanguage.fromStorage(map['language']),
      customerId: _text(map['customerId']),
      customerName: _text(map['customerName']),
      flockId: _text(map['flockId']),
      flockName: _text(map['flockName']),
      hatcheryId: _text(map['hatcheryId']),
      hatcheryName: _text(map['hatcheryName']),
      auditDate: _requiredDate(map['auditDate'], 'auditDate'),
      scope: AgentIntakeScope.fromStorage(map['scope']),
      setterIdentity: _text(map['setterIdentity']),
      hatcherIdentity: _text(map['hatcherIdentity']),
      workingValues: workingValues,
      pendingClarification: _immutableJsonObject(
        _jsonObject(map['pendingClarificationJson']),
      ),
      summaryVersion: _integer(map['summaryVersion']) ?? 0,
      summary: snapshot == null
          ? null
          : AgentIntakeSummary.fromSnapshot(
              snapshot,
              fallbackSchemaKey: schemaKey,
              fallbackSchemaVersion: schemaVersion,
            ),
      userConfirmedAt: _date(map['userConfirmedAt']),
      approvedSessionId: _text(map['approvedSessionId']),
      approvedPanelRowId: _text(map['approvedPanelRowId']),
      reviewedBy: _text(map['reviewedBy']),
      reviewedAt: _date(map['reviewedAt']),
      rejectionReason: _text(map['rejectionReason']),
      createdAt: _requiredDate(map['createdAt'], 'createdAt'),
      updatedAt: _requiredDate(map['updatedAt'], 'updatedAt'),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'staffLinkId': staffLinkId,
    'telegramChatId': telegramChatId,
    'schemaKey': schemaKey,
    'schemaVersion': schemaVersion,
    'state': state.storageKey,
    'language': language.storageKey,
    'customerId': customerId,
    'customerName': customerName,
    'flockId': flockId,
    'flockName': flockName,
    'hatcheryId': hatcheryId,
    'hatcheryName': hatcheryName,
    'auditDate': _dayText(auditDate),
    'scope': scope?.storageKey,
    'setterIdentity': setterIdentity,
    'hatcherIdentity': hatcherIdentity,
    'workingValuesJson': jsonEncode(workingValues),
    'pendingClarificationJson': pendingClarification == null
        ? null
        : jsonEncode(pendingClarification),
    'summaryVersion': summaryVersion,
    'summarySnapshotJson': summary == null
        ? null
        : jsonEncode(summary!.toSnapshot()),
    'userConfirmedAt': userConfirmedAt?.toUtc().toIso8601String(),
    'approvedSessionId': approvedSessionId,
    'approvedPanelRowId': approvedPanelRowId,
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt?.toUtc().toIso8601String(),
    'rejectionReason': rejectionReason,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class AgentIntakeValue {
  const AgentIntakeValue({
    required this.id,
    required this.intakeSessionId,
    required this.fieldKey,
    required this.value,
    required this.sourcePhrase,
    required this.confidence,
    required this.createdAt,
    required this.updatedAt,
    this.clarificationReason,
  });

  final String id;
  final String intakeSessionId;
  final String fieldKey;
  final Object? value;
  final String sourcePhrase;
  final double confidence;
  final String? clarificationReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  int? get intValue => _integer(value);

  factory AgentIntakeValue.fromMap(Map<String, Object?> map) {
    return AgentIntakeValue(
      id: _requiredText(map['id'], 'id'),
      intakeSessionId: _requiredText(map['intakeSessionId'], 'intakeSessionId'),
      fieldKey: _requiredText(map['fieldKey'], 'fieldKey'),
      value: _jsonValue(map['valueJson']),
      sourcePhrase: _requiredText(map['sourcePhrase'], 'sourcePhrase'),
      confidence: _number(map['confidence']) ?? 0,
      clarificationReason: _text(map['clarificationReason']),
      createdAt: _requiredDate(map['createdAt'], 'createdAt'),
      updatedAt: _requiredDate(map['updatedAt'], 'updatedAt'),
    );
  }
}

class AgentIntakeTurn {
  const AgentIntakeTurn({
    required this.id,
    required this.intakeSessionId,
    required this.direction,
    required this.text,
    required this.language,
    required this.createdAt,
    this.telegramUpdateId,
    this.telegramMessageId,
    this.intent,
    this.deliveryStatus,
    this.attachmentKind,
    this.attachmentFileName,
    this.attachmentMimeType,
    this.attachmentRemotePath,
  });

  final String id;
  final String intakeSessionId;
  final AgentIntakeTurnDirection direction;
  final String? telegramUpdateId;
  final String? telegramMessageId;
  final String text;
  final AgentIntakeLanguage language;
  final String? intent;
  final String? deliveryStatus;
  final String? attachmentKind;
  final String? attachmentFileName;
  final String? attachmentMimeType;
  final String? attachmentRemotePath;
  final DateTime createdAt;

  factory AgentIntakeTurn.fromMap(Map<String, Object?> map) {
    return AgentIntakeTurn(
      id: _requiredText(map['id'], 'id'),
      intakeSessionId: _requiredText(map['intakeSessionId'], 'intakeSessionId'),
      direction: AgentIntakeTurnDirection.fromStorage(map['direction']),
      telegramUpdateId: _text(map['telegramUpdateId']),
      telegramMessageId: _text(map['telegramMessageId']),
      text: _requiredText(map['text'], 'text'),
      language: AgentIntakeLanguage.fromStorage(map['language']),
      intent: _text(map['intent']),
      deliveryStatus: _text(map['deliveryStatus']),
      attachmentKind: _text(map['attachmentKind']),
      attachmentFileName: _text(map['attachmentFileName']),
      attachmentMimeType: _text(map['attachmentMimeType']),
      attachmentRemotePath: _text(map['attachmentRemotePath']),
      createdAt: _requiredDate(map['createdAt'], 'createdAt'),
    );
  }
}

class AgentIntakeSummary {
  AgentIntakeSummary({
    required this.version,
    required this.schemaKey,
    required this.schemaVersion,
    required Map<String, Object?> values,
    required Map<String, Object?> calculations,
    required this.generatedAt,
  }) : values = _immutableJsonMap(values),
       calculations = _immutableJsonMap(calculations);

  static const pasgarFieldKeys = <String>[
    'pasgarSampleSize',
    'pasgarReflexesCount',
    'pasgarBeakCount',
    'pasgarNavelCount',
    'pasgarBellyCount',
    'pasgarLegCount',
    'pasgarFeatherDevCount',
  ];

  final int version;
  final String schemaKey;
  final int schemaVersion;
  final Map<String, Object?> values;
  final Map<String, Object?> calculations;
  final DateTime generatedAt;

  int get sampleSize => _integer(values['pasgarSampleSize']) ?? 0;

  double get score {
    final stored = _number(calculations['pasgarScore']);
    if (stored != null) return stored;
    return CalculationUtils.pasgarScore(
      sampleSize,
      pasgarFieldKeys
          .skip(1)
          .take(CalculationUtils.pasgarScoredDefectCategoryCount)
          .map((key) => _integer(values[key]) ?? 0)
          .toList(growable: false),
    );
  }

  double? percentageFor(String fieldKey) {
    final calculationKey = switch (fieldKey) {
      'pasgarReflexesCount' => 'pasgarReflexPct',
      'pasgarBeakCount' => 'pasgarBeakPct',
      'pasgarNavelCount' => 'pasgarNavelPct',
      'pasgarBellyCount' => 'pasgarBellyPct',
      'pasgarLegCount' => 'pasgarLegPct',
      'pasgarFeatherDevCount' => 'pasgarFeatherDevPct',
      _ => null,
    };
    final stored = calculationKey == null
        ? null
        : _number(calculations[calculationKey]);
    return stored ??
        CalculationUtils.percentOf(_integer(values[fieldKey]), sampleSize);
  }

  factory AgentIntakeSummary.fromSnapshot(
    Map<String, dynamic> snapshot, {
    required String fallbackSchemaKey,
    required int fallbackSchemaVersion,
  }) {
    final values = _jsonObject(snapshot['values']) ?? const {};
    final calculations =
        _jsonObject(snapshot['calculations']) ??
        _legacyPasgarCalculations(fallbackSchemaKey, values);
    return AgentIntakeSummary(
      version: _integer(snapshot['version']) ?? 0,
      schemaKey: _text(snapshot['schemaKey']) ?? fallbackSchemaKey,
      schemaVersion:
          _integer(snapshot['schemaVersion']) ?? fallbackSchemaVersion,
      values: values,
      calculations: calculations,
      generatedAt: _requiredDate(snapshot['generatedAt'], 'generatedAt'),
    );
  }

  Map<String, Object?> toSnapshot() => {
    'version': version,
    'schemaKey': schemaKey,
    'schemaVersion': schemaVersion,
    'values': values,
    'calculations': calculations,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
  };
}

class AgentIntakeDetails {
  AgentIntakeDetails({
    required this.session,
    required List<AgentIntakeValue> values,
    required List<AgentIntakeTurn> turns,
  }) : values = List.unmodifiable(values),
       turns = List.unmodifiable(turns);

  final AgentIntakeSession session;
  final List<AgentIntakeValue> values;
  final List<AgentIntakeTurn> turns;

  AgentStationSchema get schema =>
      AgentStationRegistry.require(session.schemaKey, session.schemaVersion);

  AgentIntakeValue? valueFor(String fieldKey) {
    for (final value in values) {
      if (value.fieldKey == fieldKey) return value;
    }
    return null;
  }
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _requiredText(Object? value, String field) {
  final text = _text(value);
  if (text == null) throw FormatException('$field is required');
  return text;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value.toUtc();
  final text = _text(value);
  if (text == null) return null;
  final day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (day != null) {
    return DateTime.utc(
      int.parse(day.group(1)!),
      int.parse(day.group(2)!),
      int.parse(day.group(3)!),
    );
  }
  return DateTime.tryParse(text)?.toUtc();
}

DateTime _requiredDate(Object? value, String field) {
  final date = _date(value);
  if (date == null) throw FormatException('$field is invalid');
  return date;
}

String _dayText(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

Object? _jsonValue(Object? value) {
  if (value is String) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return value;
    }
  }
  return value;
}

Map<String, dynamic>? _jsonObject(Object? value) {
  final decoded = _jsonValue(value);
  if (decoded is Map) {
    return decoded.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

Map<String, dynamic>? _immutableJsonObject(Map<String, dynamic>? source) {
  if (source == null) return null;
  return UnmodifiableMapView(
    source.map((key, value) => MapEntry(key, _immutableJsonValue(value))),
  );
}

Map<String, Object?> _immutableJsonMap(Map<String, Object?> source) {
  return UnmodifiableMapView(
    source.map((key, value) => MapEntry(key, _immutableJsonValue(value))),
  );
}

Object? _immutableJsonValue(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView(
      value.map(
        (key, item) => MapEntry(key.toString(), _immutableJsonValue(item)),
      ),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_immutableJsonValue));
  }
  return value;
}

Map<String, Object?> _legacyPasgarCalculations(
  String schemaKey,
  Map<String, Object?> values,
) {
  if (schemaKey != 'chicks.pasgar') return const {};
  final sampleSize = _integer(values['pasgarSampleSize']) ?? 0;
  final result = <String, Object?>{};
  const percentageKeys = <String, String>{
    'pasgarReflexesCount': 'pasgarReflexPct',
    'pasgarBeakCount': 'pasgarBeakPct',
    'pasgarNavelCount': 'pasgarNavelPct',
    'pasgarBellyCount': 'pasgarBellyPct',
    'pasgarLegCount': 'pasgarLegPct',
    'pasgarFeatherDevCount': 'pasgarFeatherDevPct',
  };
  for (final entry in percentageKeys.entries) {
    final percentage = CalculationUtils.percentOf(
      _integer(values[entry.key]),
      sampleSize,
    );
    if (percentage != null) result[entry.value] = percentage;
  }
  result['pasgarScore'] = CalculationUtils.pasgarScore(
    sampleSize,
    AgentIntakeSummary.pasgarFieldKeys
        .skip(1)
        .take(CalculationUtils.pasgarScoredDefectCategoryCount)
        .map((key) => _integer(values[key]) ?? 0)
        .toList(growable: false),
  );
  return result;
}
