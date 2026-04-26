import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/audit_model.dart';
import '../providers/audit_provider.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../widgets/tabs/cha_env_tab.dart';
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
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 5).toInt(),
    );
    _currentTab = _tabController.index;
    _tabController.addListener(() {
      setState(() {
        _currentTab = _tabController.index;
      });
    });

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
      child: Scaffold(
        appBar: widget.context.sessionId != null ? null : GradientAppBar(
          title: 'Chick Quality',
          actions: [
            if (auditProvider.isReadOnly)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => auditProvider.setEditMode(true),
              ),
            if (!auditProvider.isReadOnly)
              IconButton(
                tooltip: 'Add hatch',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: auditProvider.addHatch,
              ),
          ],
        ),
        body: Column(
          children: [
            _buildAuditHeader(auditProvider),
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.inactiveTab,
                tabs: List.generate(6, (index) {
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
                  ChaEnvTab(
                    audit: auditProvider.activeDraft,
                    isReadOnly: auditProvider.isReadOnly,
                    auditSessionId: widget.context.sessionId ??
                        '${widget.context.customerId}_${widget.context.flockId}',
                    onFieldChanged: (key, value) {
                      auditProvider.updateField(key, value);
                    },
                  ),
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
          if (provider.hatchCount > 1)
            Row(
              children: [
                Text('Hatch', style: AppTextStyles.caption),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: provider.activeHatchIndex,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: List.generate(
                      provider.hatchCount,
                      (index) => DropdownMenuItem(
                        value: index,
                        child: Text('Hatch ${index + 1}'),
                      ),
                    ),
                    onChanged: provider.isReadOnly
                        ? null
                        : (index) {
                            if (index != null) provider.switchHatch(index);
                          },
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Hatch ${provider.activeHatchIndex + 1}',
                style: AppTextStyles.caption,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _contextField(
                  key: 'setter_${audit.id}',
                  label: 'Setter ID',
                  initialValue: audit.setterId ?? '',
                  enabled: !provider.isReadOnly,
                  onChanged: (value) => provider.updateField('setterId', value),
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
        return 'CHA Environmental';
      case 1:
        return 'Pasgar Score';
      case 2:
        return 'Chick Weights';
      case 3:
        return 'YFBM';
      case 4:
        return 'CVT';
      case 5:
        return 'PM Necropsy';
      default:
        return '';
    }
  }
}
