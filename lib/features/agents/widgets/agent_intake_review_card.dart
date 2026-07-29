import 'dart:convert';

import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/agent/station_adapter.dart';
import '../../../data/agent/station_registry.dart';
import '../../../data/models/agent_intake_models.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../widgets/app_card.dart';

class AgentIntakeReviewCard extends StatelessWidget {
  const AgentIntakeReviewCard({
    required this.details,
    required this.matchingAuditSessions,
    required this.isLoading,
    required this.onEditValue,
    required this.onApproveNew,
    required this.onAttach,
    required this.onReject,
    super.key,
  });

  final AgentIntakeDetails details;
  final List<AuditSessionModel> matchingAuditSessions;
  final bool isLoading;
  final Future<void> Function(String fieldKey, Object? value) onEditValue;
  final Future<void> Function() onApproveNew;
  final Future<void> Function(String auditSessionId) onAttach;
  final Future<void> Function(String reason) onReject;

  @override
  Widget build(BuildContext context) {
    final session = details.session;
    final schema = AgentStationRegistry.require(
      session.schemaKey,
      session.schemaVersion,
    );
    final calculations = AgentStationAdapter.calculate(
      schema,
      session.workingValues,
    );
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text(schema.names.en, style: AppTextStyles.sectionTitle),
              ),
              Text(
                'Schema v${session.schemaVersion}',
                style: AppTextStyles.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Wrap(
            spacing: AppSizes.spaceLg,
            runSpacing: AppSizes.spaceSm,
            children: [
              _ContextValue(
                label: 'Customer',
                value: session.customerName ?? 'Not available',
              ),
              _ContextValue(
                label: 'Flock',
                value: session.flockName ?? 'Not available',
              ),
              _ContextValue(
                label: 'Hatchery',
                value: session.hatcheryName ?? 'Not available',
              ),
              _ContextValue(label: 'Date', value: _day(session.auditDate)),
              _ContextValue(label: 'Scope', value: _scopeLabel(session)),
              _ContextValue(
                label: 'Conversation language',
                value: _languageLabel(session.language),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceLg),
          if (session.summary == null)
            Text(
              'The customer-confirmed summary is unavailable.',
              style: AppTextStyles.body.copyWith(color: AppColors.statusError),
            )
          else ...[
            Text(
              'Customer-confirmed summary v${session.summaryVersion}',
              style: AppTextStyles.subtitle,
            ),
            const SizedBox(height: AppSizes.spaceXs),
            Text(
              'Admin corrections are shown below; the original conversation '
              'and confirmed summary remain available as evidence.',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: AppSizes.spaceSm),
            for (final field in schema.fields)
              _MeasurementRow(
                field: field,
                value: session.workingValues[field.fieldKey],
                evidence: details.valueFor(field.fieldKey),
                isLoading: isLoading,
                onEdit: () => _editValue(
                  context,
                  field,
                  session.workingValues[field.fieldKey],
                ),
              ),
            if (schema.calculations.isNotEmpty) ...[
              const SizedBox(height: AppSizes.spaceMd),
              const Text('Calculated results', style: AppTextStyles.subtitle),
              const SizedBox(height: AppSizes.spaceXs),
              for (final calculation in schema.calculations)
                _CalculatedRow(
                  label: _titleFromKey(calculation.fieldKey),
                  value: calculations[calculation.fieldKey],
                  unit: calculation.unit,
                ),
            ],
          ],
          const SizedBox(height: AppSizes.spaceMd),
          ExpansionTile(
            key: const ValueKey('agent-intake-conversation-evidence'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
            title: const Text('Conversation evidence'),
            subtitle: Text(
              '${details.turns.length} messages',
              style: AppTextStyles.caption,
            ),
            children: details.turns.isEmpty
                ? const [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No messages'),
                    ),
                  ]
                : details.turns
                      .map(
                        (turn) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            turn.direction == AgentIntakeTurnDirection.inbound
                                ? Icons.person_outline
                                : Icons.smart_toy_outlined,
                            size: AppSizes.iconSm,
                          ),
                          title: Text(turn.text),
                          subtitle: Text(_timestamp(turn.createdAt)),
                        ),
                      )
                      .toList(growable: false),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceSm,
            children: [
              FilledButton.icon(
                key: const ValueKey('agent-intake-approve-new'),
                onPressed: isLoading || session.summary == null
                    ? null
                    : onApproveNew,
                icon: const Icon(Icons.add_task),
                label: const Text('Approve as new visit'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('agent-intake-attach'),
                onPressed:
                    isLoading ||
                        session.summary == null ||
                        matchingAuditSessions.isEmpty
                    ? null
                    : () => _chooseVisit(context),
                icon: const Icon(Icons.link),
                label: const Text('Attach to visit'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('agent-intake-reject'),
                onPressed: isLoading ? null : () => _reject(context),
                icon: const Icon(Icons.close),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editValue(
    BuildContext context,
    AgentStationField field,
    Object? initialValue,
  ) async {
    final value = await showDialog<Object?>(
      context: context,
      builder: (_) =>
          _EditAgentValueDialog(field: field, initialValue: initialValue),
    );
    if (value != null) await onEditValue(field.fieldKey, value);
  }

  Future<void> _chooseVisit(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Attach to matching visit'),
        children: matchingAuditSessions
            .map(
              (session) => SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(session.id),
                child: Text(
                  '${_day(session.date)} · ${_statusLabel(session.status)}',
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (selected != null) await onAttach(selected);
  }

  Future<void> _reject(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectAgentIntakeDialog(),
    );
    if (reason != null) await onReject(reason);
  }
}

class _EditAgentValueDialog extends StatefulWidget {
  const _EditAgentValueDialog({
    required this.field,
    required this.initialValue,
  });

  final AgentStationField field;
  final Object? initialValue;

  @override
  State<_EditAgentValueDialog> createState() => _EditAgentValueDialogState();
}

class _EditAgentValueDialogState extends State<_EditAgentValueDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: _editableText(widget.initialValue),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return AlertDialog(
      title: Text('Edit ${field.names.en}'),
      content: TextField(
        key: const ValueKey('agent-intake-edit-value-input'),
        controller: _controller,
        keyboardType: switch (field.type) {
          'integer' ||
          'number' => const TextInputType.numberWithOptions(decimal: true),
          _ => TextInputType.text,
        },
        maxLines: field.type.endsWith('_list') ? 5 : 1,
        decoration: InputDecoration(
          labelText: field.unit == 'none' ? 'Value' : field.unit,
          helperText: field.type.endsWith('_list')
              ? 'Enter a JSON list, for example [40, 41, 42]'
              : null,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('agent-intake-save-value'),
          onPressed: () {
            try {
              final parsed = _parseValue(field.type, _controller.text);
              Navigator.of(context).pop(parsed);
            } on FormatException {
              setState(() => _error = 'Enter a valid ${field.type} value.');
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _RejectAgentIntakeDialog extends StatefulWidget {
  const _RejectAgentIntakeDialog();

  @override
  State<_RejectAgentIntakeDialog> createState() =>
      _RejectAgentIntakeDialogState();
}

class _RejectAgentIntakeDialogState extends State<_RejectAgentIntakeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject intake'),
      content: TextField(
        key: const ValueKey('agent-intake-rejection-reason'),
        controller: _controller,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Rejection reason'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('agent-intake-confirm-rejection'),
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isEmpty) return;
            Navigator.of(context).pop(value);
          },
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

class _ContextValue extends StatelessWidget {
  const _ContextValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(value, style: AppTextStyles.body),
        ],
      ),
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    required this.field,
    required this.value,
    required this.evidence,
    required this.isLoading,
    required this.onEdit,
  });

  final AgentStationField field;
  final Object? value;
  final AgentIntakeValue? evidence;
  final bool isLoading;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final source = evidence;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceXs),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderDefault)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.names.en),
                if (source != null)
                  Text(
                    '${source.sourcePhrase} · '
                    '${(source.confidence * 100).toStringAsFixed(0)}%',
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Flexible(
            child: Text(
              _displayValue(value, field.unit),
              textAlign: TextAlign.end,
              style: AppTextStyles.subtitle,
            ),
          ),
          IconButton(
            key: ValueKey('agent-intake-edit-${field.fieldKey}'),
            tooltip: 'Edit',
            onPressed: isLoading ? null : onEdit,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: AppSizes.iconSm),
          ),
        ],
      ),
    );
  }
}

