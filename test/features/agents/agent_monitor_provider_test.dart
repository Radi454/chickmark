import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/agent_intake_models.dart';
import 'package:hatchaudit/data/models/agent_diagnostic_models.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/agent_intake_repository.dart';
import 'package:hatchaudit/data/repositories/agent_diagnostic_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_agent_repository.dart';
import 'package:hatchaudit/features/agents/providers/agent_monitor_provider.dart';
import 'package:hatchaudit/services/supabase/agent_intake_approval_service.dart';
import 'package:hatchaudit/services/supabase/telegram_agent_settings_service.dart';

void main() {
  test('load exposes newest batch summaries', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: [
        _summary(id: 'batch-new', submittedAt: DateTime.utc(2026, 7, 27)),
        _summary(id: 'batch-old', submittedAt: DateTime.utc(2026, 7, 26)),
      ],
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.load();

    expect(provider.isLoading, isFalse);
    expect(provider.batches.map((batch) => batch.id), [
      'batch-new',
      'batch-old',
    ]);
  });

  test('load exposes the persisted Telegram setting', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      settings: const AgentSettings(telegramEnabled: false),
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.load();

    expect(provider.settings.telegramEnabled, isFalse);
  });

  test('load exposes bounded agent health and conversation context', () async {
    final diagnostics = _FakeAgentDiagnosticRepository(
      health: const AgentHealthSnapshot(
        conversationCount: 2,
        failedDeliveryCount: 1,
      ),
      conversations: [
        AgentConversationDiagnostic(
          id: 'conversation-1',
          contextEpoch: 2,
          updatedAt: DateTime.utc(2026, 7, 30),
          customerName: 'Customer One',
          flockName: 'Flock One',
          latestTurnIndex: 4,
          provider: 'openai',
          model: 'gpt-4.1-mini',
        ),
      ],
    );
    final provider = _providerFor(
      _adminUser(),
      _FakeHatcheryAgentRepository(summaries: const []),
      diagnosticRepository: diagnostics,
    );

    await provider.load();

    expect(provider.health.conversationCount, 2);
    expect(provider.health.failedDeliveryCount, 1);
    expect(provider.conversationDiagnostics.single.contextEpoch, 2);
    expect(diagnostics.loadCount, 1);
  });

  test('load exposes customer choices for draft editing', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      linkCatalog: HatcheryAgentLinkCatalog(
        customers: [
          CustomerModel(
            id: 'customer-1',
            name: 'Customer One',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: 'test',
          ),
        ],
      ),
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.load();

    expect(provider.linkCatalog.customers.single.id, 'customer-1');
  });

  test('load exposes pending Telegram staff requests', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      pendingStaffLinks: [
        TelegramStaffLink(
          id: 'pending-1',
          telegramUserId: '999',
          telegramChatId: '123',
          displayName: 'New Staff',
          username: 'newstaff',
          status: TelegramStaffLinkStatus.pending,
          createdAt: DateTime.utc(2026, 7, 27, 8),
          updatedAt: DateTime.utc(2026, 7, 27, 8),
        ),
      ],
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.load();

    expect(provider.pendingStaffLinks.single.telegramUserId, '999');
    expect(provider.pendingStaffLinks.single.displayName, 'New Staff');
  });

  test('load exposes allowed Telegram users with enforced scope', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      staffLinks: const [
        TelegramStaffLink(
          id: 'allowed-1',
          telegramUserId: '999',
          status: TelegramStaffLinkStatus.allowed,
          accessRole: TelegramAgentAccessRole.customer,
          customerId: 'customer-1',
        ),
      ],
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.load();

    expect(provider.staffLinks.single.id, 'allowed-1');
    expect(
      provider.staffLinks.single.accessRole,
      TelegramAgentAccessRole.customer,
    );
    expect(provider.staffLinks.single.customerId, 'customer-1');
  });

  test('selectBatch exposes the requested batch details', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      detailsById: {'batch-1': _details('batch-1')},
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.selectBatch('batch-1');

    expect(provider.selectedBatch?.batch.id, 'batch-1');
  });

  test('load selects the newest batch when none is selected', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: [
        _summary(id: 'batch-new', submittedAt: DateTime.utc(2026, 7, 27)),
      ],
      detailsById: {'batch-new': _details('batch-new')},
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.load();

    expect(provider.selectedBatch?.batch.id, 'batch-new');
  });

  test('resume confirms cloud before local and visible state', () async {
    final events = <String>[];
    final cloud = _FakeTelegramAgentSettingsPort.controlled(events: events);
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      settings: const AgentSettings(telegramEnabled: false),
      settingsEvents: events,
    );
    final provider = _providerFor(
      _adminUser(),
      repository,
      telegramSettingsPort: cloud,
    );
    await provider.load();

    final operation = provider.setTelegramEnabled(true);
    await Future<void>.delayed(Duration.zero);

    expect(provider.settings.telegramEnabled, isFalse);
    expect(provider.isUpdatingTelegram, isTrue);
    expect(repository.settingsSaveCount, 0);
    expect(events, ['cloud-start']);

    cloud.complete(telegramEnabled: true);
    await operation;

    expect(events, ['cloud-start', 'cloud-confirmed', 'local-confirmed']);
    expect(provider.isUpdatingTelegram, isFalse);
    expect(provider.settings.telegramEnabled, isTrue);
    expect(repository.settings.telegramEnabled, isTrue);
    expect(repository.settingsSaveCount, 1);
  });

  test('pause confirms cloud before local and visible state', () async {
    final events = <String>[];
    final cloud = _FakeTelegramAgentSettingsPort.controlled(events: events);
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      settingsEvents: events,
    );
    final provider = _providerFor(
      _adminUser(),
      repository,
      telegramSettingsPort: cloud,
    );
    await provider.load();

    final operation = provider.setTelegramEnabled(false);
    await Future<void>.delayed(Duration.zero);

    expect(provider.settings.telegramEnabled, isTrue);
    expect(repository.settingsSaveCount, 0);
    cloud.complete(telegramEnabled: false);
    await operation;

    expect(events, ['cloud-start', 'cloud-confirmed', 'local-confirmed']);
    expect(provider.settings.telegramEnabled, isFalse);
    expect(repository.settings.telegramEnabled, isFalse);
    expect(repository.settingsSaveCount, 1);
  });

  test(
    'resume cloud failure preserves paused local and provider state',
    () async {
      final cloud = _FakeTelegramAgentSettingsPort.controlled();
      final repository = _FakeHatcheryAgentRepository(
        summaries: const [],
        settings: const AgentSettings(telegramEnabled: false),
      );
      final provider = _providerFor(
        _adminUser(),
        repository,
        telegramSettingsPort: cloud,
      );
      await provider.load();

      final operation = provider.setTelegramEnabled(true);
      await Future<void>.delayed(Duration.zero);
      cloud.fail();
      await operation;

      expect(repository.settingsSaveCount, 0);
      expect(repository.settings.telegramEnabled, isFalse);
      expect(provider.settings.telegramEnabled, isFalse);
      expect(provider.isUpdatingTelegram, isFalse);
      expect(
        provider.error,
        'Unable to update Telegram agent. Please try again.',
      );
    },
  );

  test(
    'pause cloud failure preserves running local and provider state',
    () async {
      final cloud = _FakeTelegramAgentSettingsPort.controlled();
      final repository = _FakeHatcheryAgentRepository(summaries: const []);
      final provider = _providerFor(
        _adminUser(),
        repository,
        telegramSettingsPort: cloud,
      );
      await provider.load();

      final operation = provider.setTelegramEnabled(false);
      await Future<void>.delayed(Duration.zero);
      cloud.fail();
      await operation;

      expect(repository.settingsSaveCount, 0);
      expect(repository.settings.telegramEnabled, isTrue);
      expect(provider.settings.telegramEnabled, isTrue);
      expect(provider.isUpdatingTelegram, isFalse);
    },
  );

  test('provider publishes threshold values returned by cloud', () async {
    final cloud = _FakeTelegramAgentSettingsPort(
      confirmed: AgentSettings(
        telegramEnabled: false,
        hatchabilityWarningThresholdPoints: 4,
        minimumReadyConfidencePct: 90,
        updatedAt: DateTime.utc(2026, 8, 13, 18),
      ),
    );
    final repository = _FakeHatcheryAgentRepository(summaries: const []);
    final provider = _providerFor(
      _adminUser(),
      repository,
      telegramSettingsPort: cloud,
    );
    await provider.load();

    await provider.setTelegramEnabled(false);

    expect(provider.settings.telegramEnabled, isFalse);
    expect(provider.settings.hatchabilityWarningThresholdPoints, 4);
    expect(provider.settings.minimumReadyConfidencePct, 90);
    expect(repository.settings.minimumReadyConfidencePct, 90);
  });

  test(
    'repeated requests while active create one cloud and local write',
    () async {
      final cloud = _FakeTelegramAgentSettingsPort.controlled();
      final repository = _FakeHatcheryAgentRepository(summaries: const []);
      final provider = _providerFor(
        _adminUser(),
        repository,
        telegramSettingsPort: cloud,
      );
      await provider.load();

      final first = provider.setTelegramEnabled(false);
      await Future<void>.delayed(Duration.zero);
      await provider.setTelegramEnabled(false);
      await provider.setTelegramEnabled(true);

      expect(cloud.callCount, 1);
      expect(repository.settingsSaveCount, 0);
      cloud.complete(telegramEnabled: false);
      await first;

      expect(repository.settingsSaveCount, 1);
      expect(provider.settings.telegramEnabled, isFalse);
      expect(repository.settings.telegramEnabled, isFalse);
    },
  );

  test(
    'approveStaffLink assigns one customer and reloads Telegram users',
    () async {
      final repository = _FakeHatcheryAgentRepository(
        summaries: const [],
        pendingStaffLinks: [
          TelegramStaffLink(
            id: 'pending-1',
            telegramUserId: '999',
            status: TelegramStaffLinkStatus.pending,
          ),
        ],
      );
      final provider = _providerFor(_adminUser(), repository);
      await provider.load();

      await provider.approveStaffLink(
        linkId: 'pending-1',
        accessRole: TelegramAgentAccessRole.customer,
        customerId: 'customer-1',
      );

      expect(repository.scopeDecisions.single.linkId, 'pending-1');
      expect(
        repository.scopeDecisions.single.accessRole,
        TelegramAgentAccessRole.customer,
      );
      expect(repository.scopeDecisions.single.customerId, 'customer-1');
      expect(repository.scopeDecisions.single.decidedBy, 'admin-1');
      expect(provider.pendingStaffLinks, isEmpty);
      expect(
        provider.staffLinks.single.status,
        TelegramStaffLinkStatus.allowed,
      );
    },
  );

  test('approveStaffLink blocks customer access without a customer', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      pendingStaffLinks: const [
        TelegramStaffLink(
          id: 'pending-1',
          telegramUserId: '999',
          status: TelegramStaffLinkStatus.pending,
        ),
      ],
    );
    final provider = _providerFor(_adminUser(), repository);
    await provider.load();

    await provider.approveStaffLink(
      linkId: 'pending-1',
      accessRole: TelegramAgentAccessRole.customer,
      customerId: null,
    );

    expect(repository.scopeDecisions, isEmpty);
    expect(provider.error, 'Select a customer before allowing access.');
    expect(provider.pendingStaffLinks, hasLength(1));
  });

  test('approveStaffLink permits explicit all-customer admin access', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      pendingStaffLinks: const [
        TelegramStaffLink(
          id: 'pending-1',
          telegramUserId: '999',
          status: TelegramStaffLinkStatus.pending,
        ),
      ],
    );
    final provider = _providerFor(_adminUser(), repository);
    await provider.load();

    await provider.approveStaffLink(
      linkId: 'pending-1',
      accessRole: TelegramAgentAccessRole.admin,
      customerId: null,
    );

    expect(
      repository.scopeDecisions.single.accessRole,
      TelegramAgentAccessRole.admin,
    );
    expect(repository.scopeDecisions.single.customerId, isNull);
  });

  test('revokeStaffLink marks the request revoked', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      pendingStaffLinks: [
        TelegramStaffLink(
          id: 'pending-1',
          telegramUserId: '999',
          status: TelegramStaffLinkStatus.pending,
        ),
      ],
    );
    final provider = _providerFor(_adminUser(), repository);
    await provider.load();

    await provider.revokeStaffLink('pending-1');

    expect(
      repository.statusDecisions.single.status,
      TelegramStaffLinkStatus.revoked,
    );
    expect(provider.pendingStaffLinks, isEmpty);
  });

  test(
    'auditor and customer cannot load or change Telegram settings',
    () async {
      for (final user in [_auditorUser(), _customerUser()]) {
        final repository = _FakeHatcheryAgentRepository(summaries: const []);
        final provider = _providerFor(user, repository);

        await provider.load();
        await provider.setTelegramEnabled(false);

        expect(provider.canAccessMonitor, isFalse, reason: user.role);
        expect(repository.settingsLoadCount, 0, reason: user.role);
        expect(repository.summaryLoadCount, 0, reason: user.role);
        expect(repository.settingsSaveCount, 0, reason: user.role);
        expect(provider.settings.telegramEnabled, isTrue, reason: user.role);
      }
    },
  );

  test('unapproved admin cannot access Agent Monitor', () async {
    final user = _adminUser(status: 'pending');
    final repository = _FakeHatcheryAgentRepository(summaries: const []);
    final provider = _providerFor(user, repository);

    await provider.load();
    await provider.setTelegramEnabled(false);
    await provider.approveStaffLink(
      linkId: 'pending-1',
      accessRole: TelegramAgentAccessRole.admin,
      customerId: null,
    );
    await provider.revokeStaffLink('pending-1');

    expect(provider.canAccessMonitor, isFalse);
    expect(repository.settingsLoadCount, 0);
    expect(repository.settingsSaveCount, 0);
    expect(repository.scopeDecisions, isEmpty);
    expect(repository.statusDecisions, isEmpty);
  });

  test('load exposes a readable error when the repository fails', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      listError: StateError('database unavailable'),
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.load();

    expect(provider.isLoading, isFalse);
    expect(provider.error, 'Unable to load agent data. Please try again.');
  });

  test(
    'local cache failure keeps the cloud-confirmed setting visible',
    () async {
      final repository = _FakeHatcheryAgentRepository(
        summaries: const [],
        saveError: StateError('write failed'),
      );
      final provider = _providerFor(_adminUser(), repository);
      await provider.load();

      await provider.setTelegramEnabled(false);

      expect(provider.settings.telegramEnabled, isFalse);
      expect(repository.settings.telegramEnabled, isTrue);
      expect(
        provider.error,
        'Telegram updated, but the local cache could not be refreshed.',
      );
    },
  );

  test(
    'refreshSelected replaces the selected batch with fresh details',
    () async {
      final detailsById = <String, HatcheryDraftBatchDetails>{
        'batch-1': _details('batch-1'),
      };
      final repository = _FakeHatcheryAgentRepository(
        summaries: const [],
        detailsById: detailsById,
      );
      final provider = _providerFor(_adminUser(), repository);
      await provider.selectBatch('batch-1');
      detailsById['batch-1'] = _details(
        'batch-1',
        status: AgentSubmissionStatus.needsAdminReview,
      );

      await provider.refreshSelected();

      expect(
        provider.selectedBatch?.batch.status,
        AgentSubmissionStatus.needsAdminReview,
      );
    },
  );

  test('selectBatch exposes a readable error when details fail', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      detailError: StateError('read failed'),
    );
    final provider = _providerFor(_adminUser(), repository);

    await provider.selectBatch('batch-1');

    expect(provider.isLoading, isFalse);
    expect(provider.error, 'Unable to load this draft. Please try again.');
  });

  test(
    'approveRow approves then reloads selected details and summaries',
    () async {
      final repository = _FakeHatcheryAgentRepository(
        summaries: [
          _summary(id: 'batch-1', submittedAt: DateTime.utc(2026, 7, 27)),
        ],
        detailsById: {'batch-1': _details('batch-1')},
      );
      final provider = _providerFor(_adminUser(), repository);
      await provider.load();
      final initialDetailLoads = repository.detailLoadCount;
      final initialSummaryLoads = repository.summaryLoadCount;

      await provider.approveRow('row-1', 'admin-1');

      expect(repository.approvedRowId, 'row-1');
      expect(repository.approvedBy, 'admin-1');
      expect(repository.detailLoadCount, initialDetailLoads + 1);
      expect(repository.summaryLoadCount, initialSummaryLoads + 1);
    },
  );

  test('rejectRow forwards its reason then refreshes monitor data', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: [
        _summary(id: 'batch-1', submittedAt: DateTime.utc(2026, 7, 27)),
      ],
      detailsById: {'batch-1': _details('batch-1')},
    );
    final provider = _providerFor(_adminUser(), repository);
    await provider.load();

    await provider.rejectRow('row-1', 'admin-1', reason: 'Wrong flock');

    expect(repository.rejectedRowId, 'row-1');
    expect(repository.rejectedBy, 'admin-1');
    expect(repository.rejectionReason, 'Wrong flock');
    expect(repository.detailLoadCount, 2);
    expect(repository.summaryLoadCount, 2);
  });

  test('saveRowEdit persists the row then refreshes monitor data', () async {
    final row = _row('row-1');
    final repository = _FakeHatcheryAgentRepository(
      summaries: [
        _summary(id: 'batch-1', submittedAt: DateTime.utc(2026, 7, 27)),
      ],
      detailsById: {
        'batch-1': _details('batch-1', rows: [row]),
      },
    );
    final provider = _providerFor(_adminUser(), repository);
    await provider.load();
    final edited = row.copyWith(stationName: 'Station B');

    await provider.saveRowEdit(edited);

    expect(repository.updatedRow?.stationName, 'Station B');
    expect(repository.detailLoadCount, 2);
    expect(repository.summaryLoadCount, 2);
  });

  test('loads confirmed Pasgar intakes alongside hatchery batches', () async {
    final intakeRepository = _FakeAgentIntakeRepository(
      sessions: [_intakeSession()],
      detailsById: {'intake-1': _intakeDetails()},
    );
    final provider = _providerFor(
      _adminUser(),
      _FakeHatcheryAgentRepository(summaries: const []),
      intakeRepository: intakeRepository,
    );

    await provider.load();

    expect(provider.intakes.map((intake) => intake.id), ['intake-1']);
    expect(provider.selectedIntake?.session.id, 'intake-1');
  });

  test('Pasgar edits refresh the final review summary', () async {
    final intakeRepository = _FakeAgentIntakeRepository(
      sessions: [_intakeSession()],
      detailsById: {'intake-1': _intakeDetails()},
    );
    final provider = _providerFor(
      _adminUser(),
      _FakeHatcheryAgentRepository(summaries: const []),
      intakeRepository: intakeRepository,
    );
    await provider.load();

    await provider.saveIntakeValue('pasgarNavelCount', 3);

    expect(intakeRepository.updatedFieldKey, 'pasgarNavelCount');
    expect(intakeRepository.updatedValue, 3);
    expect(
      provider.selectedIntake?.session.summary?.values['pasgarNavelCount'],
      3,
    );
  });

  test(
    'Pasgar approval calls the authenticated port then mirrors IDs',
    () async {
      final intakeRepository = _FakeAgentIntakeRepository(
        sessions: [_intakeSession()],
        detailsById: {'intake-1': _intakeDetails()},
      );
      final approval = _FakeApprovalPort();
      final provider = _providerFor(
        _adminUser(),
        _FakeHatcheryAgentRepository(summaries: const []),
        intakeRepository: intakeRepository,
        approvalPort: approval,
      );
      await provider.load();

      await provider.approveIntake(targetSessionId: 'audit-target');

      expect(approval.intakeId, 'intake-1');
      expect(approval.targetSessionId, 'audit-target');
      expect(intakeRepository.approvedAuditSessionId, 'audit-1');
      expect(intakeRepository.approvedPanelRowId, 'panel-1');
      expect(provider.intakes, isEmpty);
    },
  );

  test(
    'Pasgar rejection requires a reason and preserves failed selection',
    () async {
      final intakeRepository = _FakeAgentIntakeRepository(
        sessions: [_intakeSession()],
        detailsById: {'intake-1': _intakeDetails()},
        rejectError: StateError('offline'),
      );
      final provider = _providerFor(
        _adminUser(),
        _FakeHatcheryAgentRepository(summaries: const []),
        intakeRepository: intakeRepository,
      );
      await provider.load();

      await provider.rejectIntake(' ');
      expect(provider.error, 'Enter a rejection reason.');
      await provider.rejectIntake('Wrong flock');

      expect(provider.selectedIntake?.session.id, 'intake-1');
      expect(provider.error, 'Unable to reject this intake. Please try again.');
    },
  );
}

