import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/dashboard_action_model.dart';
import '../models/dashboard_intelligence_models.dart';
import '../providers/dashboard_provider.dart';

Future<void> showDashboardActionSheet(
  BuildContext context, {
  required DashboardFinding finding,
  DashboardActionModel? action,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<DashboardProvider>(),
      child: _DashboardActionSheet(finding: finding, action: action),
    ),
  );
}

class _DashboardActionSheet extends StatefulWidget {
  const _DashboardActionSheet({required this.finding, this.action});

  final DashboardFinding finding;
  final DashboardActionModel? action;

  @override
  State<_DashboardActionSheet> createState() => _DashboardActionSheetState();
}

class _DashboardActionSheetState extends State<_DashboardActionSheet> {
  late final TextEditingController _owner;
  late final TextEditingController _notes;
  late DashboardActionStatus _status;
  DateTime? _dueAt;
  bool _localizedInitialAdvice = false;

  @override
  void initState() {
    super.initState();
    _owner = TextEditingController(text: widget.action?.ownerName ?? '');
    _notes = TextEditingController(text: widget.action?.resolutionNotes ?? '');
    _status = widget.action?.status ?? DashboardActionStatus.open;
    _dueAt = widget.action?.dueAt;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localizedInitialAdvice || widget.action != null) return;
    _localizedInitialAdvice = true;
    final advice = widget.finding.advice;
    if (_notes.text.isEmpty && advice != null) {
      _notes.text = context.tr(advice);
    }
  }

  @override
  void dispose() {
    _owner.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSizes.spaceLg,
        AppSizes.spaceLg,
        AppSizes.spaceLg,
        MediaQuery.viewInsetsOf(context).bottom + AppSizes.spaceLg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr(
                widget.action == null ? 'Create action' : 'Update action',
              ),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.finding.metricLabel} · ${widget.finding.valueText}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSizes.spaceLg),
            TextField(
              controller: _owner,
              decoration: InputDecoration(labelText: context.tr('Owner')),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSizes.spaceMd),
            DropdownButtonFormField<DashboardActionStatus>(
              initialValue: _status,
              decoration: InputDecoration(labelText: context.tr('Status')),
              items: [
                for (final status in DashboardActionStatus.values)
                  DropdownMenuItem(
                    value: status,
                    child: Text(context.tr(_statusLabel(status))),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
            const SizedBox(height: AppSizes.spaceMd),
            OutlinedButton.icon(
              onPressed: _pickDueDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _dueAt == null
                    ? context.tr('Set due date')
                    : context.tr(
                        'Due ${_dueAt!.toLocal().toIso8601String().split('T').first}',
                      ),
              ),
            ),
            const SizedBox(height: AppSizes.spaceMd),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.tr(
                  _status == DashboardActionStatus.resolved
                      ? 'Resolution notes'
                      : 'Action notes',
                ),
              ),
            ),
            if (provider.actionError != null) ...[
              const SizedBox(height: AppSizes.spaceSm),
              Text(
                provider.actionError!,
                style: const TextStyle(color: AppColors.statusError),
              ),
            ],
            const SizedBox(height: AppSizes.spaceLg),
            FilledButton.icon(
              onPressed: provider.isSavingAction ? null : _save,
              icon: provider.isSavingAction
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                context.tr(
                  widget.action == null ? 'Create action' : 'Save action',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
      initialDate: _dueAt ?? now.add(const Duration(days: 3)),
    );
    if (date != null && mounted) setState(() => _dueAt = date);
  }

  Future<void> _save() async {
    final provider = context.read<DashboardProvider>();
    final action = widget.action;
    final saved = action == null
        ? await provider.createAction(
            widget.finding,
            ownerName: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
            dueAt: _dueAt,
            description: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          )
        : await provider.updateAction(
            action,
            status: _status,
            ownerName: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
            dueAt: _dueAt,
            resolutionNotes: _notes.text.trim().isEmpty
                ? null
                : _notes.text.trim(),
          );
    if (saved != null && mounted) Navigator.of(context).pop();
  }

  String _statusLabel(DashboardActionStatus status) => switch (status) {
    DashboardActionStatus.open => 'Action open',
    DashboardActionStatus.inProgress => 'In progress',
    DashboardActionStatus.resolved => 'Resolved',
    DashboardActionStatus.reopened => 'Reopened',
  };
}
