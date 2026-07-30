import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/agent_diagnostic_models.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/hatchery_agent_models.dart';
import '../../../data/repositories/hatchery_agent_repository.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../widgets/app_card.dart';
import '../providers/agent_monitor_provider.dart';
import '../widgets/agent_submission_card.dart';
import '../widgets/hatchery_draft_row_card.dart';
import '../widgets/agent_intake_review_card.dart';

class AgentMonitorScreen extends StatefulWidget {
  const AgentMonitorScreen({super.key});

  @override
  State<AgentMonitorScreen> createState() => _AgentMonitorScreenState();
}

class _AgentMonitorScreenState extends State<AgentMonitorScreen> {
  bool _loadRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadRequested) return;
    final user = context.watch<AuthProvider>().user;
    final provider = context.read<AgentMonitorProvider>();
    if (user?.isApproved != true ||
        user?.isAdmin != true ||
        !provider.canAccessMonitor) {
      return;
    }
    if (provider.hasLoaded) {
      _loadRequested = true;
      return;
    }
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AgentMonitorProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AgentMonitorProvider, AuthProvider>(
      builder: (context, provider, auth, _) {
        final hasAdminAccess =
            auth.user?.isApproved == true &&
            auth.user?.isAdmin == true &&
            provider.canAccessMonitor;
        if (!hasAdminAccess) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            appBar: GradientAppBar(title: 'Agent Monitor'),
            body: Center(child: Text('Administrator access is required.')),
          );
        }
        final enabled = provider.settings.telegramEnabled;
        final adminUserId = auth.user!.id;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: GradientAppBar(
            title: 'Agent Monitor',
            actions: [
              IconButton(
                tooltip: context.tr('Refresh'),
                onPressed: provider.isLoading ? null : provider.load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                key: const ValueKey('telegram-agent-toggle'),
                tooltip: context.tr(
                  enabled ? 'Pause Telegram agent' : 'Resume Telegram agent',
                ),
                onPressed: provider.isLoading
                    ? null
                    : () => provider.setTelegramEnabled(!enabled),
                icon: Icon(
                  enabled ? Icons.pause_circle_outline : Icons.play_circle,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              _AgentStateBar(enabled: enabled),
              if (provider.isLoading)
                const LinearProgressIndicator(minHeight: 2),
              if (provider.error != null)
                _ErrorBanner(
                  message: provider.error!,
                  onRetry: provider.isLoading ? null : provider.load,
                ),
              _AgentHealthPanel(
                health: provider.health,
                conversations: provider.conversationDiagnostics,
              ),
              if (provider.pendingStaffLinks.isNotEmpty)
                _PendingStaffAccessPanel(
                  links: provider.pendingStaffLinks,
                  isLoading: provider.isLoading,
                  onApprove: (link) =>
                      _showStaffAssignment(context, provider, link),
                  onReject: (link) => provider.revokeStaffLink(link.id),
                ),
              if (provider.staffLinks.isNotEmpty)
                _StaffAccessPanel(
                  links: provider.staffLinks,
                  customers: provider.linkCatalog.customers,
                  isLoading: provider.isLoading,
                  onEdit: (link) =>
                      _showStaffAssignment(context, provider, link),
                  onRevoke: (link) => provider.revokeStaffLink(link.id),
                ),
              Expanded(
                child: _MonitorWorkspace(
                  provider: provider,
                  adminUserId: adminUserId,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showStaffAssignment(
    BuildContext context,
    AgentMonitorProvider provider,
    TelegramStaffLink link,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StaffAssignmentSheet(
        link: link,
        customers: provider.linkCatalog.customers,
        provider: provider,
      ),
    );
  }
}

class _AgentHealthPanel extends StatelessWidget {
  const _AgentHealthPanel({required this.health, required this.conversations});

  final AgentHealthSnapshot health;
  final List<AgentConversationDiagnostic> conversations;

  @override
  Widget build(BuildContext context) {
    final latest = conversations.firstOrNull;
    return AppCard(
      key: const ValueKey('agent-health-panel'),
      margin: const EdgeInsets.fromLTRB(
        AppSizes.spaceMd,
        AppSizes.spaceMd,
        AppSizes.spaceMd,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                health.hasErrors
                    ? Icons.health_and_safety_outlined
                    : Icons.health_and_safety,
                color: health.hasErrors
                    ? AppColors.statusWarning
                    : AppColors.statusGood,
              ),
              const SizedBox(width: AppSizes.spaceSm),
              const Expanded(
                child: Text('Agent health', style: AppTextStyles.sectionTitle),
              ),
              Text(
                health.hasErrors ? 'Needs attention' : 'Healthy',
                style: AppTextStyles.caption.copyWith(
                  color: health.hasErrors
                      ? AppColors.statusWarning
                      : AppColors.statusGood,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceXs,
            children: [
              _HealthMetric(
                label: 'Conversations',
                value: health.conversationCount,
              ),
              _HealthMetric(
                label: 'Delivery errors',
                value: health.failedDeliveryCount,
                isError: health.failedDeliveryCount > 0,
              ),
              _HealthMetric(
                label: 'Pending replies',
                value: health.pendingDeliveryCount,
              ),
              _HealthMetric(
                label: 'Tool errors',
                value: health.failedToolCount,
                isError: health.failedToolCount > 0,
              ),
              _HealthMetric(
                label: 'Flocks missing sector',
                value: health.unassignedFlockCount,
                isError: health.unassignedFlockCount > 0,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          if (latest == null)
            Text(
              'No synchronized conversations yet.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            _LatestConversationContext(diagnostic: latest),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            'Send /new in Telegram to clear the selected context and start '
            'a new conversation. Earlier evidence is retained.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({
    required this.label,
    required this.value,
    this.isError = false,
  });

  final String label;
  final int value;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.statusError : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceXs,
      ),
      decoration: BoxDecoration(
        color: isError ? AppColors.statusErrorBg : AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Text(
        '$label: $value',
        style: AppTextStyles.caption.copyWith(color: color),
      ),
    );
  }
}

class _LatestConversationContext extends StatelessWidget {
  const _LatestConversationContext({required this.diagnostic});

  final AgentConversationDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final model = [
      diagnostic.provider,
      diagnostic.model,
    ].whereType<String>().join(' / ');
    return Container(
      key: const ValueKey('agent-latest-context'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            diagnostic.staffName ?? 'Unknown Telegram user',
            style: AppTextStyles.subtitle,
          ),
          Text(
            'Selected customer: ${_contextValue(diagnostic.selectedCustomerId, diagnostic.customerName, 'customer')}',
            style: AppTextStyles.caption,
          ),
          Text(
            'Selected flock: ${_contextValue(diagnostic.selectedFlockId, diagnostic.flockName, 'flock')}',
            style: AppTextStyles.caption,
          ),
          Text(
            'Selected audit: ${_contextValue(diagnostic.selectedAuditId, diagnostic.auditLabel, 'audit')}',
            style: AppTextStyles.caption,
          ),
          if (diagnostic.hasUnassignedSector)
            Text(
              'This flock has no sector assignment. Assign a sector before '
              'starting station intake.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.statusError,
              ),
            ),
          Text(
            diagnostic.latestTurnIndex == null
                ? 'No assistant reply recorded.'
                : 'Latest reply #${diagnostic.latestTurnIndex}: '
                      '${model.isEmpty ? 'model metadata unavailable' : model}'
                      ' · ${diagnostic.deliveryStatus ?? 'delivery unknown'}',
            style: AppTextStyles.caption,
          ),
          if (diagnostic.latestToolErrorCode case final code?)
            Text(
              'Latest agent error: $code'
              '${diagnostic.latestToolErrorAt == null ? '' : ' · ${_utcMinute(diagnostic.latestToolErrorAt!)}'}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.statusError,
              ),
            ),
        ],
      ),
    );
  }

  String _contextValue(String? selectedId, String? label, String kind) {
    if (selectedId == null) return 'Not selected';
    return label ?? 'Missing $kind record';
  }

  String _utcMinute(DateTime value) {
    final iso = value.toUtc().toIso8601String();
    return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
  }
}

class _AgentStateBar extends StatelessWidget {
  const _AgentStateBar({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.statusGood : AppColors.statusWarning;
    final background = enabled
        ? AppColors.statusGoodBg
        : AppColors.statusWarningBg;
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceLg,
          vertical: AppSizes.spaceSm,
        ),
        color: background,
        child: Row(
          children: [
            Icon(
              enabled ? Icons.telegram : Icons.pause_circle_outline,
              color: color,
              size: AppSizes.iconSm,
            ),
            const SizedBox(width: AppSizes.spaceSm),
            Text(
              enabled ? 'Telegram running' : 'Telegram paused',
              style: AppTextStyles.subtitle.copyWith(color: color),
            ),
            if (constraints.maxWidth >= 600) ...[
              const Spacer(),
              Text(
                enabled
                    ? 'New submissions are accepted'
                    : 'New submissions paused',
                style: AppTextStyles.caption.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.statusErrorBg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.statusError,
            size: AppSizes.iconSm,
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body.copyWith(color: AppColors.statusError),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PendingStaffAccessPanel extends StatelessWidget {
  const _PendingStaffAccessPanel({
    required this.links,
    required this.isLoading,
    required this.onApprove,
    required this.onReject,
  });

  final List<TelegramStaffLink> links;
  final bool isLoading;
  final Future<void> Function(TelegramStaffLink link) onApprove;
  final Future<void> Function(TelegramStaffLink link) onReject;

  @override
  Widget build(BuildContext context) {
    final requestLabel = links.length == 1
        ? '1 request'
        : '${links.length} requests';
    return AppCard(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.spaceMd,
        AppSizes.spaceMd,
        AppSizes.spaceMd,
        0,
      ),
      color: AppColors.statusWarningBg,
      border: Border.all(color: AppColors.statusWarning.withValues(alpha: 0.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_add_alt_1,
                color: AppColors.statusWarning,
              ),
              const SizedBox(width: AppSizes.spaceSm),
              const Expanded(
                child: Text(
                  'Pending Telegram access',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              Text(requestLabel, style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            'Approve new Telegram staff before they can send hatchery data.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          ...links.map(
            (link) => _PendingStaffAccessTile(
              link: link,
              isLoading: isLoading,
              onApprove: () => onApprove(link),
              onReject: () => onReject(link),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingStaffAccessTile extends StatelessWidget {
  const _PendingStaffAccessTile({
    required this.link,
    required this.isLoading,
    required this.onApprove,
    required this.onReject,
  });

  final TelegramStaffLink link;
  final bool isLoading;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final displayName = _staffDisplayName(link);
    final username = link.username?.trim();
    final requestedAt = link.updatedAt ?? link.createdAt;
    return Container(
      margin: const EdgeInsets.only(top: AppSizes.spaceXs),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            foregroundColor: AppColors.primary,
            child: const Icon(Icons.telegram),
          ),
          const SizedBox(width: AppSizes.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: AppTextStyles.subtitle),
                if (username != null && username.isNotEmpty)
                  Text('@$username', style: AppTextStyles.caption),
                Text(
                  'Telegram ID: ${link.telegramUserId}',
                  style: AppTextStyles.caption,
                ),
                if (link.telegramChatId case final chatId?)
                  Text('Chat ID: $chatId', style: AppTextStyles.caption),
                if (requestedAt != null)
                  Text(
                    'Requested: ${_formatTimestamp(requestedAt)}',
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Wrap(
            spacing: AppSizes.spaceXs,
            runSpacing: AppSizes.spaceXs,
            children: [
              FilledButton.icon(
                key: ValueKey('agent-staff-approve-${link.id}'),
                onPressed: isLoading ? null : onApprove,
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                key: ValueKey('agent-staff-reject-${link.id}'),
                onPressed: isLoading ? null : onReject,
                icon: const Icon(Icons.block),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaffAssignmentSheet extends StatefulWidget {
  const _StaffAssignmentSheet({
    required this.link,
    required this.customers,
    required this.provider,
  });

  final TelegramStaffLink link;
  final List<CustomerModel> customers;
  final AgentMonitorProvider provider;

  @override
  State<_StaffAssignmentSheet> createState() => _StaffAssignmentSheetState();
}

class _StaffAssignmentSheetState extends State<_StaffAssignmentSheet> {
  late TelegramAgentAccessRole _accessRole;
  String? _customerId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _accessRole = widget.link.status == TelegramStaffLinkStatus.allowed
        ? widget.link.accessRole
        : TelegramAgentAccessRole.customer;
    final assignedCustomerId = widget.link.customerId;
    _customerId =
        assignedCustomerId != null &&
            widget.customers.any(
              (customer) => customer.id == assignedCustomerId,
            )
        ? assignedCustomerId
        : null;
  }

  bool get _canSubmit =>
      _accessRole == TelegramAgentAccessRole.admin || _customerId != null;

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() => _submitting = true);
    await widget.provider.approveStaffLink(
      linkId: widget.link.id,
      accessRole: _accessRole,
      customerId: _accessRole == TelegramAgentAccessRole.customer
          ? _customerId
          : null,
    );
    if (!mounted) return;
    if (widget.provider.error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSizes.spaceLg,
        AppSizes.spaceLg,
        AppSizes.spaceLg,
        AppSizes.spaceLg + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_accounts, color: AppColors.primary),
              const SizedBox(width: AppSizes.spaceSm),
              const Expanded(
                child: Text(
                  'Assign Telegram access',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(_staffDisplayName(widget.link), style: AppTextStyles.subtitle),
          const SizedBox(height: AppSizes.spaceLg),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceSm,
            children: [
              ChoiceChip(
                key: const ValueKey('agent-staff-role-customer'),
                selected: _accessRole == TelegramAgentAccessRole.customer,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        _accessRole = TelegramAgentAccessRole.customer;
                      }),
                avatar: const Icon(Icons.business, size: 18),
                label: const Text('Customer access'),
              ),
              ChoiceChip(
                key: const ValueKey('agent-staff-role-admin'),
                selected: _accessRole == TelegramAgentAccessRole.admin,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        _accessRole = TelegramAgentAccessRole.admin;
                        _customerId = null;
                      }),
                avatar: const Icon(Icons.admin_panel_settings, size: 18),
                label: const Text('Agent admin access'),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            _accessRole == TelegramAgentAccessRole.customer
                ? context.tr(
                    'The agent can read and collect data for one customer.',
                  )
                : context.tr(
                    'The agent can read and collect data for all customers.',
                  ),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (_accessRole == TelegramAgentAccessRole.customer) ...[
            const SizedBox(height: AppSizes.spaceLg),
            DropdownButtonFormField<String>(
              key: const ValueKey('agent-staff-customer-dropdown'),
              initialValue: _customerId,
              decoration: InputDecoration(
                labelText: context.tr('Select customer'),
                border: const OutlineInputBorder(),
              ),
              items: widget.customers
                  .map(
                    (customer) => DropdownMenuItem(
                      value: customer.id,
                      child: Text(customer.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _customerId = value),
            ),
          ],
          const SizedBox(height: AppSizes.spaceLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              FilledButton.icon(
                key: const ValueKey('agent-staff-confirm-assignment'),
                onPressed: _canSubmit && !_submitting ? _submit : null,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Allow access'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaffAccessPanel extends StatelessWidget {
  const _StaffAccessPanel({
    required this.links,
    required this.customers,
    required this.isLoading,
    required this.onEdit,
    required this.onRevoke,
  });

  final List<TelegramStaffLink> links;
  final List<CustomerModel> customers;
  final bool isLoading;
  final Future<void> Function(TelegramStaffLink link) onEdit;
  final Future<void> Function(TelegramStaffLink link) onRevoke;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.spaceMd,
        AppSizes.spaceMd,
        AppSizes.spaceMd,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.manage_accounts, color: AppColors.primary),
              SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text(
                  'Telegram users',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          ...links.map(
            (link) => _StaffAccessTile(
              link: link,
              scopeLabel: _scopeLabel(context, link),
              isLoading: isLoading,
              onEdit: () => onEdit(link),
              onRevoke: () => onRevoke(link),
            ),
          ),
        ],
      ),
    );
  }

  String _scopeLabel(BuildContext context, TelegramStaffLink link) {
    if (link.accessRole == TelegramAgentAccessRole.admin) {
      return context.tr('Agent admin access · All customers');
    }
    final customerName = customers
        .where((customer) => customer.id == link.customerId)
        .map((customer) => customer.name)
        .firstOrNull;
    return '${context.tr('Customer access')} · '
        '${customerName ?? context.tr('Unknown customer')}';
  }
}

class _StaffAccessTile extends StatelessWidget {
  const _StaffAccessTile({
    required this.link,
    required this.scopeLabel,
    required this.isLoading,
    required this.onEdit,
    required this.onRevoke,
  });

  final TelegramStaffLink link;
  final String scopeLabel;
  final bool isLoading;
  final Future<void> Function() onEdit;
  final Future<void> Function() onRevoke;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.telegram)),
      title: Text(_staffDisplayName(link)),
      subtitle: Text(scopeLabel),
      trailing: Wrap(
        spacing: AppSizes.spaceXs,
        children: [
          IconButton(
            key: ValueKey('agent-staff-edit-${link.id}'),
            tooltip: context.tr('Change scope'),
            onPressed: isLoading ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey('agent-staff-revoke-${link.id}'),
            tooltip: context.tr('Revoke access'),
            onPressed: isLoading ? null : onRevoke,
            icon: const Icon(
              Icons.person_remove_outlined,
              color: AppColors.statusError,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorWorkspace extends StatelessWidget {
  const _MonitorWorkspace({required this.provider, this.adminUserId});

  final AgentMonitorProvider provider;
  final String? adminUserId;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading &&
        provider.batches.isEmpty &&
        provider.intakes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.batches.isEmpty && provider.intakes.isEmpty) {
      return const _EmptyMonitor();
    }

    if (provider.intakes.isNotEmpty) {
      final intakeWorkspace = _IntakeWorkspace(provider: provider);
      if (provider.batches.isEmpty) return intakeWorkspace;
      return Column(
        children: [
          Expanded(child: intakeWorkspace),
          const Divider(height: 1),
          Expanded(
            child: _HatcheryWorkspace(
              provider: provider,
              adminUserId: adminUserId,
            ),
          ),
        ],
      );
    }

    return _HatcheryWorkspace(provider: provider, adminUserId: adminUserId);
  }
}

class _IntakeWorkspace extends StatelessWidget {
  const _IntakeWorkspace({required this.provider});

  final AgentMonitorProvider provider;

  @override
  Widget build(BuildContext context) {
    final details = provider.selectedIntake;
    return SingleChildScrollView(
      key: const ValueKey('agent-intake-review-workspace'),
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Conversational station intakes',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              if (provider.intakes.length > 1)
                DropdownButton<String>(
                  value: details?.session.id,
                  items: provider.intakes
                      .map(
                        (intake) => DropdownMenuItem(
                          value: intake.id,
                          child: Text(
                            '${intake.customerName ?? 'Customer'} · '
                            '${_dateInput(intake.auditDate)}',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: provider.isLoading
                      ? null
                      : (id) {
                          if (id != null) provider.selectIntake(id);
                        },
                ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          if (details == null)
            const Text('Select an intake to review')
          else
            AgentIntakeReviewCard(
              details: details,
              matchingAuditSessions: provider.matchingAuditSessions,
              isLoading: provider.isLoading,
              onEditValue: provider.saveIntakeValue,
              onApproveNew: provider.approveIntake,
              onAttach: (sessionId) =>
                  provider.approveIntake(targetSessionId: sessionId),
              onReject: provider.rejectIntake,
            ),
        ],
      ),
    );
  }
}

class _HatcheryWorkspace extends StatelessWidget {
  const _HatcheryWorkspace({required this.provider, this.adminUserId});

  final AgentMonitorProvider provider;
  final String? adminUserId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 960) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 340,
                child: _BatchList(
                  provider: provider,
                  padding: const EdgeInsets.all(AppSizes.spaceMd),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _BatchDetails(
                  details: provider.selectedBatch,
                  provider: provider,
                  adminUserId: adminUserId,
                ),
              ),
            ],
          );
        }

        final listHeight = (constraints.maxHeight * 0.4).clamp(72.0, 230.0);
        return Column(
          children: [
            SizedBox(
              height: listHeight,
              child: _BatchList(
                provider: provider,
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.spaceMd,
                  AppSizes.spaceMd,
                  AppSizes.spaceMd,
                  AppSizes.spaceSm,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _BatchDetails(
                details: provider.selectedBatch,
                provider: provider,
                adminUserId: adminUserId,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BatchList extends StatelessWidget {
  const _BatchList({required this.provider, required this.padding});

  final AgentMonitorProvider provider;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final selectedId = provider.selectedBatch?.batch.id;
    return ListView.builder(
      key: const ValueKey('agent-batch-list'),
      padding: padding,
      itemCount: provider.batches.length,
      itemBuilder: (context, index) {
        final summary = provider.batches[index];
        return AgentSubmissionCard(
          summary: summary,
          isSelected: summary.id == selectedId,
          onTap: () => provider.selectBatch(summary.id),
        );
      },
    );
  }
}

class _BatchDetails extends StatelessWidget {
  const _BatchDetails({
    required this.details,
    required this.provider,
    this.adminUserId,
  });

  final HatcheryDraftBatchDetails? details;
  final AgentMonitorProvider provider;
  final String? adminUserId;

  @override
  Widget build(BuildContext context) {
    final value = details;
    if (value == null) {
      return const Center(child: Text('Select a submission to review'));
    }

    return SingleChildScrollView(
      key: const ValueKey('agent-batch-details'),
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SourceEvidenceCard(details: value),
          if (value.questions.isNotEmpty) ...[
            const SizedBox(height: AppSizes.spaceMd),
            _QuestionsCard(questions: value.questions),
          ],
          const SizedBox(height: AppSizes.spaceLg),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Extracted rows',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              Text('${value.rows.length} rows', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          ...value.rows.map(
            (row) => HatcheryDraftRowCard(
              row: row,
              onEdit: adminUserId == null ? null : () => _editRow(context, row),
              onApprove: adminUserId == null
                  ? null
                  : () => provider.approveRow(row.id, adminUserId!),
              onReject: adminUserId == null
                  ? null
                  : () => _rejectRow(context, row),
            ),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          _AuditHistoryCard(events: value.events),
          const SizedBox(height: AppSizes.spaceXl),
        ],
      ),
    );
  }

  Future<void> _editRow(BuildContext context, HatcheryDraftRow row) async {
    final edited = await showDialog<HatcheryDraftRow>(
      context: context,
      builder: (_) =>
          _EditDraftRowDialog(row: row, linkCatalog: provider.linkCatalog),
    );
    if (edited != null) {
      await provider.saveRowEdit(edited);
    }
  }

  Future<void> _rejectRow(BuildContext context, HatcheryDraftRow row) async {
    final decision = await showDialog<_RejectRowDecision>(
      context: context,
      builder: (_) => const _RejectDraftRowDialog(),
    );
    final reviewerId = adminUserId;
    if (decision != null && reviewerId != null) {
      await provider.rejectRow(row.id, reviewerId, reason: decision.reason);
    }
  }
}

class _RejectRowDecision {
  const _RejectRowDecision(this.reason);

  final String? reason;
}

class _RejectDraftRowDialog extends StatefulWidget {
  const _RejectDraftRowDialog();

  @override
  State<_RejectDraftRowDialog> createState() => _RejectDraftRowDialogState();
}

class _RejectDraftRowDialogState extends State<_RejectDraftRowDialog> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject row'),
      content: TextField(
        key: const ValueKey('agent-rejection-reason'),
        controller: _reasonController,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Rejection reason (optional)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('agent-confirm-rejection'),
          onPressed: () {
            final reason = _reasonController.text.trim();
            Navigator.of(
              context,
            ).pop(_RejectRowDecision(reason.isEmpty ? null : reason));
          },
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

enum _DraftInputKind { text, integer, decimal, date }

class _DraftFieldSpec {
  const _DraftFieldSpec({
    required this.keyName,
    required this.label,
    this.kind = _DraftInputKind.text,
    this.widgetKey,
  });

  final String keyName;
  final String label;
  final _DraftInputKind kind;
  final String? widgetKey;
}

const _draftFieldSpecs = <_DraftFieldSpec>[
  _DraftFieldSpec(
    keyName: 'stationName',
    label: 'Station',
    widgetKey: 'agent-edit-station-name',
  ),
  _DraftFieldSpec(keyName: 'breed', label: 'Breed'),
  _DraftFieldSpec(
    keyName: 'eggsPlaced',
    label: 'Eggs placed',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'productionDate',
    label: 'Production date',
    kind: _DraftInputKind.date,
  ),
  _DraftFieldSpec(
    keyName: 'placementDate',
    label: 'Placement date',
    kind: _DraftInputKind.date,
  ),
  _DraftFieldSpec(
    keyName: 'eggWeightG',
    label: 'Egg weight',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(
    keyName: 'fertilityPct',
    label: 'Fertility',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(
    keyName: 'transferWeightG',
    label: 'Transfer weight',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(keyName: 'setterNumber', label: 'Setter'),
  _DraftFieldSpec(keyName: 'hatcherNumber', label: 'Hatcher'),
  _DraftFieldSpec(
    keyName: 'hatchDate',
    label: 'Hatch date',
    kind: _DraftInputKind.date,
    widgetKey: 'agent-edit-hatch-date',
  ),
  _DraftFieldSpec(
    keyName: 'healthyChicks',
    label: 'Healthy chicks',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'secondGradeChicks',
    label: 'Second grade',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'condemnedChicks',
    label: 'Condemned',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'totalProduction',
    label: 'Total production',
    kind: _DraftInputKind.integer,
  ),
  _DraftFieldSpec(
    keyName: 'hatchabilityPct',
    label: 'Hatchability',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(
    keyName: 'confidencePct',
    label: 'Confidence',
    kind: _DraftInputKind.decimal,
  ),
  _DraftFieldSpec(
    keyName: 'proposedFlockAgeWeeks',
    label: 'Proposed flock age',
    kind: _DraftInputKind.integer,
  ),
];

class _EditDraftRowDialog extends StatefulWidget {
  const _EditDraftRowDialog({required this.row, required this.linkCatalog});

  final HatcheryDraftRow row;
  final HatcheryAgentLinkCatalog linkCatalog;

  @override
  State<_EditDraftRowDialog> createState() => _EditDraftRowDialogState();
}

class _EditDraftRowDialogState extends State<_EditDraftRowDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  String? _customerId;
  String? _flockId;
  String? _hatcheryId;

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    _customerId = _initialCustomerId(row, widget.linkCatalog);
    _flockId = _initialFlockId(row, widget.linkCatalog, _customerId);
    _hatcheryId = _initialHatcheryId(row, widget.linkCatalog, _customerId);
    _controllers = {
      'stationName': _controller(row.stationName),
      'breed': _controller(row.breed),
      'eggsPlaced': _controller(row.eggsPlaced),
      'productionDate': _controller(_dateInput(row.productionDate)),
      'placementDate': _controller(_dateInput(row.placementDate)),
      'eggWeightG': _controller(row.eggWeightG),
      'fertilityPct': _controller(row.fertilityPct),
      'transferWeightG': _controller(row.transferWeightG),
      'setterNumber': _controller(row.setterNumber),
      'hatcherNumber': _controller(row.hatcherNumber),
      'hatchDate': _controller(_dateInput(row.hatchDate)),
      'healthyChicks': _controller(row.healthyChicks),
      'secondGradeChicks': _controller(row.secondGradeChicks),
      'condemnedChicks': _controller(row.condemnedChicks),
      'totalProduction': _controller(row.totalProduction),
      'hatchabilityPct': _controller(row.hatchabilityPct),
      'confidencePct': _controller(row.confidencePct),
      'proposedFlockAgeWeeks': _controller(row.proposedFlockAgeWeeks),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit row'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Use YYYY-MM-DD for dates.'),
                const SizedBox(height: AppSizes.spaceMd),
                _buildCustomerSelector(),
                const SizedBox(height: AppSizes.spaceSm),
                _buildFlockSelector(),
                const SizedBox(height: AppSizes.spaceSm),
                _buildHatcherySelector(),
                const SizedBox(height: AppSizes.spaceSm),
                for (final field in _draftFieldSpecs) ...[
                  TextFormField(
                    key: field.widgetKey == null
                        ? null
                        : ValueKey(field.widgetKey!),
                    controller: _controllers[field.keyName],
                    keyboardType: _keyboardType(field.kind),
                    decoration: InputDecoration(labelText: field.label),
                    validator: (value) =>
                        _validateField(context, field.kind, value),
                  ),
                  const SizedBox(height: AppSizes.spaceSm),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('agent-save-row-edit'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildCustomerSelector() {
    final customerItems = widget.linkCatalog.customers
        .map(
          (customer) => DropdownMenuItem(
            value: customer.id,
            child: Text(customer.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(growable: true);
    if (_customerId != null &&
        _customerById(widget.linkCatalog, _customerId) == null) {
      customerItems.insert(
        0,
        DropdownMenuItem(
          value: _customerId,
          child: Text(
            '${widget.row.customerName ?? context.tr('Existing customer')} · '
            '${context.tr('Unavailable locally')}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: const ValueKey('agent-edit-customer-selector'),
      initialValue: _customerId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Customer',
        helperText: _customerId == null && widget.row.customerName != null
            ? '${context.tr('Extracted')}: ${widget.row.customerName}'
            : null,
      ),
      hint: const Text('Select customer'),
      items: customerItems,
      onChanged: (customerId) {
        setState(() {
          _customerId = customerId;
          _flockId = _matchingFlockId(
            widget.row.flockName,
            widget.linkCatalog,
            customerId,
          );
          final hatcheries = widget.linkCatalog.hatcheriesForCustomer(
            customerId,
          );
          _hatcheryId = hatcheries.length == 1 ? hatcheries.single.id : null;
        });
      },
    );
  }

  Widget _buildFlockSelector() {
    final flocks = widget.linkCatalog.flocksForCustomer(_customerId);
    final flockItems = flocks
        .map(
          (flock) => DropdownMenuItem(
            value: flock.id,
            child: Text(
              '${flock.flockId} · ${flock.breed}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(growable: true);
    if (_flockId != null && _flockById(widget.linkCatalog, _flockId) == null) {
      flockItems.insert(
        0,
        DropdownMenuItem(
          value: _flockId,
          child: Text(
            '${widget.row.flockName ?? context.tr('Existing flock')} · '
            '${context.tr('Unavailable locally')}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: const ValueKey('agent-edit-flock-selector'),
      initialValue: _flockId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Flock',
        helperText: _flockId == null && widget.row.flockName != null
            ? '${context.tr('Extracted')}: ${widget.row.flockName}'
            : null,
      ),
      hint: Text(
        _customerId == null ? 'Select customer first' : 'Select flock',
      ),
      items: flockItems,
      onChanged: _customerId == null
          ? null
          : (flockId) => setState(() => _flockId = flockId),
    );
  }

  Widget _buildHatcherySelector() {
    final hatcheries = widget.linkCatalog.hatcheriesForCustomer(_customerId);
    const noHatchery = '';
    final hatcheryItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: noHatchery,
        child: Text('No hatchery selected'),
      ),
      ...hatcheries.map(
        (hatchery) => DropdownMenuItem(
          value: hatchery.id,
          child: Text(hatchery.name, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
    if (_hatcheryId != null &&
        !hatcheries.any((hatchery) => hatchery.id == _hatcheryId)) {
      hatcheryItems.insert(
        1,
        DropdownMenuItem(
          value: _hatcheryId,
          child: Text(
            '${context.tr('Existing hatchery')} · '
            '${context.tr('Unavailable locally')}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: const ValueKey('agent-edit-hatchery-selector'),
      initialValue: _hatcheryId ?? noHatchery,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Hatchery'),
      items: hatcheryItems,
      onChanged: _customerId == null
          ? null
          : (hatcheryId) => setState(
              () => _hatcheryId = hatcheryId == noHatchery ? null : hatcheryId,
            ),
    );
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    final row = widget.row;
    final customer = _customerById(widget.linkCatalog, _customerId);
    final flock = _flockById(widget.linkCatalog, _flockId);
    Navigator.of(context).pop(
      HatcheryDraftRow(
        id: row.id,
        batchId: row.batchId,
        rowOrdinal: row.rowOrdinal,
        status: row.status,
        customerId: _customerId,
        customerName: customer?.name ?? row.customerName,
        flockId: _flockId,
        flockName: flock?.flockId ?? row.flockName,
        hatcheryId: _hatcheryId,
        stationName: _textValue('stationName'),
        breed: _textValue('breed'),
        eggsPlaced: _intValue('eggsPlaced'),
        productionDate: _dateValue('productionDate'),
        placementDate: _dateValue('placementDate'),
        eggWeightG: _doubleValue('eggWeightG'),
        fertilityPct: _doubleValue('fertilityPct'),
        transferWeightG: _doubleValue('transferWeightG'),
        setterNumber: _textValue('setterNumber'),
        hatcherNumber: _textValue('hatcherNumber'),
        hatchDate: _dateValue('hatchDate'),
        healthyChicks: _intValue('healthyChicks'),
        secondGradeChicks: _intValue('secondGradeChicks'),
        condemnedChicks: _intValue('condemnedChicks'),
        totalProduction: _intValue('totalProduction'),
        hatchabilityPct: _doubleValue('hatchabilityPct'),
        confidencePct: _doubleValue('confidencePct'),
        extractionJson: row.extractionJson,
        warningsJson: row.warningsJson,
        proposedFlockAgeWeeks: _intValue('proposedFlockAgeWeeks'),
        approvedRecordId: row.approvedRecordId,
        reviewedBy: row.reviewedBy,
        reviewedAt: row.reviewedAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      ),
    );
  }

  String? _textValue(String key) {
    final value = _controllers[key]!.text.trim();
    return value.isEmpty ? null : value;
  }

  int? _intValue(String key) => int.tryParse(_controllers[key]!.text.trim());

  double? _doubleValue(String key) {
    return double.tryParse(_controllers[key]!.text.trim());
  }

  DateTime? _dateValue(String key) {
    return _parseDateInput(_controllers[key]!.text);
  }
}

String? _initialCustomerId(
  HatcheryDraftRow row,
  HatcheryAgentLinkCatalog catalog,
) {
  if (row.customerId != null) {
    return row.customerId;
  }
  final matches = catalog.customers
      .where(
        (customer) =>
            _normalizedName(customer.name) == _normalizedName(row.customerName),
      )
      .toList(growable: false);
  return matches.length == 1 ? matches.single.id : null;
}

String? _initialFlockId(
  HatcheryDraftRow row,
  HatcheryAgentLinkCatalog catalog,
  String? customerId,
) {
  if (row.flockId != null) return row.flockId;
  return _matchingFlockId(row.flockName, catalog, customerId);
}

String? _matchingFlockId(
  String? flockName,
  HatcheryAgentLinkCatalog catalog,
  String? customerId,
) {
  final normalized = _normalizedName(flockName);
  if (normalized == null) return null;
  final matches = catalog
      .flocksForCustomer(customerId)
      .where((flock) => _normalizedName(flock.flockId) == normalized)
      .toList(growable: false);
  return matches.length == 1 ? matches.single.id : null;
}

String? _initialHatcheryId(
  HatcheryDraftRow row,
  HatcheryAgentLinkCatalog catalog,
  String? customerId,
) {
  if (row.hatcheryId != null) return row.hatcheryId;
  final hatcheries = catalog.hatcheriesForCustomer(customerId);
  return hatcheries.length == 1 ? hatcheries.single.id : null;
}

CustomerModel? _customerById(
  HatcheryAgentLinkCatalog catalog,
  String? customerId,
) {
  if (customerId == null) return null;
  for (final customer in catalog.customers) {
    if (customer.id == customerId) return customer;
  }
  return null;
}

FlockModel? _flockById(HatcheryAgentLinkCatalog catalog, String? flockId) {
  if (flockId == null) return null;
  for (final flock in catalog.flocks) {
    if (flock.id == flockId) return flock;
  }
  return null;
}

String? _normalizedName(String? source) {
  final normalized = source
      ?.trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

TextEditingController _controller(Object? value) {
  return TextEditingController(text: value?.toString() ?? '');
}

TextInputType _keyboardType(_DraftInputKind kind) {
  return switch (kind) {
    _DraftInputKind.integer => TextInputType.number,
    _DraftInputKind.decimal => const TextInputType.numberWithOptions(
      decimal: true,
    ),
    _DraftInputKind.text || _DraftInputKind.date => TextInputType.text,
  };
}

String? _validateField(
  BuildContext context,
  _DraftInputKind kind,
  String? source,
) {
  final value = source?.trim() ?? '';
  if (value.isEmpty) return null;
  final valid = switch (kind) {
    _DraftInputKind.text => true,
    _DraftInputKind.integer => int.tryParse(value) != null,
    _DraftInputKind.decimal => double.tryParse(value) != null,
    _DraftInputKind.date => _parseDateInput(value) != null,
  };
  return valid ? null : context.tr('Enter a valid value');
}

DateTime? _parseDateInput(String source) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(source.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

String? _dateInput(DateTime? value) {
  if (value == null) return null;
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

class _SourceEvidenceCard extends StatelessWidget {
  const _SourceEvidenceCard({required this.details});

  final HatcheryDraftBatchDetails details;

  @override
  Widget build(BuildContext context) {
    final submission = details.submission;
    final batch = details.batch;
    final source =
        submission.sourceText ??
        submission.sourceFileName ??
        submission.sourceRemotePath ??
        'Source unavailable';
    final submitter = submission.telegramUserId == null
        ? 'Unknown staff'
        : 'Telegram user ${submission.telegramUserId}';
    final status = agentSubmissionStatusPresentation(batch.status);

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  batch.sourceSummary ?? 'Original Telegram source',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              AgentStatusChip(presentation: status),
            ],
          ),
          const SizedBox(height: AppSizes.spaceLg),
          _EvidenceLine(
            icon: Icons.person_outline,
            label: 'Staff submitter',
            value: submitter,
          ),
          _EvidenceLine(
            icon: Icons.attach_file,
            label: 'Source type',
            value: _sourceKindLabel(submission.sourceKind),
          ),
          _EvidenceLine(
            icon: Icons.schedule,
            label: 'Submitted',
            value: _formatTimestamp(submission.submittedAt),
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text('Original source', style: AppTextStyles.caption),
          const SizedBox(height: AppSizes.spaceXs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSizes.spaceMd),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              border: Border.all(color: AppColors.borderDefault),
            ),
            child: Text(source, style: AppTextStyles.body),
          ),
        ],
      ),
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.iconSm, color: AppColors.textSecondary),
          const SizedBox(width: AppSizes.spaceSm),
          SizedBox(
            width: 110,
            child: Text(label, style: AppTextStyles.caption),
          ),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}

class _QuestionsCard extends StatelessWidget {
  const _QuestionsCard({required this.questions});

  final List<HatcheryAgentQuestion> questions;

  @override
  Widget build(BuildContext context) {
    final isArabic = context.l10n.isArabic;
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Questions and answers', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.spaceMd),
          ...questions.map((question) {
            final prompt = isArabic
                ? question.questionTextAr
                : question.questionTextEn;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
              padding: const EdgeInsets.all(AppSizes.spaceMd),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prompt, style: AppTextStyles.body),
                  const SizedBox(height: AppSizes.spaceXs),
                  Text(
                    question.answerText ?? 'Waiting for answer',
                    style: AppTextStyles.subtitle.copyWith(
                      color: question.answerText == null
                          ? AppColors.statusWarning
                          : AppColors.statusGood,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AuditHistoryCard extends StatelessWidget {
  const _AuditHistoryCard({required this.events});

  final List<HatcheryAgentAuditEvent> events;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Admin action history', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.spaceMd),
          if (events.isEmpty)
            Text('No admin actions yet', style: AppTextStyles.caption)
          else
            ...events.map(
              (event) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.history),
                title: Text(_eventLabel(event.eventType)),
                subtitle: Text(
                  '${event.actorId ?? event.actorType} · '
                  '${_formatTimestamp(event.createdAt)}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyMonitor extends StatelessWidget {
  const _EmptyMonitor();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.smart_toy_outlined,
              size: AppSizes.iconLg,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: AppSizes.spaceMd),
            Text('No agent submissions', style: AppTextStyles.sectionTitle),
            const SizedBox(height: AppSizes.spaceXs),
            Text(
              'Telegram submissions will appear here for review.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _sourceKindLabel(AgentSourceKind kind) {
  return switch (kind) {
    AgentSourceKind.text => 'Text',
    AgentSourceKind.image => 'Image',
    AgentSourceKind.pdf => 'PDF',
    AgentSourceKind.spreadsheet => 'Spreadsheet',
    AgentSourceKind.file => 'File',
  };
}

String _eventLabel(String value) {
  if (value == 'row_extracted') return 'Row extracted';
  if (value.isEmpty) return 'Agent event';
  final words = value.split('_');
  final label = words.join(' ');
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

String _staffDisplayName(TelegramStaffLink link) {
  final name = link.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return 'Telegram user ${link.telegramUserId}';
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
