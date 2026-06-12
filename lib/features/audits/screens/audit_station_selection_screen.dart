import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/audit_type_labels.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../data/models/flock_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/audit_session_provider.dart';
import '../widgets/chick_icon.dart';
import 'audit_session_screen.dart';

class AuditStationSelectionScreen extends StatefulWidget {
  final String customerId;
  final String flockId;
  final String hatcheryId;
  final FlockModel selectedFlock;
  final DateTime? visitDate;
  final String? existingSessionId;

  const AuditStationSelectionScreen({
    super.key,
    required this.customerId,
    required this.flockId,
    required this.hatcheryId,
    required this.selectedFlock,
    this.visitDate,
    this.existingSessionId,
  });

  @override
  State<AuditStationSelectionScreen> createState() =>
      _AuditStationSelectionScreenState();
}

class _AuditStationSelectionScreenState
    extends State<AuditStationSelectionScreen> {
  final List<String> _orderedSelectedKeys = [];
  final Set<String> _savedStationKeys = <String>{};
  AuditSessionModel? _existingSession;
  String? _selectedOpenStationKey;
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

  DateTime get _visitDate => widget.visitDate ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExistingSession());
  }

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
              onReorderItem: _onReorder,
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
    final name = station['name'] as String;
    final isSaved = _savedStationKeys.contains(stationKey);

    return Material(
      key: ValueKey(stationKey),
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: isSaved
              ? () {
                  setState(() => _selectedOpenStationKey = stationKey);
                  _handleStartVisit();
                }
              : null,
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
                _buildStationIcon(stationKey, AppColors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(name, style: AppTextStyles.body)),
                if (isSaved) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.completedText.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
                      border: Border.all(
                        color: AppColors.completedText.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      'Saved',
                      style: AppTextStyles.badgeLabel.copyWith(
                        color: AppColors.completedText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  tooltip: 'Remove station',
                  onPressed: () {
                    setState(() {
                      final removed = _orderedSelectedKeys.removeAt(index);
                      if (_selectedOpenStationKey == removed) {
                        _selectedOpenStationKey = null;
                      }
                    });
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
            _buildStationIcon(stationKey, Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationIcon(String stationKey, Color color) {
    if (stationKey == 'chicks') {
      return ChickIcon(key: const ValueKey('station-chick-icon'), color: color);
    }

    final station = _allStations.firstWhere(
      (s) => s['key'] == stationKey,
      orElse: () => {'icon': Icons.help},
    );
    return Icon(station['icon'] as IconData, color: color, size: 20);
  }

  Widget _buildStartVisitButton() {
    final buttonText = _existingSession == null
        ? 'Start Visit'
        : 'Continue Visit';
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
                : Text(
                    buttonText,
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
      final existing = _existingSession;
      if (existing != null) {
        await sessionProvider.updateSelectedStationKeys(_orderedSelectedKeys);
        final stationIndex = _selectedOpenStationKey == null
            ? null
            : _orderedSelectedKeys.indexOf(_selectedOpenStationKey!);
        await sessionProvider.resumeSession(
          existing.id,
          initialStationIndex: stationIndex == null || stationIndex < 0
              ? null
              : stationIndex,
        );
      } else {
        await sessionProvider.startOrResumeSession(
          context: _sessionContext(),
          currentUser: context.read<AuthProvider>().user,
        );
      }

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
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(Duration.zero);
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _loadExistingSession() async {
    AuditSessionProvider sessionProvider;
    AuthProvider authProvider;
    try {
      sessionProvider = context.read<AuditSessionProvider>();
      authProvider = context.read<AuthProvider>();
    } on ProviderNotFoundException {
      return;
    }

    if (widget.existingSessionId != null) {
      await sessionProvider.resumeSession(
        widget.existingSessionId!,
        initialStationIndex: 0,
      );
    } else {
      await sessionProvider.loadMatchingSessionForStationSelection(
        context: _sessionContext(selectedStationKeys: const []),
        currentUser: authProvider.user,
      );
    }
    if (!mounted) return;
    final session = sessionProvider.currentSession;
    if (session == null || !sessionProvider.isResumed) return;
    setState(() {
      _existingSession = session;
      _orderedSelectedKeys
        ..clear()
        ..addAll(session.selectedStationKeys);
      _savedStationKeys
        ..clear()
        ..addAll(session.stationsCompleted);
      if (_selectedOpenStationKey != null &&
          !_orderedSelectedKeys.contains(_selectedOpenStationKey)) {
        _selectedOpenStationKey = null;
      }
    });
  }

  AuditSessionContext _sessionContext({List<String>? selectedStationKeys}) {
    return AuditSessionContext(
      customerId: widget.customerId,
      hatcheryId: widget.hatcheryId,
      flockId: widget.flockId,
      date: _visitDate,
      breed: widget.selectedFlock.breed,
      flockAgeWeeks: widget.selectedFlock.currentAgeWeeks.toInt(),
      selectedStationKeys: selectedStationKeys ?? _orderedSelectedKeys,
    );
  }
}