class _FakeHatcheryAgentRepository extends HatcheryAgentRepository {
  _FakeHatcheryAgentRepository({
    required this.summaries,
    this.settings = const AgentSettings(),
    this.linkCatalog = const HatcheryAgentLinkCatalog(),
    this.pendingStaffLinks = const [],
    this.staffLinks = const [],
    this.detailsById = const {},
    this.listError,
    this.saveError,
    this.detailError,
    this.settingsEvents,
  });

  final List<HatcheryDraftBatchSummary> summaries;
  AgentSettings settings;
  final HatcheryAgentLinkCatalog linkCatalog;
  List<TelegramStaffLink> pendingStaffLinks;
  List<TelegramStaffLink> staffLinks;
  final Map<String, HatcheryDraftBatchDetails> detailsById;
  final Object? listError;
  final Object? saveError;
  final Object? detailError;
  final List<String>? settingsEvents;
  int settingsLoadCount = 0;
  int settingsSaveCount = 0;
  int summaryLoadCount = 0;
  int detailLoadCount = 0;
  String? approvedRowId;
  String? approvedBy;
  String? rejectedRowId;
  String? rejectedBy;
  String? rejectionReason;
  HatcheryDraftRow? updatedRow;
  final List<_StaffStatusDecision> statusDecisions = [];
  final List<_StaffScopeDecision> scopeDecisions = [];

