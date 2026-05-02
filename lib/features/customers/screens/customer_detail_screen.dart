import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/scorecard_formatter.dart';
import '../../../providers/customers_provider.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/audit_model.dart';
import '../../../features/dashboard/providers/dashboard_provider.dart';
import '../../../features/dashboard/models/visit_session_summary.dart';
import '../../../features/customers/widgets/add_flock_sheet.dart';
import '../../../features/customers/widgets/flock_management_sheet.dart';
import '../../../features/customers/widgets/add_hatchery_sheet.dart';
import '../../../features/customers/widgets/add_customer_sheet.dart';
import '../../../features/customers/widgets/audit_history_card.dart';
import '../../../features/customers/screens/audit_detail_screen.dart';
import '../../../features/customers/screens/visit_detail_screen.dart';
import '../../../features/auth/providers/auth_provider.dart';

class CustomerDetailScreen extends StatefulWidget {
  final CustomerModel customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late CustomerModel _customer;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomersProvider>().selectCustomer(_customer);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: GradientAppBar(
          title: _customer.name,
          actions: [
            if (canEdit)
              IconButton(
                tooltip: 'Edit customer',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showEditCustomerSheet(context),
              ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Flocks'),
              Tab(text: 'Hatcheries'),
              Tab(text: 'Audits'),
            ],
          ),
        ),
        body: Consumer<CustomersProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return TabBarView(
              children: [
                _buildFlocksTab(provider, canEdit),
                _buildHatcheriesTab(provider, canEdit),
                _buildAuditHistoryTab(provider),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFlocksTab(CustomersProvider provider, bool canEdit) {
    final summaryCard = _buildCustomerSummaryCard();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (summaryCard != null) ...[summaryCard, const SizedBox(height: 16)],
        _buildTabHeader(
          title: 'Flocks',
          count: provider.flocks.length,
          actionLabel: 'Manage',
          icon: Icons.settings_outlined,
          onAction: canEdit ? () => _showFlockManagementSheet(context) : null,
        ),
        const SizedBox(height: 12),
        if (provider.flocks.isEmpty)
          _buildEmptyState(
            title: 'No flocks yet',
            actionLabel: 'Manage flocks',
            icon: Icons.settings_outlined,
            onAction: canEdit ? () => _showFlockManagementSheet(context) : null,
          )
        else
          ...provider.flocks.map(
            (flock) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildFlockCard(flock, canEdit),
            ),
          ),
      ],
    );
  }

  Widget _buildHatcheriesTab(CustomersProvider provider, bool canEdit) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildTabHeader(
          title: 'Hatcheries',
          count: provider.hatcheries.length,
          actionLabel: 'Add',
          icon: Icons.add_business_outlined,
          onAction: canEdit ? () => _showAddHatcherySheet(context) : null,
        ),
        const SizedBox(height: 12),
        if (provider.hatcheries.isEmpty)
          _buildEmptyState(
            title: 'No hatcheries registered',
            actionLabel: 'Add hatchery',
            icon: Icons.add_business_outlined,
            onAction: canEdit ? () => _showAddHatcherySheet(context) : null,
          )
        else
          ...provider.hatcheries.map(
            (hatchery) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.factory_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(hatchery.name),
                  subtitle: Text(hatchery.location ?? 'No location'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAuditHistoryTab(CustomersProvider provider) {
    final relatedAudits =
        provider.audits
            .where((audit) => audit.customerId == _customer.id)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildVisitSessionsSection(provider),
        if (provider.visitSessions.isNotEmpty && relatedAudits.isNotEmpty)
          const SizedBox(height: 24),
        _buildTabHeader(title: 'Audit history', count: relatedAudits.length),
        const SizedBox(height: 12),
        if (relatedAudits.isEmpty)
          _buildEmptyState(
            title: 'No audits yet',
            subtitle:
                'Start a new visit from the Home tab to record audits for this customer.',
          )
        else
          ...relatedAudits.map(
            (audit) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AuditHistoryCard(
                audit: audit,
                flock: _flockForAudit(provider, audit),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AuditDetailScreen(audit: audit),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVisitSessionsSection(CustomersProvider provider) {
    final visits = provider.visitSessions;
    if (visits.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTabHeader(title: 'Recent visits', count: visits.length),
        const SizedBox(height: 12),
        ...visits.map((visit) => _buildVisitCard(visit)),
      ],
    );
  }

  Widget _buildVisitCard(VisitSessionSummary visit) {
    final completed = visit.completedStationCount;
    final total = visit.selectedStationCount;
    final progress = visit.completionFraction;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final dashboardProvider = context.read<DashboardProvider>();
          final navigator = Navigator.of(context);
          await dashboardProvider.selectVisitSession(visit);
          if (!navigator.mounted) return;
          await navigator.push(
            MaterialPageRoute(
              builder: (context) => VisitDetailScreen(visit: visit),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Visit ${visit.session.date.day}/${visit.session.date.month}/${visit.session.date.year}',
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  _buildVisitStatusChip(visit),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? const Color(0xFF3a9a5c) : AppColors.primary,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                ScorecardFormatter.completionLabel(completed, total),
                style: AppTextStyles.caption.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              _buildStationProgressDots(visit),
              if (visit.findingsSummary != null &&
                  !visit.findingsSummary!.isEmpty) ...[
                const SizedBox(height: 12),
                _buildFindingsChips(visit.findingsSummary!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisitStatusChip(VisitSessionSummary visit) {
    final isComplete = visit.isCompleted;
    final color = isComplete ? const Color(0xFF3a9a5c) : AppColors.primary;
    final label = isComplete ? 'Complete' : 'In progress';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildStationProgressDots(VisitSessionSummary visit) {
    final completed = visit.session.stationsCompleted.toSet();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: visit.selectedStationKeys.map((key) {
        final isDone = completed.contains(key);
        final label = _stationLabel(key);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isDone ? const Color(0xFF3a9a5c) : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isDone ? Colors.black87 : Colors.grey,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  String _stationLabel(String key) {
    switch (key) {
      case 'egg_storage':
        return 'Egg';
      case 'chick_quality':
        return 'Chick';
      case 'hatch_analysis':
        return 'Hatch';
      case 'setter_optimizing':
        return 'Setter';
      case 'hatcher_optimizing':
        return 'Hatcher';
      default:
        return key;
    }
  }

  Widget _buildFindingsChips(SessionFindingsSummary findings) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (findings.greenCount > 0)
          _miniChip('Good', findings.greenCount, const Color(0xFF3a9a5c)),
        if (findings.amberCount > 0)
          _miniChip('Caution', findings.amberCount, const Color(0xFFE6A23C)),
        if (findings.redCount > 0)
          _miniChip('Critical', findings.redCount, const Color(0xFFE24B4A)),
      ],
    );
  }

  Widget _miniChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        '$label: $count',
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget? _buildCustomerSummaryCard() {
    final details = <Widget>[
      if (_customer.location != null)
        _buildCustomerDetail(Icons.location_on_outlined, _customer.location!),
      if (_customer.phone != null)
        _buildCustomerDetail(Icons.phone_outlined, _customer.phone!),
    ];

    if (details.isEmpty) return null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: details),
      ),
    );
  }

  Widget _buildCustomerDetail(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }

  Widget _buildTabHeader({
    required String title,
    required int count,
    String? actionLabel,
    IconData? icon,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$title ($count)',
            style: AppTextStyles.heading.copyWith(fontSize: 20),
          ),
        ),
        if (onAction != null && actionLabel != null && icon != null)
          OutlinedButton.icon(
            onPressed: onAction,
            icon: Icon(icon, size: 18),
            label: Text(actionLabel),
          ),
      ],
    );
  }

  Widget _buildEmptyState({
    required String title,
    String? subtitle,
    String? actionLabel,
    IconData? icon,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(title, style: AppTextStyles.body.copyWith(color: Colors.grey)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.caption.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
          if (onAction != null && actionLabel != null && icon != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(icon),
              label: Text(actionLabel),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFlockCard(FlockModel flock, bool canEdit) {
    final ageWeeks = flock.currentAgeWeeks.toInt();
    final displayAge = ageWeeks < 0 ? 0 : ageWeeks;
    final statusLabel = flock.availabilityLabel;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canEdit ? () => _showEditFlockSheet(context, flock) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            flock.flockId,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (flock.isAgeEstimated) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Entry date is estimated',
                            child: Icon(
                              Icons.warning_amber_outlined,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildFlockAvailabilityBadge(statusLabel),
                ],
              ),
              const SizedBox(height: 12),
              _buildFlockDetailRow('Breed', flock.breed),
              const SizedBox(height: 8),
              _buildFlockDetailRow(
                flock.isAgeEstimated ? 'Estimated entry' : 'Entry date',
                _formatDate(flock.entryDate),
              ),
              const SizedBox(height: 8),
              _buildFlockDetailRow('Current age', '$displayAge weeks'),
              const SizedBox(height: 8),
              _buildFlockDetailRow(
                'Depletion age',
                '${flock.depletionAgeWeeks} weeks',
              ),
              if (flock.isSold && flock.soldAt != null) ...[
                const SizedBox(height: 8),
                _buildFlockDetailRow('Sold date', _formatDate(flock.soldAt!)),
              ],
              if (canEdit) ...[
                const SizedBox(height: 14),
                _buildFlockActions(flock),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlockActions(FlockModel flock) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => _toggleFlockSold(flock),
          icon: Icon(
            flock.isSold ? Icons.check_circle_outline : Icons.sell_outlined,
            size: 18,
          ),
          label: Text(flock.isSold ? 'Mark active' : 'Mark sold'),
        ),
        IconButton.outlined(
          tooltip: 'Edit flock',
          onPressed: () => _showEditFlockSheet(context, flock),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton.outlined(
          tooltip: 'Delete flock',
          onPressed: () => _confirmDeleteFlock(context, flock),
          color: Colors.red.shade700,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _buildFlockAvailabilityBadge(String label) {
    final isActive = label == 'Active';
    final isDepleted = label == 'Depleted';
    final color = isActive
        ? AppColors.completedText
        : isDepleted
        ? Colors.orange.shade800
        : Colors.grey.shade700;
    final icon = isActive
        ? Icons.check_circle_outline
        : isDepleted
        ? Icons.hourglass_bottom_outlined
        : Icons.sell_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlockDetailRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(color: Colors.grey[700]),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  FlockModel? _flockForAudit(CustomersProvider provider, AuditModel audit) {
    if (audit.flockId == null) return null;
    for (final flock in provider.flocks) {
      if (flock.id == audit.flockId) return flock;
    }
    return provider.flockById(audit.flockId);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showFlockManagementSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FlockManagementSheet(),
    );
  }

  void _showAddHatcherySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddHatcherySheet(customerId: _customer.id),
    );
  }

  Future<void> _showEditCustomerSheet(BuildContext context) async {
    final updatedCustomer = await showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddCustomerSheet(initialCustomer: _customer),
    );
    if (!context.mounted || updatedCustomer == null) return;
    setState(() {
      _customer = updatedCustomer;
    });
    await context.read<CustomersProvider>().selectCustomer(updatedCustomer);
  }

  void _showEditFlockSheet(BuildContext context, FlockModel flock) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddFlockSheet(initialFlock: flock),
    );
  }

  void _toggleFlockSold(FlockModel flock) {
    final markSold = !flock.isSold;
    final updated = flock.copyWith(
      status: markSold ? FlockModel.soldStatus : FlockModel.activeStatus,
      soldAt: markSold ? DateTime.now() : null,
      clearSoldAt: !markSold,
    );
    context.read<CustomersProvider>().updateFlock(updated);
  }

  void _confirmDeleteFlock(BuildContext context, FlockModel flock) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Flock'),
        content: Text(
          'Delete flock "${flock.flockId}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              this.context.read<CustomersProvider>().deleteFlock(flock.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