class _CalculatedRow extends StatelessWidget {
  const _CalculatedRow({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final Object? value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceXs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(_displayValue(value, unit), style: AppTextStyles.subtitle),
        ],
      ),
    );
  }
}

Object? _parseValue(String type, String source) {
  final text = source.trim();
  if (text.isEmpty) throw const FormatException();
  return switch (type) {
    'integer' => int.tryParse(text) ?? (throw const FormatException()),
    'number' => double.tryParse(text) ?? (throw const FormatException()),
    'boolean' => switch (text.toLowerCase()) {
      'true' || 'yes' || '1' => true,
      'false' || 'no' || '0' => false,
      _ => throw const FormatException(),
    },
    'number_list' => _parseNumberList(text),
    'object_list' => _parseObjectList(text),
    'string' => text,
    _ => throw const FormatException(),
  };
}

List<num> _parseNumberList(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! List ||
      decoded.any((item) => item is! num || !item.isFinite)) {
    throw const FormatException();
  }
  return decoded.cast<num>();
}

List<Map<String, Object?>> _parseObjectList(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! List || decoded.any((item) => item is! Map)) {
    throw const FormatException();
  }
  return decoded
      .cast<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

String _editableText(Object? value) {
  if (value is List || value is Map) return jsonEncode(value);
  return value?.toString() ?? '';
}

String _displayValue(Object? value, String unit) {
  final text = switch (value) {
    null => '—',
    double() => value.toStringAsFixed(1),
    List() => jsonEncode(value),
    Map() => jsonEncode(value),
    _ => value.toString(),
  };
  return unit == 'none' || unit.isEmpty ? text : '$text $unit';
}

String _scopeLabel(AgentIntakeSession session) {
  return switch (session.scope) {
    AgentIntakeScope.pool => 'Pool',
    AgentIntakeScope.house => 'House',
    AgentIntakeScope.setter => session.setterIdentity ?? 'Setter',
    AgentIntakeScope.hatcher => session.hatcherIdentity ?? 'Hatcher',
    AgentIntakeScope.setterHatcher =>
      '${session.setterIdentity ?? 'Setter'} / '
          '${session.hatcherIdentity ?? 'Hatcher'}',
    AgentIntakeScope.trolley => 'Trolley',
    AgentIntakeScope.tray => 'Tray',
    null => 'Not available',
  };
}

String _languageLabel(AgentIntakeLanguage language) {
  return switch (language) {
    AgentIntakeLanguage.english => 'English',
    AgentIntakeLanguage.arabic => 'Arabic',
    AgentIntakeLanguage.mixed => 'Arabic and English',
  };
}

String _titleFromKey(String key) {
  final words = key.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return words.isEmpty
      ? words
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

String _statusLabel(String status) {
  return status
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String _day(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _timestamp(DateTime value) {
  final utc = value.toUtc();
  return '${_day(utc)} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')} UTC';
}
