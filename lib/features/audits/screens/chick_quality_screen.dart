import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/sample_mode.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../widgets/tabs/pasgar_tab.dart';
import '../widgets/tabs/weights_tab.dart';
import '../widgets/tabs/yfbm_tab.dart';
import '../widgets/tabs/cvt_tab.dart';
import '../widgets/tabs/pm_necropsy_tab.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class ChickQualityScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final int initialTabIndex;

  const ChickQualityScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialTabIndex = 0,
  });

  @override
  State<ChickQualityScreen> createState() => _ChickQualityScreenState();
}

class _ChickQualityScreenState extends State<ChickQualityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 4).toInt(),
    );

    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    final auditContext = AuditContext(
      auditType: widget.context.auditType,
      customerId: widget.context.customerId,
      flockId: widget.context.flockId,
      breed: widget.context.breed,
      setterId: widget.context.setterId,
      hatcherId: widget.context.hatcherId,
      date: widget.context.date,
    );
    auditProvider.initialize(
      auditContext,
      existingAudit: widget.initialAudit,
      notify: false,
      currentUser: context.read<AuthProvider>().user,
      sessionId: widget.context.sessionId,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditProvider = context.watch<AuditProvider>();

    return UnsavedChangesGuard(
      enabled: widget.context.sessionId == null,
      child: Scaffold(
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Chick Quality',
                actions: [
                  if (auditProvider.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => auditProvider.setEditMode(true),
                    ),
                ],
              ),
        body: AuditKeyboardDismiss(
          child: Column(
            children: [
              _buildSampleModeControl(auditProvider),
              _buildAuditHeader(auditProvider),
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.inactiveTab,
                  tabs: List.generate(5, (index) {
                    final isSaved = auditProvider.isTabSaved(index);
                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSaved)
                            Icon(
                              Icons.check_circle,
                              color: AppColors.greenTab,
                              size: 16,
                            ),
                          Text(
                            _getTabTitle(index),
                            style: TextStyle(
                              color: isSaved ? AppColors.greenTab : null,
                              fontWeight: isSaved ? FontWeight.bold : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    PasgarTab(
                      audit: auditProvider.activeDraft,
                      isReadOnly: auditProvider.isReadOnly,
                      onFieldChanged: (key, value) {
                        auditProvider.updateField(key, value);
                      },
                    ),
                    WeightsTab(
                      audit: auditProvider.activeDraft,
                      isReadOnly: auditProvider.isReadOnly,
                      onFieldChanged: (key, value) {
                        auditProvider.updateField(key, value);
                      },
                    ),
                    YfbmTab(
                      audit: auditProvider.activeDraft,
                      isReadOnly: auditProvider.isReadOnly,
                      onFieldChanged: (key, value) {
                        auditProvider.updateField(key, value);
                      },
                    ),
                    CvtTab(
                      audit: auditProvider.activeDraft,
                      isReadOnly: auditProvider.isReadOnly,
                      onFieldChanged: (key, value) {
                        auditProvider.updateField(key, value);
                      },
                    ),
                    PmNecropsyTab(
                      audit: auditProvider.activeDraft,
                      isReadOnly: auditProvider.isReadOnly,
                      onFieldChanged: (key, value) {
                        auditProvider.updateField(key, value);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditHeader(AuditProvider provider) {
    final audit = provider.activeDraft;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.cardPadding,
        AppSizes.cardPadding,
        AppSizes.cardPadding,
        8,
      ),
      child: Column(
        children: [
          if (!provider.isCompareMode)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pooled sample',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Column(
              children: [
                _buildHatchCompareTabs(provider),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _contextField(
                        key: 'setter_${audit.id}',
                        label: 'Setter ID',
                        initialValue: audit.setterId ?? '',
                        enabled: !provider.isReadOnly,
                        onChanged: (value) =>
                            provider.updateField('setterId', value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _contextField(
                        key: 'hatcher_${audit.id}',
                        label: 'Hatcher ID',
                        initialValue: audit.hatcherId ?? '',
                        enabled: !provider.isReadOnly,
                        onChanged: (value) =>
                            provider.updateField('hatcherId', value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHatchCompareTabs(AuditProvider provider) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(provider.hatchCount, (index) {
                final selected = provider.activeHatchIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('Hatch ${index + 1}'),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: provider.isReadOnly
                        ? null
                        : (_) => provider.switchHatch(index),
                    labelStyle: AppTextStyles.caption.copyWith(
                      color: selected ? Colors.white : AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    selectedColor: AppColors.primary,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : AppColors.borderDefault,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Remove active hatch',
          icon: const Icon(Icons.remove_circle_outline),
          color: AppColors.statusError,
          onPressed: provider.isReadOnly || provider.hatchCount <= 1
              ? null
              : provider.removeActiveHatch,
        ),
        IconButton(
          tooltip: 'Add hatch',
          icon: const Icon(Icons.add_circle_outline),
          color: AppColors.primary,
          onPressed: provider.isReadOnly ? null : provider.addHatch,
        ),
      ],
    );
  }

  Widget _buildSampleModeControl(AuditProvider provider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.cardPadding,
        AppSizes.cardPadding,
        AppSizes.cardPadding,
        0,
      ),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: SampleMode.pool,
            icon: Icon(Icons.all_inclusive),
            label: Text('Pool sample'),
          ),
          ButtonSegment(
            value: SampleMode.compare,
            icon: Icon(Icons.compare_arrows),
            label: Text('Compare hatches'),
          ),
        ],
        selected: {provider.sampleMode},
        onSelectionChanged: provider.isReadOnly
            ? null
            : (selection) => provider.setSampleMode(selection.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.primary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.primary
                : Colors.white;
          }),
        ),
      ),
    );
  }

  Widget _contextField({
    required String key,
    required String label,
    required String initialValue,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      key: ValueKey(key),
      initialValue: initialValue,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }

  String _getTabTitle(int index) {
    switch (index) {
      case 0:
        return 'Pasgar Score';
      case 1:
        return 'Chick Weights';
      case 2:
        return 'YFBM';
      case 3:
        return 'CVT';
      case 4:
        return 'PM Necropsy';
      default:
        return '';
    }
  }
}
