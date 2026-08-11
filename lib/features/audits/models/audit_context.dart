/// The flock/session context an audit session is being captured against.
///
/// Moved verbatim out of `providers/audit_provider.dart` so that
/// `services/audit_panel_save_coordinator.dart` can depend on it without a
/// circular import back into the provider. `audit_provider.dart` re-exports
/// this library, so every existing `import '.../audit_provider.dart'` call
/// site still resolves `AuditContext` unchanged.
class AuditContext {
  final String auditType;
  final String customerId;
  final String flockId;
  final String? hatcheryId;
  final String? breed;
  final String? setterId;
  final String? hatcherId;
  final DateTime? flockEntryDate;
  final int? flockAgeWeeks;
  final String date;

  AuditContext({
    required this.auditType,
    required this.customerId,
    required this.flockId,
    this.hatcheryId,
    this.breed,
    this.setterId,
    this.hatcherId,
    this.flockEntryDate,
    this.flockAgeWeeks,
    required this.date,
  });
}