  @override
  Future<AgentSettings> loadSettings() async {
    settingsLoadCount++;
    return settings;
  }

  @override
  Future<HatcheryAgentLinkCatalog> loadLinkCatalog() async => linkCatalog;

  @override
  Future<List<TelegramStaffLink>> listPendingStaffLinks() async {
    return pendingStaffLinks;
  }

  @override
  Future<List<TelegramStaffLink>> listStaffLinks() async => staffLinks;

  @override
  Future<List<HatcheryDraftBatchSummary>> listBatchSummaries() async {
    if (listError case final error?) throw error;
    summaryLoadCount++;
    return summaries;
  }

  @override
  Future<HatcheryDraftBatchDetails?> loadBatchDetails(String batchId) async {
    if (detailError case final error?) throw error;
    detailLoadCount++;
    return detailsById[batchId];
  }

  @override
  Future<void> saveSettings(AgentSettings settings) async {
    if (saveError case final error?) throw error;
    settingsSaveCount++;
    this.settings = settings;
  }

  @override
  Future<void> saveConfirmedSettings(AgentSettings settings) async {
    if (saveError case final error?) throw error;
    settingsSaveCount++;
    this.settings = settings;
    settingsEvents?.add('local-confirmed');
  }

  @override
  Future<HatcheryDailyRecord> approveDraftRow({
    required String rowId,
    required String approvedBy,
    required DateTime approvedAt,
  }) async {
    approvedRowId = rowId;
    this.approvedBy = approvedBy;
    return HatcheryDailyRecord(
      id: 'record-1',
      sourceDraftRowId: rowId,
      customerId: 'customer-1',
      flockId: 'flock-1',
      stationName: 'Station A',
      breed: 'Ross',
      eggsPlaced: 1000,
      hatchDate: DateTime.utc(2026, 7, 27),
      totalProduction: 850,
      hatchabilityPct: 85,
      approvedBy: approvedBy,
      approvedAt: approvedAt,
    );
  }

