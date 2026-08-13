import '../../data/models/hatchery_agent_models.dart';
import 'supabase_service.dart';

typedef TelegramAgentSettingsUpsert =
    Future<List<Map<String, dynamic>>> Function(
      String table,
      List<Map<String, dynamic>> rows,
    );

abstract interface class TelegramAgentSettingsPort {
  Future<AgentSettings> confirm(AgentSettings requested);
}

class TelegramAgentSettingsException implements Exception {
  const TelegramAgentSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TelegramAgentSettingsService implements TelegramAgentSettingsPort {
  TelegramAgentSettingsService({
    SupabaseService? supabaseService,
    TelegramAgentSettingsUpsert? upsertRows,
  }) : _upsertRows =
           upsertRows ??
           (supabaseService ?? SupabaseService()).upsertRowsReturningStrict;

  final TelegramAgentSettingsUpsert _upsertRows;

  @override
  Future<AgentSettings> confirm(AgentSettings requested) async {
    try {
      final rows = await _upsertRows('agent_settings', [requested.toMap()]);
      if (rows.length != 1) {
        throw const FormatException('Expected one agent settings row');
      }
      final confirmed = agentSettingsFromSupabaseRow(rows.single);
      if (confirmed.id != requested.id ||
          confirmed.telegramEnabled != requested.telegramEnabled) {
        throw const FormatException(
          'Cloud agent setting did not match the request',
        );
      }
      return confirmed;
    } catch (_) {
      throw const TelegramAgentSettingsException(
        'Unable to update Telegram agent. Please try again.',
      );
    }
  }
}

AgentSettings agentSettingsFromSupabaseRow(Map<String, dynamic> row) {
  final id = row['id'];
  final enabled = row['telegram_enabled'];
  final warning = row['hatchability_warning_threshold_points'];
  final confidence = row['minimum_ready_confidence_pct'];
  final updatedText = row['updated_at']?.toString();
  final updatedAt = updatedText == null ? null : DateTime.tryParse(updatedText);
  if (id is! int ||
      enabled is! int ||
      (enabled != 0 && enabled != 1) ||
      warning is! num ||
      confidence is! num ||
      updatedAt == null) {
    throw const FormatException('Invalid agent settings confirmation');
  }
  return AgentSettings(
    id: id,
    telegramEnabled: enabled == 1,
    hatchabilityWarningThresholdPoints: warning.toDouble(),
    minimumReadyConfidencePct: confidence.toDouble(),
    updatedAt: updatedAt.toUtc(),
  );
}
