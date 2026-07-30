import '../database/database_helper.dart';
import '../models/agent_diagnostic_models.dart';

class AgentDiagnosticRepository {
  AgentDiagnosticRepository({DatabaseHelper? databaseHelper})
    : _databaseHelper = databaseHelper ?? DatabaseHelper();

  final DatabaseHelper _databaseHelper;

  Future<AgentHealthSnapshot> loadHealth() async {
    final db = await _databaseHelper.db;
    final rows = await db.rawQuery('''
      SELECT
        (
          SELECT COUNT(*) FROM agent_conversations
        ) AS conversationCount,
        (
          SELECT COUNT(*)
          FROM agent_conversation_turns
          WHERE direction = 'outbound' AND deliveryStatus = 'failed'
        ) AS failedDeliveryCount,
        (
          SELECT COUNT(*)
          FROM agent_conversation_turns
          WHERE direction = 'outbound' AND deliveryStatus = 'pending'
        ) AS pendingDeliveryCount,
        (
          SELECT COUNT(*)
          FROM agent_tool_events
          WHERE status IN ('rejected', 'failed')
        ) AS failedToolCount,
        (
          SELECT COUNT(*)
          FROM flocks
          WHERE sectorKey IS NULL OR trim(sectorKey) = ''
        ) AS unassignedFlockCount
    ''');
    return AgentHealthSnapshot.fromMap(rows.single);
  }

  Future<List<AgentConversationDiagnostic>> listConversationDiagnostics({
    int limit = 25,
  }) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }
    final db = await _databaseHelper.db;
    final rows = await db.rawQuery(
      '''
        WITH ranked_outbound AS (
          SELECT
            turn.*,
            ROW_NUMBER() OVER (
              PARTITION BY turn.conversationId
              ORDER BY
                turn.contextEpoch DESC,
                turn.turnIndex DESC,
                turn.createdAt DESC,
                turn.id DESC
            ) AS rank
          FROM agent_conversation_turns turn
          WHERE turn.direction = 'outbound'
        ),
        ranked_error AS (
          SELECT
            turn.conversationId,
            event.resultJson,
            event.createdAt AS errorCreatedAt,
            ROW_NUMBER() OVER (
              PARTITION BY turn.conversationId
              ORDER BY event.createdAt DESC, event.id DESC
            ) AS rank
          FROM agent_tool_events event
          INNER JOIN agent_conversation_turns turn
            ON turn.id = event.conversationTurnId
          WHERE event.status IN ('rejected', 'failed')
        ),
        latest_activity AS (
          SELECT
            conversationId,
            MAX(createdAt) AS lastTurnAt
          FROM agent_conversation_turns
          GROUP BY conversationId
        )
        SELECT
          conversation.id AS id,
          conversation.contextEpoch AS contextEpoch,
          COALESCE(activity.lastTurnAt, conversation.updatedAt) AS updatedAt,
          staff.displayName AS staffName,
          conversation.selectedCustomerId AS selectedCustomerId,
          conversation.selectedFlockId AS selectedFlockId,
          conversation.selectedAuditId AS selectedAuditId,
          customer.name AS customerName,
          flock.flockId AS flockName,
          flock.sectorKey AS flockSectorKey,
          audit.date AS auditLabel,
          outbound.text AS latestReplyText,
          outbound.turnIndex AS latestTurnIndex,
          outbound.provider AS provider,
          outbound.model AS model,
          outbound.deliveryStatus AS deliveryStatus,
          error.resultJson AS latestToolResultJson,
          error.errorCreatedAt AS latestToolErrorAt
        FROM agent_conversations conversation
        INNER JOIN telegram_staff_links staff
          ON staff.id = conversation.staffLinkId
        LEFT JOIN customers customer
          ON customer.id = conversation.selectedCustomerId
        LEFT JOIN flocks flock
          ON flock.id = conversation.selectedFlockId
        LEFT JOIN audit_sessions audit
          ON audit.id = conversation.selectedAuditId
        LEFT JOIN ranked_outbound outbound
          ON outbound.conversationId = conversation.id
         AND outbound.rank = 1
        LEFT JOIN ranked_error error
          ON error.conversationId = conversation.id
         AND error.rank = 1
        LEFT JOIN latest_activity activity
          ON activity.conversationId = conversation.id
        ORDER BY
          COALESCE(activity.lastTurnAt, conversation.updatedAt) DESC,
          conversation.id ASC
        LIMIT ?
      ''',
      [limit],
    );
    return List.unmodifiable(rows.map(AgentConversationDiagnostic.fromMap));
  }
}