  @override
  Future<void> rejectDraftRow({
    required String rowId,
    required String rejectedBy,
    required DateTime rejectedAt,
    String? reason,
  }) async {
    rejectedRowId = rowId;
    this.rejectedBy = rejectedBy;
    rejectionReason = reason;
  }

  @override
  Future<void> updateDraftRow(HatcheryDraftRow row) async {
    updatedRow = row;
  }

  @override
  Future<void> setStaffLinkStatus({
    required String linkId,
    required TelegramStaffLinkStatus status,
    required String decidedBy,
    required DateTime decidedAt,
  }) async {
    statusDecisions.add(
      _StaffStatusDecision(
        linkId: linkId,
        status: status,
        decidedBy: decidedBy,
      ),
    );
    pendingStaffLinks = pendingStaffLinks
        .where((link) => link.id != linkId)
        .toList(growable: false);
    staffLinks = staffLinks
        .map(
          (link) => link.id == linkId
              ? TelegramStaffLink(
                  id: link.id,
                  telegramUserId: link.telegramUserId,
                  status: status,
                  accessRole: link.accessRole,
                  customerId: link.customerId,
                )
              : link,
        )
        .toList(growable: false);
  }

  @override
  Future<void> approveStaffLink({
    required String linkId,
    required TelegramAgentAccessRole accessRole,
    required String? customerId,
    required String decidedBy,
    required DateTime decidedAt,
  }) async {
    scopeDecisions.add(
      _StaffScopeDecision(
        linkId: linkId,
        accessRole: accessRole,
        customerId: customerId,
        decidedBy: decidedBy,
      ),
    );
    final pending = pendingStaffLinks.firstWhere(
      (link) => link.id == linkId,
      orElse: () => TelegramStaffLink(
        id: linkId,
        telegramUserId: linkId,
        status: TelegramStaffLinkStatus.allowed,
      ),
    );
    final allowed = TelegramStaffLink(
      id: pending.id,
      telegramUserId: pending.telegramUserId,
      telegramChatId: pending.telegramChatId,
      displayName: pending.displayName,
      username: pending.username,
      status: TelegramStaffLinkStatus.allowed,
      accessRole: accessRole,
      customerId: customerId,
      invitedBy: decidedBy,
    );
    pendingStaffLinks = pendingStaffLinks
        .where((link) => link.id != linkId)
        .toList(growable: false);
    staffLinks = [...staffLinks.where((link) => link.id != linkId), allowed];
  }
}

