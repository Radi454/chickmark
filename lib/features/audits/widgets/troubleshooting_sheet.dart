import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/troubleshooting_model.dart';
import '../../../../data/repositories/troubleshooting_repository.dart';

class TroubleshootingSheet extends StatefulWidget {
  final String parameterId;

  const TroubleshootingSheet({super.key, required this.parameterId});

  @override
  State<TroubleshootingSheet> createState() => _TroubleshootingSheetState();
}

class _TroubleshootingSheetState extends State<TroubleshootingSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TroubleshootingRepository _repository = TroubleshootingRepository();
  final TextEditingController _searchController = TextEditingController();
  TroubleshootingModel? _troubleshooting;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTroubleshooting();
  }

  Future<void> _loadTroubleshooting() async {
    final data = await _repository.getByParameter(widget.parameterId);
    if (mounted) {
      setState(() {
        _troubleshooting = data;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.cardPadding,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Troubleshooting Guide',
                    style: AppTextStyles.heading.copyWith(fontSize: 20),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.cardPadding,
              12,
              AppSizes.cardPadding,
              8,
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search troubleshooting causes',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Tab bar
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey[600],
            tabs: const [
              Tab(text: 'Hatchery Causes'),
              Tab(text: 'Farm/Flock Causes'),
            ],
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _troubleshooting == null
                ? _buildEmptyState()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCausesTab(
                        _troubleshooting!.hatcheryCausesBySection,
                      ),
                      _buildCausesTab(
                        _troubleshooting!.farmFlockCausesBySection,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return _buildInfoState(
      'No troubleshooting data available for this parameter.',
    );
  }

  Widget _buildInfoState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: AppTextStyles.body.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCausesTab(Map<String, List<String>> causesBySection) {
    if (causesBySection.isEmpty) {
      return _buildEmptyState();
    }

    final filtered = _filterCauses(causesBySection);
    if (filtered.isEmpty) {
      return _buildInfoState('No troubleshooting causes match your search.');
    }

    return ListView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      children: filtered.entries.map((entry) {
        return _buildExpandableSection(entry.key, entry.value);
      }).toList(),
    );
  }

  Map<String, List<String>> _filterCauses(Map<String, List<String>> input) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return input;

    final filtered = <String, List<String>>{};
    for (final entry in input.entries) {
      final matches = entry.value
          .where((cause) => cause.toLowerCase().contains(query))
          .toList();
      if (matches.isNotEmpty) {
        filtered[entry.key] = matches;
      }
    }
    return filtered;
  }

  Widget _buildExpandableSection(String title, List<String> causes) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.cardPadding,
          vertical: 8,
        ),
        title: Text(
          title,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: causes
                  .map(
                    (cause) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.arrow_right,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(cause, style: AppTextStyles.body),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
