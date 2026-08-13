import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';
import 'package:hatchaudit/services/supabase/telegram_agent_settings_service.dart';

void main() {
  test('returns the cloud-confirmed agent setting', () async {
    String? table;
    List<Map<String, dynamic>>? rows;
    final service = TelegramAgentSettingsService(
      upsertRows: (name, values) async {
        table = name;
        rows = values;
        return [
          {
            'id': 1,
            'telegram_enabled': 1,
            'hatchability_warning_threshold_points': 4.0,
            'minimum_ready_confidence_pct': 90.0,
            'updated_at': '2026-08-13T18:00:00.000Z',
          },
        ];
      },
    );

    final confirmed = await service.confirm(
      AgentSettings(
        telegramEnabled: true,
        hatchabilityWarningThresholdPoints: 4,
        minimumReadyConfidencePct: 90,
        updatedAt: DateTime.utc(2026, 8, 13, 18),
      ),
    );

    expect(table, 'agent_settings');
    expect(rows, hasLength(1));
    expect(rows!.single, {
      'id': 1,
      'telegramEnabled': 1,
      'hatchabilityWarningThresholdPoints': 4.0,
      'minimumReadyConfidencePct': 90.0,
      'updatedAt': '2026-08-13T18:00:00.000Z',
    });
    expect(confirmed.telegramEnabled, isTrue);
    expect(confirmed.hatchabilityWarningThresholdPoints, 4);
    expect(confirmed.minimumReadyConfidencePct, 90);
    expect(confirmed.updatedAt, DateTime.utc(2026, 8, 13, 18));
  });

  test('rejects a missing cloud confirmation row', () async {
    final service = TelegramAgentSettingsService(
      upsertRows: (_, _) async => const [],
    );

    await expectLater(
      service.confirm(const AgentSettings(telegramEnabled: true)),
      throwsA(
        isA<TelegramAgentSettingsException>().having(
          (error) => error.message,
          'message',
          'Unable to update Telegram agent. Please try again.',
        ),
      ),
    );
  });

  test('rejects a cloud value different from the request', () async {
    final service = TelegramAgentSettingsService(
      upsertRows: (_, _) async => [
        {
          'id': 1,
          'telegram_enabled': 0,
          'hatchability_warning_threshold_points': 3.0,
          'minimum_ready_confidence_pct': 85.0,
          'updated_at': '2026-08-13T18:00:00.000Z',
        },
      ],
    );

    await expectLater(
      service.confirm(const AgentSettings(telegramEnabled: true)),
      throwsA(isA<TelegramAgentSettingsException>()),
    );
  });

  test('rejects malformed required cloud fields', () async {
    final service = TelegramAgentSettingsService(
      upsertRows: (_, _) async => [
        {
          'id': 1,
          'telegram_enabled': 'running',
          'hatchability_warning_threshold_points': 3.0,
          'minimum_ready_confidence_pct': 85.0,
          'updated_at': 'not-a-date',
        },
      ],
    );

    await expectLater(
      service.confirm(const AgentSettings(telegramEnabled: true)),
      throwsA(isA<TelegramAgentSettingsException>()),
    );
  });
}