class _StaffStatusDecision {
  const _StaffStatusDecision({
    required this.linkId,
    required this.status,
    required this.decidedBy,
  });

  final String linkId;
  final TelegramStaffLinkStatus status;
  final String decidedBy;
}

class _StaffScopeDecision {
  const _StaffScopeDecision({
    required this.linkId,
    required this.accessRole,
    required this.customerId,
    required this.decidedBy,
  });

  final String linkId;
  final TelegramAgentAccessRole accessRole;
  final String? customerId;
  final String decidedBy;
}

AgentMonitorProvider _providerFor(
  UserModel user,
  HatcheryAgentRepository repository, {
  AgentIntakeRepository? intakeRepository,
  AgentIntakeApprovalPort? approvalPort,
  AgentDiagnosticRepository? diagnosticRepository,
  TelegramAgentSettingsPort? telegramSettingsPort,
}) {
  return AgentMonitorProvider(
    repository: repository,
    intakeRepository: intakeRepository ?? _FakeAgentIntakeRepository(),
    approvalPort: approvalPort ?? _FakeApprovalPort(),
    diagnosticRepository:
        diagnosticRepository ?? _FakeAgentDiagnosticRepository(),
    telegramSettingsPort:
        telegramSettingsPort ?? _FakeTelegramAgentSettingsPort(),
    currentUser: user,
  );
}

