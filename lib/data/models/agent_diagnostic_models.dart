import 'dart:convert';

class AgentHealthSnapshot {
  const AgentHealthSnapshot({
    this.conversationCount = 0,
    this.failedDeliveryCount = 0,
    this.pendingDeliveryCount = 0,
    this.failedToolCount = 0,
    this.unassignedFlockCount = 0,
  });

  final int conversationCount;
  final int failedDeliveryCount;
  final int pendingDeliveryCount;
  final int failedToolCount;
  final int unassignedFlockCount;

  bool get hasErrors =>
      failedDeliveryCount > 0 ||
      pendingDeliveryCount > 0 ||
      failedToolCount > 0 ||
      unassignedFlockCount > 0;

  factory AgentHealthSnapshot.fromMap(Map<String, Object?> map) {
    return AgentHealthSnapshot(
      conversationCount: _integer(map['conversationCount']),
      failedDeliveryCount: _integer(map['failedDeliveryCount']),
      pendingDeliveryCount: _integer(map['pendingDeliveryCount']),
      failedToolCount: _integer(map['failedToolCount']),
      unassignedFlockCount: _integer(map['unassignedFlockCount']),
    );
  }
}

class AgentConversationDiagnostic {
  const AgentConversationDiagnostic({
    required this.id,
    required this.contextEpoch,
    required this.updatedAt,
    this.staffName,
    this.selectedCustomerId,
    this.selectedFlockId,
    this.selectedAuditId,
    this.customerName,
    this.flockName,
    this.flockSectorKey,
    this.auditLabel,
    this.latestReplyText,
    this.latestTurnIndex,
    this.provider,
    this.model,
    this.deliveryStatus,
    this.latestToolErrorCode,
    this.latestToolErrorAt,
  });

  final String id;
  final int contextEpoch;
  final DateTime? updatedAt;
  final String? staffName;
  final String? selectedCustomerId;
  final String? selectedFlockId;
  final String? selectedAuditId;
  final String? customerName;
  final String? flockName;
  final String? flockSectorKey;
  final String? auditLabel;
  final String? latestReplyText;
  final int? latestTurnIndex;
  final String? provider;
  final String? model;
  final String? deliveryStatus;
  final String? latestToolErrorCode;
  final DateTime? latestToolErrorAt;

  bool get hasUnassignedSector =>
      flockName != null && (flockSectorKey == null || flockSectorKey!.isEmpty);

  factory AgentConversationDiagnostic.fromMap(Map<String, Object?> map) {
    return AgentConversationDiagnostic(
      id: _text(map['id']) ?? '',
      contextEpoch: _integer(map['contextEpoch'], fallback: 1),
      updatedAt: DateTime.tryParse(_text(map['updatedAt']) ?? ''),
      staffName: _text(map['staffName']),
      selectedCustomerId: _text(map['selectedCustomerId']),
      selectedFlockId: _text(map['selectedFlockId']),
      selectedAuditId: _text(map['selectedAuditId']),
      customerName: _text(map['customerName']),
      flockName: _text(map['flockName']),
      flockSectorKey: _text(map['flockSectorKey']),
      auditLabel: _text(map['auditLabel']),
      latestReplyText: _text(map['latestReplyText']),
      latestTurnIndex: _nullableInteger(map['latestTurnIndex']),
      provider: _text(map['provider']),
      model: _text(map['model']),
      deliveryStatus: _text(map['deliveryStatus']),
      latestToolErrorCode: _toolErrorCode(map['latestToolResultJson']),
      latestToolErrorAt: DateTime.tryParse(
        _text(map['latestToolErrorAt']) ?? '',
      ),
    );
  }
}

String? _toolErrorCode(Object? raw) {
  final text = _text(raw);
  if (text == null) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) return _text(decoded['code']);
  } on FormatException {
    return 'unreadable_error_record';
  }
  return null;
}

int _integer(Object? value, {int fallback = 0}) =>
    _nullableInteger(value) ?? fallback;

int? _nullableInteger(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
