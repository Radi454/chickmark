import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/audit_type_labels.dart';
import '../../../data/models/flock_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/audit_session_provider.dart';
import 'audit_session_screen.dart';

class AuditStationSelectionScreen extends StatefulWidget {
  final String customerId;
  final String flockId;
  final String hatcheryId;
  final FlockModel selectedFlock;

  const AuditStationSelectionScreen({
    super.key,
    required this.customerId,
    required this.flockId,
    required this.hatcheryId,
    required this.selectedFlock,
  });

  @override
  State<AuditStationSelectionScreen> createState() =>
      _AuditStationSelectionScreenState();
}

class _AuditStationSelectionScreenState
    extends State<AuditStationSelectionScreen> {
  final List<String> _orderedSelectedKeys = [];
  bool _isStarting = false;

  static const _allStations = [
    {'key': 'egg', 'name': AuditTypeLabels.eggStationLabel, 'icon': Icons.egg},
    {'key': 'chicks', 'name': 'Chicks', 'icon': Icons.cruelty_free},
    {
      'key': 'hatch_analysis_egg_breakouts',
      'name': 'Hatch Analysis & Egg Breakouts',
      'icon': Icons.bar_chart,
    },
    {'key': 'setters', 'name': 'Setters', 'icon': Icons.thermostat},
    {'key': 'hatchers', 'name': 'Hatchers', 'icon': Icons.device_thermostat},
  ];

  List<Map<String, dynamic>> get _availableStations => _allStations
      .where((s) => !_orderedSelectedKeys.contains(s['key'] as String))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Select Stations'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_orderedSelectedKeys.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildSelectedStationsSection(),
                  ],
                  if (_availableStations.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildAvailableStationsSection(),
                  ],
                ],
              ),
            ),
          ),
          _buildStartVisitButton(),
        ],
      ),
    );
  }

  Widget _buildSelectedStationsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Visit order',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _orderedSelectedKeys.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                return _buildSelectedTile(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _orderedSelectedKeys.removeAt(oldIndex);
      _orderedSelectedKeys.insert(newIndex, item);
    });
  }

  Widget _buildSelectedTile(int index) {
    final stationKey = _orderedSelectedKeys[index];
    final station = _allStations.firstWhere(
      (s) => s['key'] == stationKey,
      orElse: () => {'key': '', 'name': '', 'icon': Icons.help},
    );
    final icon = station['icon'] as IconData;
    final name = station['name'] as String;

    return Material(
      key: ValueKey(stationKey),
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(name, style: AppTextStyles.body)),
                IconButton(
                  onPressed: () {
                    setState(() => _orderedSelectedKeys.removeAt(index));
                  },
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.grey,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(
                    Icons.drag_handle,
                    color: Colors.grey,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvailableStationsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Tap to add',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ..._availableStations.map(_buildAvailableTile),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableTile(Map<String, dynamic> station) {
    final icon = station['icon'] as IconData;
    final name = station['name'] as String;
    final stationKey = station['key'] as String;

    return InkWell(
      onTap: () => setState(() => _orderedSelectedKeys.add(stationKey)),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade200,
              ),
              child: const Icon(Icons.add, size: 16, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            Icon(icon, color: Colors.grey, size: 20),
            const SizedBox(width: 10),
            Text(name, style: AppTextStyles.body.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildStartVisitButton() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _orderedSelectedKeys.isNotEmpty && !_isStarting
                ? _handleStartVisit
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
            child: _isStarting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Start Visit',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleStartVisit() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);

    final sessionProvider = context.read<AuditSessionProvider>();

    try {
      await sessionProvider.startSession(
        context: AuditSessionContext(
          customerId: widget.customerId,
          hatcheryId: widget.hatcheryId,
          flockId: widget.flockId,
          date: DateTime.now(),
          breed: widget.selectedFlock.breed,
          flockAgeWeeks: widget.selectedFlock.currentAgeWeeks.toInt(),
          selectedStationKeys: _orderedSelectedKeys,
        ),
        currentUser: context.read<AuthProvider>().user,
      );

      if (!mounted) return;

      if (sessionProvider.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(sessionProvider.error!)));
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChangeNotifierProvider.value(
            value: sessionProvider,
            child: const AuditSessionScreen(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }
}