class _FakeTelegramAgentSettingsPort implements TelegramAgentSettingsPort {
  _FakeTelegramAgentSettingsPort({this.events, this.confirmed, this.error})
    : _completion = null;

  _FakeTelegramAgentSettingsPort.controlled({this.events})
    : confirmed = null,
      error = null,
      _completion = Completer<AgentSettings>();

  final List<String>? events;
  final AgentSettings? confirmed;
  final Object? error;
  final Completer<AgentSettings>? _completion;
  int callCount = 0;
  AgentSettings? requested;

  @override
  Future<AgentSettings> confirm(AgentSettings requested) async {
    callCount++;
    this.requested = requested;
    events?.add('cloud-start');
    if (error case final failure?) throw failure;
    final result = _completion == null
        ? (confirmed ?? requested)
        : await _completion.future;
    events?.add('cloud-confirmed');
    return result;
  }

  void complete({
    required bool telegramEnabled,
    double hatchabilityWarningThresholdPoints = 3,
    double minimumReadyConfidencePct = 85,
  }) {
    _completion!.complete(
      AgentSettings(
        id: requested?.id ?? 1,
        telegramEnabled: telegramEnabled,
        hatchabilityWarningThresholdPoints: hatchabilityWarningThresholdPoints,
        minimumReadyConfidencePct: minimumReadyConfidencePct,
        updatedAt: DateTime.utc(2026, 8, 13, 18),
      ),
    );
  }

