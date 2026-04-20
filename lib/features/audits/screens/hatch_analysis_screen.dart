import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/audit_provider.dart';
import '../widgets/tabs/hatch_results_tab.dart';
import '../widgets/tabs/egg_breakout_tab.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class HatchAnalysisScreen extends StatefulWidget {
  final AuditContextData context;

  const HatchAnalysisScreen({super.key, required this.context});

  @override
  State<HatchAnalysisScreen> createState() => _HatchAnalysisScreenState();
}

class _HatchAnalysisScreenState extends State<HatchAnalysisScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      date: widget.context.date,
    );
    auditProvider.initialize(
      auditContext,
      notify: false,
      currentUser: context.read<AuthProvider>().user,
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

    return Scaffold(
      appBar: GradientAppBar(
        title: 'Hatch Analysis',
        actions: [
          if (!auditProvider.isReadOnly)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => auditProvider.setEditMode(true),
            ),
        ],
      ),
      body: Column(
        children: [
          // Tab bar with green indicators
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.inactiveTab,
              tabs: List.generate(2, (index) {
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
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                HatchResultsTab(
                  audit: auditProvider.activeDraft,
                  isReadOnly: auditProvider.isReadOnly,
                  onFieldChanged: (key, value) {
                    auditProvider.updateField(key, value);
                  },
                  onSave: () => auditProvider.saveTab(0),
                ),
                EggBreakoutTab(
                  audit: auditProvider.activeDraft,
                  isReadOnly: auditProvider.isReadOnly,
                  onFieldChanged: (key, value) {
                    auditProvider.updateField(key, value);
                  },
                  onSave: () => auditProvider.saveTab(1),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: auditProvider.isReadOnly
            ? null
            : () => auditProvider.saveTab(_currentTab),
        backgroundColor: auditProvider.isTabSaved(_currentTab)
            ? AppColors.greenTab
            : AppColors.primary,
        icon: Icon(
          auditProvider.isTabSaved(_currentTab) ? Icons.check : Icons.save,
        ),
        label: Text(auditProvider.isTabSaved(_currentTab) ? 'Saved' : 'Save'),
      ),
    );
  }

  String _getTabTitle(int index) {
    switch (index) {
      case 0:
        return 'Hatch Results';
      case 1:
        return 'Egg Breakout';
      default:
        return '';
    }
  }
}
