import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/customers_provider.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/hatchery_model.dart';
import '../../customers/widgets/flock_management_sheet.dart';
import '../../customers/widgets/hatchery_management_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/audit_provider.dart';
import 'chick_quality_screen.dart';
import 'hatch_analysis_screen.dart';
import 'setter_optimizing_screen.dart';
import 'hatcher_optimizing_screen.dart';
import 'egg_storage_screen.dart';
import 'audit_station_selection_screen.dart';

class AuditContextScreen extends StatefulWidget {
  final String? auditType;

  const AuditContextScreen({super.key, this.auditType});

  @override
  State<AuditContextScreen> createState() => _AuditContextScreenState();
}

class _AuditContextScreenState extends State<AuditContextScreen> {
  String? _selectedCustomerId;
  String? _selectedFlockId;
  String? _selectedHatcheryId;
  final TextEditingController _setterIdController = TextEditingController();
  final TextEditingController _hatcherIdController = TextEditingController();

  bool get _isSessionFlow => widget.auditType == null;

  @override
  void dispose() {
    _setterIdController.dispose();
    _hatcherIdController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (!(auth.user?.canEditAudits ?? false)) {
        Navigator.of(context).pop();
        return;
      }
      context.read<CustomersProvider>().loadCustomers(currentUser: auth.user);
    });
  }

  @override
  Widget build(BuildContext context) {
    final customersProvider = context.watch<CustomersProvider>();
    final customers = customersProvider.filteredCustomers;

    final flocks = customersProvider.selectedCustomer?.id == _selectedCustomerId
        ? customersProvider.availableFlocks
        : <FlockModel>[];
    final hatcheries =
        customersProvider.selectedCustomer?.id == _selectedCustomerId
            ? customersProvider.hatcheries
            : <HatcheryModel>[];

    if (_selectedHatcheryId != null &&
        !hatcheries.any((h) => h.id == _selectedHatcheryId)) {
      _selectedHatcheryId = null;
    }
    if (_selectedHatcheryId == null && hatcheries.length == 1) {
      _selectedHatcheryId = hatcheries.first.id;
    }

    final selectedCustomer =
        customers.where((c) => c.id == _selectedCustomerId).firstOrNull;
    final selectedFlock = _findSelectedFlock(flocks);
    final selectedHatchery =
        hatcheries.where((h) => h.id == _selectedHatcheryId).firstOrNull;

    final showSetterField = widget.auditType == 'Setter Optimizing';
    final showHatcherField = widget.auditType == 'Hatcher Optimizing';
    final title = _isSessionFlow ? 'New Visit' : widget.auditType!;

    return Scaffold(
      appBar: GradientAppBar(title: title),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer
            _buildSummaryCard(
              icon: Icons.business_outlined,
              label: 'Customer',
              displayValue: selectedCustomer?.name,
              placeholder: 'Select customer',
              onTap: () => _showCustomerSheet(context, customers
                  .map((c) => _CustomerOption(id: c.id, name: c.name))
                  .toList(), customersProvider),
            ),
            const SizedBox(height: 12),

            // Hatchery
            _buildSummaryCard(
              icon: Icons.factory_outlined,
              label: 'Hatchery',
              displayValue: selectedHatchery == null
                  ? null
                  : (selectedHatchery.location?.isNotEmpty == true
                      ? '${selectedHatchery.name} · ${selectedHatchery.location}'
                      : selectedHatchery.name),
              placeholder: _selectedCustomerId == null
                  ? 'Select customer first'
                  : 'Select hatchery',
              onTap: _selectedCustomerId != null
                  ? () => _showHatcheryManagementSheet(context)
                  : null,
            ),
            const SizedBox(height: 12),

            // Flock
            _buildSummaryCard(
              icon: Icons.pets,
              label: 'Flock',
              displayValue: selectedFlock == null
                  ? null
                  : '${selectedFlock.flockId} · ${selectedFlock.breed} · ${selectedFlock.currentAgeWeeks.toInt()}w',
              placeholder: _selectedCustomerId == null
                  ? 'Select customer first'
                  : 'Select flock',
              onTap: _selectedCustomerId != null
                  ? () => _showFlockManagementSheet(context)
                  : null,
            ),

            // Flock detail card
            if (selectedFlock != null) ...[
              const SizedBox(height: 12),
              _buildFlockDetailCard(selectedFlock),
            ],

            // Legacy setter/hatcher fields
            if (showSetterField) ...[
              const SizedBox(height: 12),
              _buildTextFieldCard(
                icon: Icons.precision_manufacturing,
                title: 'Setter ID',
                controller: _setterIdController,
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (showHatcherField) ...[
              const SizedBox(height: 12),
              _buildTextFieldCard(
                icon: Icons.precision_manufacturing,
                title: 'Hatcher ID',
                controller: _hatcherIdController,
                onChanged: (_) => setState(() {}),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _canContinue(selectedFlock)
                    ? () => _handleContinue(selectedFlock!)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withAlpha(77),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
                  ),
                ),
                child: Text(
                  _isSessionFlow ? 'Next: Select Stations' : 'Continue',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String? displayValue,
    required String placeholder,
    required VoidCallback? onTap,
  }) {
    final isSelected = displayValue != null;
    final isEnabled = onTap != null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        side: isSelected
            ? const BorderSide(color: AppColors.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.infoBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: AppTextStyles.caption
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      displayValue ?? placeholder,
                      style: AppTextStyles.body.copyWith(
                        color: isSelected
                            ? const Color(0xFF111827)
                            : Colors.grey.shade500,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.edit_outlined : Icons.chevron_right,
                color: isEnabled ? AppColors.primary : Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlockDetailCard(FlockModel flock) {
    return Card(
      elevation: 1,
      color: AppColors.infoBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${flock.breed}  ·  ${flock.currentAgeWeeks.toStringAsFixed(1)}w  ·  Entry ${flock.entryDate.toIso8601String().split('T')[0]}',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.primary, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextFieldCard({
    required IconData icon,
    required String title,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style:
                        AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomerSheet(
    BuildContext context,
    List<_CustomerOption> options,
    CustomersProvider customersProvider,
  ) async {
    final picked = await showModalBottomSheet<_CustomerOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Select Customer',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: options.length,
                  itemBuilder: (_, i) => ListTile(
                    leading:
                        const Icon(Icons.business_outlined, color: AppColors.primary),
                    title: Text(options[i].name, style: AppTextStyles.body),
                    onTap: () => Navigator.pop(ctx, options[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedCustomerId = picked.id;
        _selectedFlockId = null;
        _selectedHatcheryId = null;
        _setterIdController.clear();
        _hatcherIdController.clear();
      });
      final customer = customersProvider.filteredCustomers
          .where((c) => c.id == picked.id)
          .firstOrNull;
      if (customer != null) customersProvider.selectCustomer(customer);
    }
  }

  Future<void> _showHatcheryManagementSheet(BuildContext context) async {
    final provider = context.read<CustomersProvider>();
    final selectedCustomer = provider.selectedCustomer;
    if (selectedCustomer == null ||
        selectedCustomer.id != _selectedCustomerId) {
      return;
    }

    final picked = await showModalBottomSheet<HatcheryModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          const HatcheryManagementSheet(allowAuditSelection: true),
    );

    if (!mounted) return;
    if (picked != null) {
      setState(() => _selectedHatcheryId = picked.id);
      return;
    }
    final stillAvailable =
        provider.hatcheries.any((h) => h.id == _selectedHatcheryId);
    if (!stillAvailable) setState(() => _selectedHatcheryId = null);
  }

  Future<void> _showFlockManagementSheet(BuildContext context) async {
    final provider = context.read<CustomersProvider>();
    final selectedCustomer = provider.selectedCustomer;
    if (selectedCustomer == null ||
        selectedCustomer.id != _selectedCustomerId) {
      return;
    }

    final selectedFlock = await showModalBottomSheet<FlockModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          const FlockManagementSheet(allowAuditSelection: true),
    );

    if (!mounted) return;
    final availableFlocks = provider.availableFlocks;
    final currentSelectionStillAvailable =
        availableFlocks.any((flock) => flock.id == _selectedFlockId);
    if (selectedFlock != null && selectedFlock.isAvailableForAudit) {
      setState(() => _selectedFlockId = selectedFlock.id);
      return;
    }
    if (!currentSelectionStillAvailable) {
      setState(() => _selectedFlockId = null);
    }
  }

  FlockModel? _findSelectedFlock(List<FlockModel> flocks) {
    for (final flock in flocks) {
      if (flock.id == _selectedFlockId) return flock;
    }
    return null;
  }

  bool _canContinue(FlockModel? selectedFlock) {
    if (_selectedCustomerId == null) return false;
    if (selectedFlock == null || !selectedFlock.isAvailableForAudit) {
      return false;
    }
    if (_isSessionFlow && _selectedHatcheryId == null) return false;
    if (widget.auditType == 'Setter Optimizing') {
      return _setterIdController.text.trim().isNotEmpty;
    }
    if (widget.auditType == 'Hatcher Optimizing') {
      return _hatcherIdController.text.trim().isNotEmpty;
    }
    return true;
  }

  void _handleContinue(FlockModel selectedFlock) {
    if (_isSessionFlow) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AuditStationSelectionScreen(
            customerId: _selectedCustomerId!,
            flockId: _selectedFlockId!,
            hatcheryId: _selectedHatcheryId!,
            selectedFlock: selectedFlock,
          ),
        ),
      );
    } else {
      _handleLegacyContinue(selectedFlock);
    }
  }

  void _handleLegacyContinue(FlockModel selectedFlock) {
    final contextData = AuditContextData(
      auditType: widget.auditType!,
      customerId: _selectedCustomerId!,
      flockId: _selectedFlockId!,
      breed: selectedFlock.breed,
      setterId: _setterIdController.text.trim().isEmpty
          ? null
          : _setterIdController.text.trim(),
      hatcherId: _hatcherIdController.text.trim().isEmpty
          ? null
          : _hatcherIdController.text.trim(),
      flockEntryDate: selectedFlock.entryDate,
      date: DateTime.now().toIso8601String().split('T')[0],
    );

    Widget screen;
    switch (widget.auditType) {
      case 'Chick Quality':
        screen = ChickQualityScreen(context: contextData);
        break;
      case 'Hatch Analysis':
        screen = HatchAnalysisScreen(context: contextData);
        break;
      case 'Setter Optimizing':
        screen = SetterOptimizingScreen(context: contextData);
        break;
      case 'Hatcher Optimizing':
        screen = HatcherOptimizingScreen(context: contextData);
        break;
      case 'Egg Storage':
        screen = EggStorageScreen(context: contextData);
        break;
      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (_) => AuditProvider(),
          child: screen,
        ),
      ),
    );
  }
}

class _CustomerOption {
  final String id;
  final String name;
  const _CustomerOption({required this.id, required this.name});
}

class AuditContextData {
  final String auditType;
  final String customerId;
  final String flockId;
  final String? sessionId;
  final String? breed;
  final String? setterId;
  final String? hatcherId;
  final DateTime? flockEntryDate;
  final String date;

  AuditContextData({
    required this.auditType,
    required this.customerId,
    required this.flockId,
    this.sessionId,
    this.breed,
    this.setterId,
    this.hatcherId,
    this.flockEntryDate,
    required this.date,
  });
}