  void fail() {
    _completion!.completeError(StateError('cloud unavailable'));
  }
}

class _FakeAgentDiagnosticRepository extends AgentDiagnosticRepository {
  _FakeAgentDiagnosticRepository({
    this.health = const AgentHealthSnapshot(),
    this.conversations = const [],
  });

  final AgentHealthSnapshot health;
  final List<AgentConversationDiagnostic> conversations;
  int loadCount = 0;

  @override
  Future<AgentHealthSnapshot> loadHealth() async {
    loadCount++;
    return health;
  }

  @override
  Future<List<AgentConversationDiagnostic>> listConversationDiagnostics({
    int limit = 25,
  }) async {
    return conversations;
  }
}

UserModel _adminUser({String status = 'approved'}) {
  return UserModel(
    id: 'admin-1',
    fullName: 'Admin',
    email: 'admin@example.test',
    role: 'admin',
    status: status,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

UserModel _auditorUser() {
  return UserModel(
    id: 'auditor-1',
    fullName: 'Auditor',
    email: 'auditor@example.test',
    role: 'auditor',
    status: 'approved',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

UserModel _customerUser() {
  return UserModel(
    id: 'customer-user-1',
    fullName: 'Customer',
    email: 'customer@example.test',
    role: 'customer',
    status: 'approved',
    customerId: 'customer-1',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

HatcheryDraftBatchSummary _summary({
  required String id,
  required DateTime submittedAt,
}) {
  return HatcheryDraftBatchSummary(
    id: id,
    submissionId: 'submission-$id',
    status: AgentSubmissionStatus.draftReady,
    submittedAt: submittedAt,
    sourceKind: AgentSourceKind.text,
    rowCount: 1,
    needsReviewCount: 0,
    approvedCount: 0,
    rejectedCount: 0,
  );
}

HatcheryDraftBatchDetails _details(
  String batchId, {
  AgentSubmissionStatus status = AgentSubmissionStatus.draftReady,
  List<HatcheryDraftRow> rows = const [],
}) {
  return HatcheryDraftBatchDetails(
    submission: HatcheryAgentSubmission(
      id: 'submission-$batchId',
      sourceKind: AgentSourceKind.text,
      status: status,
      submittedAt: DateTime.utc(2026, 7, 27),
    ),
    batch: HatcheryDraftBatch(
      id: batchId,
      submissionId: 'submission-$batchId',
      status: status,
    ),
    rows: rows,
    questions: const [],
    events: const [],
  );
}

HatcheryDraftRow _row(String id) {
  return HatcheryDraftRow(
    id: id,
    batchId: 'batch-1',
    rowOrdinal: 1,
    status: HatcheryDraftRowStatus.needsReview,
    customerId: 'customer-1',
    flockId: 'flock-1',
    stationName: 'Station A',
    breed: 'Ross',
    eggsPlaced: 1000,
    hatchDate: DateTime.utc(2026, 7, 27),
    totalProduction: 850,
    hatchabilityPct: 85,
  );
}

class _FakeAgentIntakeRepository extends AgentIntakeRepository {
  _FakeAgentIntakeRepository({
    this.sessions = const [],
    this.detailsById = const {},
    this.rejectError,
  });

  List<AgentIntakeSession> sessions;
  final Map<String, AgentIntakeDetails> detailsById;
  final Object? rejectError;
  String? updatedFieldKey;
  Object? updatedValue;
  String? approvedAuditSessionId;
  String? approvedPanelRowId;

  @override
  Future<List<AgentIntakeSession>> listAwaitingReview() async => sessions;

  @override
  Future<AgentIntakeDetails?> loadDetails(String intakeId) async {
    return detailsById[intakeId];
  }

  @override
  Future<List<AuditSessionModel>> listMatchingAuditSessions(
    AgentIntakeSession intake,
  ) async {
    return const [];
  }

  @override
  Future<void> updateValue({
    required String intakeId,
    required String fieldKey,
    required Object? value,
    DateTime? updatedAt,
  }) async {
    updatedFieldKey = fieldKey;
    updatedValue = value;
    final current = detailsById[intakeId]!;
    final map = current.session.toMap();
    final values = Map<String, Object?>.from(current.session.workingValues)
      ..[fieldKey] = value;
    final version = current.session.summaryVersion + 1;
    map['workingValuesJson'] = values;
    map['summaryVersion'] = version;
    map['summarySnapshotJson'] = {
      'version': version,
      'values': values,
      'generatedAt': '2026-07-28T13:00:00.000Z',
    };
    detailsById[intakeId] = AgentIntakeDetails(
      session: AgentIntakeSession.fromMap(map),
      values: current.values,
      turns: current.turns,
    );
    sessions = [detailsById[intakeId]!.session];
  }

  @override
  Future<void> markApproved({
    required String intakeId,
    required String auditSessionId,
    required String panelRowId,
    required String reviewedBy,
    DateTime? reviewedAt,
  }) async {
    approvedAuditSessionId = auditSessionId;
    approvedPanelRowId = panelRowId;
    sessions = [];
  }

  @override
  Future<void> reject({
    required String intakeId,
    required String reason,
    required String reviewedBy,
    DateTime? reviewedAt,
  }) async {
    if (rejectError case final error?) throw error;
    sessions = [];
  }
}

class _FakeApprovalPort implements AgentIntakeApprovalPort {
  String? intakeId;
  String? targetSessionId;

  @override
  Future<AgentIntakeApprovalResult> approve({
    required String intakeId,
    required int expectedSummaryVersion,
    String? targetSessionId,
  }) async {
    this.intakeId = intakeId;
    this.targetSessionId = targetSessionId;
    return const AgentIntakeApprovalResult(
      intakeId: 'intake-1',
      auditSessionId: 'audit-1',
      panelRowId: 'panel-1',
      alreadyApproved: false,
    );
  }
}

AgentIntakeSession _intakeSession({
  Map<String, int>? values,
  int summaryVersion = 1,
}) {
  final workingValues = values ?? _pasgarValues;
  return AgentIntakeSession.fromMap({
    'id': 'intake-1',
    'staffLinkId': 'staff-1',
    'telegramChatId': 'chat-1',
    'schemaKey': 'chicks.pasgar',
    'schemaVersion': 1,
    'state': 'awaiting_admin_review',
    'language': 'en',
    'customerId': 'customer-1',
    'customerName': 'Customer One',
    'flockId': 'flock-1',
    'flockName': 'Flock One',
    'hatcheryId': 'hatchery-1',
    'hatcheryName': 'Main Hatchery',
    'auditDate': '2026-07-28',
    'scope': 'pool',
    'workingValuesJson': workingValues,
    'summaryVersion': summaryVersion,
    'summarySnapshotJson': {
      'version': summaryVersion,
      'values': workingValues,
      'generatedAt': '2026-07-28T12:00:00.000Z',
    },
    'userConfirmedAt': '2026-07-28T12:01:00.000Z',
    'createdAt': '2026-07-28T11:00:00.000Z',
    'updatedAt': '2026-07-28T12:01:00.000Z',
  });
}

AgentIntakeDetails _intakeDetails() {
  return AgentIntakeDetails(
    session: _intakeSession(),
    values: const [],
    turns: const [],
  );
}

const _pasgarValues = <String, int>{
  'pasgarSampleSize': 40,
  'pasgarReflexesCount': 2,
  'pasgarBeakCount': 1,
  'pasgarNavelCount': 1,
  'pasgarBellyCount': 1,
  'pasgarLegCount': 2,
  'pasgarFeatherDevCount': 3,
};
