import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/panel_sample_repository.dart';
import '../../../data/repositories/station_sample_repository.dart';
import '../../audits/providers/audit_provider.dart';
import '../../audits/providers/audit_session_provider.dart';
import '../../audits/screens/audit_context_screen.dart';
import '../../audits/screens/chick_quality_screen.dart';
import '../../audits/screens/egg_storage_screen.dart';
import '../../audits/screens/hatch_analysis_screen.dart';
import '../../audits/screens/hatcher_optimizing_screen.dart';
import '../../audits/screens/setter_optimizing_screen.dart';
import '../../audits/utils/audit_govee_spots.dart';
import '../../audits/widgets/audit_autosave_status.dart';
import '../../audits/widgets/audit_keyboard_dismiss.dart';
import '../../govee/providers/govee_capture_provider.dart';
import '../../govee/widgets/govee_floating_launcher.dart';
import '../../../providers/customers_provider.dart';

bool auditSessionCompletionRoutePredicate(Route<dynamic> route) {
  return route.settings.name == '/main' || route.isFirst;
}

class AuditSessionScreen extends StatefulWidget {
  final AuditRepository? auditRepository;
  final StationSampleRepository? stationSampleRepository;

  const AuditSessionScreen({
    super.key,
    this.auditRepository,
    this.stationSampleRepository,
  });

  @override
  State<AuditSessionScreen> createState() => _AuditSessionScreenState();
}

class _AuditSessionScreenState extends State<AuditSessionScreen> {
  final Map<String, AuditProvider> _stationAuditProviders = {};
  final Map<String, EggStorageStationController> _eggStorageControllers = {};
  final Set<String> _mountedStationKeys = <String>{};
  final PanelSampleRepository _panelSampleRepository = PanelSampleRepository();
  String? _mountedSessionId;
  bool _showSavedAnimation = false;
  bool _isSavingStation = false;

  @override
  void dispose() {
    for (final provider in _stationAuditProviders.values) {
      provider.dispose();
    }
    super.dispose();
  }

  AuditProvider? get _currentStationProvider {
    final sessionProvider = context.read<AuditSessionProvider>();
    if (sessionProvider.currentSession == null) return null;
    final key =
        sessionProvider.stationKeys[sessionProvider.currentStationIndex];
    return _stationAuditProviders[key];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackNavigation(context);
      },
      child: Consumer<AuditSessionProvider>(
        builder: (context, sessionProvider, child) {
          if (sessionProvider.currentSession == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final stationKeys = sessionProvider.stationKeys;
          final currentStationKey = stationKeys.isEmpty
              ? null
              : stationKeys[sessionProvider.currentStationIndex];
          _syncMountedStations(
            sessionProvider.currentSession!.id,
            stationKeys,
            currentStationKey,
          );
          final showProgress =
              currentStationKey != 'hatch_analysis_egg_breakouts';

          return Stack(
            children: [
              Scaffold(
                appBar: _buildAppBar(sessionProvider),
                body: AuditKeyboardDismiss(
                  child: Column(
                    children: [
                      if (showProgress) ...[
                        _buildProgressIndicator(sessionProvider, stationKeys),
                        const Divider(height: 1),
                      ],
                      _buildCurrentStationGoveeEntryPoint(
                        sessionProvider,
                        stationKeys,
                      ),
                      Expanded(
                        child: _buildMountedStationStack(
                          sessionProvider,
                          stationKeys,
                        ),
                      ),
                      _buildNavigationFooter(sessionProvider, stationKeys),
                    ],
                  ),
                ),
              ),
              if (_showSavedAnimation) _buildSavedOverlay(),
            ],
          );
        },
      ),
    );
  }

  void _syncMountedStations(
    String sessionId,
    List<String> stationKeys,
    String? currentStationKey,
  ) {
    if (_mountedSessionId != sessionId) {
      _mountedStationKeys.clear();
      _mountedSessionId = sessionId;
    }

    _mountedStationKeys.removeWhere((key) => !stationKeys.contains(key));
    if (currentStationKey != null) {
      _mountedStationKeys.add(currentStationKey);
    }
  }

  Widget _buildMountedStationStack(
    AuditSessionProvider provider,
    List<String> stationKeys,
  ) {
    return Stack(
      children: [
        for (var i = 0; i < stationKeys.length; i++)
          if (_mountedStationKeys.contains(stationKeys[i]))
            Offstage(
              offstage: i != provider.currentStationIndex,
              child: _buildStationWidget(provider, stationKeys, i),
            ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(AuditSessionProvider provider) {
    final stationKey = provider.stationKeys.isNotEmpty
        ? provider.stationKeys[provider.currentStationIndex]
        : null;
    final title = stationKey != null
        ? (AuditSessionProvider.stationDisplayLabels[stationKey] ?? 'Visit')
        : 'Visit';
    return GradientAppBar(title: title);
  }

  Widget _buildSavedOverlay() {
    return AnimatedOpacity(
      opacity: _showSavedAnimation ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.completedText,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 48),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(
    AuditSessionProvider provider,
    List<String> stationKeys,
  ) {
    final displayLabels = stationKeys
        .map((k) => AuditSessionProvider.stationDisplayLabels[k] ?? k)
        .toList();
    final completed = provider.stationsCompleted;

    return Container(
      key: const ValueKey('audit-session-progress-shell'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const nodeSize = 36.0;
          const connectorHeight = 2.0;
          final stationCount = stationKeys.length;
          final stationCellWidth = constraints.maxWidth / stationCount;
          final connectorTop = (nodeSize - connectorHeight) / 2;

          return Stack(
            children: [
              for (var index = 0; index < stationCount - 1; index++)
                Positioned(
                  left: stationCellWidth * (index + 0.5) + nodeSize / 2,
                  right:
                      constraints.maxWidth -
                      (stationCellWidth * (index + 1.5) - nodeSize / 2),
                  top: connectorTop,
                  child: Container(
                    key: ValueKey('audit-session-progress-connector-$index'),
                    height: connectorHeight,
                    color:
                        completed.contains(stationKeys[index]) ||
                            index == provider.currentStationIndex ||
                            index < provider.currentStationIndex
                        ? AppColors.completedText
                        : Colors.grey.shade300,
                  ),
                ),
              Row(
                children: List.generate(stationCount, (index) {
                  final isCompleted = completed.contains(stationKeys[index]);
                  final isCurrent = index == provider.currentStationIndex;
                  final isPast = index < provider.currentStationIndex;
                  final isReached = isCompleted || isCurrent || isPast;

                  return Expanded(
                    child: GestureDetector(
                      onTap: isPast || isCompleted || isCurrent
                          ? () =>
                                _handleStationTap(provider, index, stationKeys)
                          : null,
                      child: Column(
                        children: [
                          Container(
                            key: ValueKey('audit-session-progress-node-$index'),
                            width: nodeSize,
                            height: nodeSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isReached
                                  ? AppColors.completedText
                                  : Colors.grey.shade300,
                            ),
                            child: Center(
                              child: isReached
                                  ? const Icon(
                                      Icons.check,
                                      size: 12,
                                      color: Colors.white,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _progressStationLabel(
                              stationKeys[index],
                              displayLabels[index],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.05,
                              fontWeight: isReached
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isReached
                                  ? AppColors.completedText
                                  : Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStationWidget(
    AuditSessionProvider provider,
    List<String> stationKeys,
    int index,
  ) {
    final session = provider.currentSession!;
    final stationKey = stationKeys[index];
    CustomersProvider? customersProvider;
    try {
      customersProvider = context.read<CustomersProvider>();
    } on ProviderNotFoundException {
      customersProvider = null;
    }
    final flock = customersProvider?.flockById(session.flockId);
    final sessionFlockAgeWeeks = session.flockAgeWeeks;
    final resolvedFlockAgeWeeks =
        sessionFlockAgeWeeks != null && sessionFlockAgeWeeks > 0
        ? sessionFlockAgeWeeks
        : flock?.currentAgeWeeks.toInt();
    final sessionBreed = session.breed;

    final auditContext = AuditContextData(
      auditType:
          AuditSessionProvider.stationKeyToAuditType[stationKey] ?? 'Egg',
      customerId: session.customerId,
      flockId: session.flockId,
      hatcheryId: session.hatcheryId,
      sessionId: session.id,
      breed: sessionBreed != null && sessionBreed.trim().isNotEmpty
          ? sessionBreed
          : flock?.breed,
      setterId: null,
      hatcherId: null,
      flockEntryDate: flock?.entryDate,
      flockAgeWeeks: resolvedFlockAgeWeeks,
      date: session.date.toIso8601String().split('T')[0],
    );

    final stationProvider = _stationAuditProviders.putIfAbsent(stationKey, () {
      final p = AuditProvider();
      return p;
    });

    return ChangeNotifierProvider.value(
      key: ValueKey('${session.id}:$stationKey'),
      value: stationProvider,
      child: _StationFrame(
        stationKey: stationKey,
        context: auditContext,
        sessionId: session.id,
        panelSampleRepository: _panelSampleRepository,
        eggStorageController: stationKey == 'egg'
            ? _eggStorageControllers.putIfAbsent(
                stationKey,
                EggStorageStationController.new,
              )
            : null,
      ),
    );
  }

  Widget _buildNavigationFooter(
    AuditSessionProvider provider,
    List<String> stationKeys,
  ) {
    final index = provider.currentStationIndex;
    final isLast = index == stationKeys.length - 1;
    final isFirst = index == 0;
    final stationProvider = _currentStationProvider;

    return Container(
      key: const ValueKey('audit-session-navigation-footer'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (!isFirst)
              OutlinedButton.icon(
                key: const ValueKey('audit-session-back-action'),
                onPressed: provider.isMovingToStation || _isSavingStation
                    ? null
                    : () => _handlePreviousStation(provider),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            if (!isFirst) const SizedBox(width: 12),
            if (stationProvider != null) ...[
              ChangeNotifierProvider<AuditProvider>.value(
                value: stationProvider,
                child: const AuditAutosaveStatus(),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ElevatedButton.icon(
                key: const ValueKey('audit-session-next-action'),
                onPressed: provider.isMovingToStation || _isSavingStation
                    ? null
                    : () {
                        _handleNextOrSave(provider);
                      },
                icon: _isSavingStation
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(isLast ? Icons.save : Icons.arrow_forward, size: 18),
                label: Text(
                  _isSavingStation
                      ? 'Saving...'
                      : (isLast ? 'Save' : 'Next Station'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStationGoveeEntryPoint(
    AuditSessionProvider provider,
    List<String> stationKeys,
  ) {
    if (stationKeys.isEmpty ||
        provider.currentStationIndex < 0 ||
        provider.currentStationIndex >= stationKeys.length) {
      return const SizedBox.shrink();
    }

    final session = provider.currentSession;
    if (session == null) return const SizedBox.shrink();

    final stationKey = stationKeys[provider.currentStationIndex];
    final spot = goveeSpotForStationKey(stationKey);
    if (spot == null) return const SizedBox.shrink();

    return Material(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: InkWell(
          key: const ValueKey('audit-open-govee-readings'),
          onTap: () async {
            final goveeProvider = context.read<GoveeCaptureProvider>();
            final machineId = _machineIdForStation(stationKey);
            await goveeProvider.configure(
              customerId: session.customerId,
              hatcheryId: session.hatcheryId,
              place: spot.place,
              stationKey: stationKey,
              machineId: machineId,
            );
            if (!mounted) return;
            await openGoveeFloatingCapturePanel(context);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderDefault),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Govee readings',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _machineIdForStation(String stationKey) {
    final stationProvider = _stationAuditProviders[stationKey];
    if (stationProvider == null || stationProvider.drafts.isEmpty) {
      return null;
    }
    final draft = stationProvider.activeDraft;
    return switch (stationKey) {
      'setters' => draft.setterId ?? draft.soSetterId,
      'hatchers' => draft.hatcherId ?? draft.hoHatcherId,
      _ => null,
    };
  }

  Future<void> _handleBackNavigation(BuildContext context) async {
    final shouldLeave = await _confirmStationExit();
    if (!shouldLeave) return;
    if (!mounted) return;

    final sessionProvider = this.context.read<AuditSessionProvider>();
    final sessionId = sessionProvider.currentSession?.id;
    Navigator.of(this.context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (sessionProvider.currentSession?.id == sessionId) {
        sessionProvider.clearCurrentSession();
      }
    });
  }

  Future<void> _handleNextOrSave(AuditSessionProvider provider) async {
    if (_isSavingStation) return;
    final shouldContinue = await _confirmStationExit();
    if (!shouldContinue) return;

    await provider.markCurrentStationCompleted();

    final isLast =
        provider.currentStationIndex == provider.stationKeys.length - 1;

    if (!isLast) {
      provider.goToNextStation();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.stationTransitionComplete();
      });
    } else {
      await provider.completeSession();
      if (!mounted) return;
      setState(() => _showSavedAnimation = true);
      await Future.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;
      Navigator.of(context).popUntil(auditSessionCompletionRoutePredicate);
    }
  }

  Future<void> _handlePreviousStation(AuditSessionProvider provider) async {
    final shouldMove = await _confirmStationExit();
    if (!shouldMove) return;

    provider.goToPreviousStation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.stationTransitionComplete();
    });
  }

  Future<void> _handleStationTap(
    AuditSessionProvider provider,
    int stationIndex,
    List<String> stationKeys,
  ) async {
    if (stationIndex == provider.currentStationIndex) return;

    final shouldMove = await _confirmStationExit();
    if (!shouldMove) return;

    provider.goToStation(stationIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.stationTransitionComplete();
    });
  }

  Future<bool> _confirmStationExit() async {
    final stationAuditProvider = _currentStationProvider;
    if (stationAuditProvider == null) return true;

    if (!mounted) return false;

    setState(() => _isSavingStation = true);
    var saved = false;
    try {
      final prepared = await _prepareCurrentStationForExit();
      saved = prepared ? await _saveCurrentStation() : false;
      if (!mounted) return false;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save station. Try again.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save station. Try again.')),
        );
      }
      saved = false;
    } finally {
      if (mounted) setState(() => _isSavingStation = false);
    }
    return saved;
  }

  Future<bool> _prepareCurrentStationForExit() async {
    final sessionProvider = context.read<AuditSessionProvider>();
    if (sessionProvider.currentSession == null) return true;
    final stationKey =
        sessionProvider.stationKeys[sessionProvider.currentStationIndex];
    if (stationKey != 'egg') return true;
    return _eggStorageControllers[stationKey]?.prepareForStationExit() ??
        Future.value(true);
  }

  Future<bool> _saveCurrentStation() async {
    final stationAuditProvider = _currentStationProvider;
    if (stationAuditProvider == null) return true;

    final stationKey =
        context.read<AuditSessionProvider>().currentSession == null
        ? null
        : context.read<AuditSessionProvider>().stationKeys[context
              .read<AuditSessionProvider>()
              .currentStationIndex];

    if (stationKey == 'hatch_analysis_egg_breakouts') {
      return stationAuditProvider.saveSamplesWithResult(markAllTabsSaved: true);
    }
    return stationAuditProvider.saveSamplesWithResult(tabIndex: 0);
  }

  String _shortStationLabel(String label) {
    final parts = label.split(' ');
    if (parts.length <= 2) return label;
    return parts.take(2).join(' ');
  }

  String _progressStationLabel(String stationKey, String label) {
    if (stationKey == 'hatch_analysis_egg_breakouts') return 'Hatch';
    return _shortStationLabel(label);
  }
}

class _StationFrame extends StatefulWidget {
  final String stationKey;
  final AuditContextData context;
  final String sessionId;
  final PanelSampleRepository panelSampleRepository;
  final EggStorageStationController? eggStorageController;

  const _StationFrame({
    required this.stationKey,
    required this.context,
    required this.sessionId,
    required this.panelSampleRepository,
    this.eggStorageController,
  });

  @override
  State<_StationFrame> createState() => _StationFrameState();
}

class _StationFrameState extends State<_StationFrame> {
  late Future<_StationInitialData> _initialDataFuture;

  @override
  void initState() {
    super.initState();
    _initialDataFuture = _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant _StationFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.stationKey != widget.stationKey) {
      _initialDataFuture = _loadInitialData();
    }
  }

  Future<_StationInitialData> _loadInitialData() async {
    try {
      final rowsByPanel = <String, List<Map<String, dynamic>>>{};
      for (final table in _panelTablesForStation(widget.stationKey)) {
        rowsByPanel[table] = await widget.panelSampleRepository
            .getRowsBySessionId(table, widget.sessionId);
      }
      final stationAudits = _auditDraftsFromPanelRows(rowsByPanel)
        ..sort((a, b) => a.hatchNumber.compareTo(b.hatchNumber));
      final samples = _stationSamplesFromPanelRows(rowsByPanel);
      return _StationInitialData(
        stationAudits: stationAudits,
        stationSamples: samples,
      );
    } catch (_) {
      return const _StationInitialData();
    }
  }

  List<String> _panelTablesForStation(String stationKey) {
    return switch (stationKey) {
      'egg' => const ['egg_storage', 'egg_quality'],
      'chicks' => const [
        'chick_pasgar',
        'chick_weights',
        'chick_yfbm',
        'chick_cvt',
        'chick_pm',
      ],
      'hatch_analysis_egg_breakouts' => const [
        'fresh_egg_breakout',
        'candled_egg_breakout',
        'residue_breakout',
      ],
      'setters' => const ['setter_optimizing'],
      'hatchers' => const ['hatcher_optimizing'],
      _ => const [],
    };
  }

  List<AuditModel> _auditDraftsFromPanelRows(
    Map<String, List<Map<String, dynamic>>> rowsByPanel,
  ) {
    final grouped = <int, List<({String table, Map<String, dynamic> row})>>{};
    for (final entry in rowsByPanel.entries) {
      for (final row in entry.value) {
        final index = _asInt(row['sampleIndex']) ?? 0;
        grouped
            .putIfAbsent(
              index,
              () => <({String table, Map<String, dynamic> row})>[],
            )
            .add((table: entry.key, row: row));
      }
    }
    return [
      for (final entry in grouped.entries)
        AuditModel.fromMap(_auditMapFromPanelRows(entry.key, entry.value)),
    ];
  }

  Map<String, dynamic> _auditMapFromPanelRows(
    int sampleIndex,
    List<({String table, Map<String, dynamic> row})> records,
  ) {
    final first = records.first.row;
    final createdAt =
        first['createdAt']?.toString() ?? DateTime.now().toIso8601String();
    final updatedAt = records
        .map((record) => record.row['updatedAt']?.toString())
        .where((value) => value != null && value.isNotEmpty)
        .cast<String>()
        .fold<String>(createdAt, (latest, value) {
          return value.compareTo(latest) > 0 ? value : latest;
        });
    final mode = first['mode']?.toString() == 'comparison'
        ? 'comparison'
        : 'pool';
    final map = <String, dynamic>{
      'id': '${widget.sessionId}:${widget.stationKey}:$sampleIndex',
      'auditType': widget.context.auditType,
      'customerId': first['customerId'] ?? widget.context.customerId,
      'flockId': first['flockId'] ?? widget.context.flockId,
      'date': first['date'] ?? widget.context.date,
      'status': 'completed',
      'createdBy': 'panel',
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sessionId': widget.sessionId,
      'sampleMode': mode,
      'compareGroupKey': first['groupKey'],
      'hatchNumber': sampleIndex + 1,
      'notes': first['notes'],
    };

    for (final record in records) {
      _mergePanelRowIntoAuditMap(map, record.table, record.row);
    }
    return map;
  }

  void _mergePanelRowIntoAuditMap(
    Map<String, dynamic> map,
    String table,
    Map<String, dynamic> row,
  ) {
    void copy(String target, String source) {
      final value = row[source];
      if (value != null) map[target] = value;
    }

    switch (table) {
      case 'egg_storage':
        copy('esEggStorageDays', 'storageDays');
        copy('es_estReadingsJson', 'estReadingsJson');
        copy('es_estAvg', 'estAvg');
        copy('es_estCv', 'estCvPct');
        copy('esShellTemp', 'shellTemp');
        copy('esTurningTimes', 'turningTimes');
        copy('es_traySpacing', 'traySpacing');
        copy('es_coolerProximity', 'coolerProximity');
        copy('es_condensation', 'condensationPresent');
        _mergeEggTraySummary(map, {'upsideDown': row['upsideDownCount']});
        break;
      case 'egg_quality':
        copy('es_uvSampleSize', 'uvTrayEggCount');
        copy('es_uvCuticleDamageCount', 'uvCuticleDamageCount');
        copy('es_uvWashingEvidenceCount', 'uvWashedCount');
        copy('es_uvFecalCount', 'uvDirtyCount');
        _mergeEggTraySummary(map, {
          'totalEggs': row['uvTrayEggCount'],
          'cuticleDamage': row['uvCuticleDamageCount'],
          'washed': row['uvWashedCount'],
          'dirty': row['uvDirtyCount'],
        });
        copy('esEggWeights', 'eggWeightsJson');
        copy('esEggSampleSize', 'eggSampleSize');
        copy('esEggAvgWeight', 'eggAvgWeight');
        copy('esEggUniformityPct', 'eggUniformityPct');
        copy('esEggCvPct', 'eggCvPct');
        copy('esEggBmkAge', 'eggBmkAgeWeeks');
        copy('esEggBmkWeight', 'eggBmkWeight');
        break;
      case 'chick_pasgar':
        copy('pasgarSampleSize', 'sampleSize');
        copy('pasgarReflexes', 'reflexesCount');
        copy('pasgarBeak', 'beakCount');
        copy('pasgarNavel', 'navelCount');
        copy('pasgarBelly', 'bellyCount');
        copy('pasgarLeg', 'legCount');
        copy('pasgarFeatherDev', 'featherDevCount');
        copy('pasgarFinalScore', 'finalScore');
        break;
      case 'chick_weights':
        copy('chickWeights', 'weightsJson');
        copy('chickSampleSize', 'sampleSize');
        copy('chickAvgWeight', 'avgWeight');
        copy('chickUniformityPct', 'uniformityPct');
        copy('chickCvPct', 'cvPct');
        copy('chickBmkAge', 'bmkAgeWeeks');
        copy('chickBmkWeight', 'bmkWeight');
        break;
      case 'chick_yfbm':
        copy('yfbmEntries', 'entriesJson');
        copy('yfbmAvgPct', 'avgPct');
        copy('yfbmCvPct', 'cvPct');
        break;
      case 'chick_cvt':
        copy('cvtReadingsJson', 'readingsJson');
        copy('cvtSampleSize', 'sampleSize');
        copy('cvtAvg', 'avgTemp');
        copy('cvtCvPct', 'cvPct');
        break;
      case 'chick_pm':
        for (final key in row.keys) {
          if (_pmKeys.contains(key)) map['pm_$key'] = row[key];
        }
        break;
      case 'fresh_egg_breakout':
        _mergeBreakoutRow(map, row, 'freshEggBreakout');
        break;
      case 'candled_egg_breakout':
        _mergeBreakoutRow(map, row, 'candledEggBreakout');
        break;
      case 'residue_breakout':
        _mergeBreakoutRow(map, row, 'residueHatchDay');
        copy('setterId', 'setterId');
        copy('hatcherId', 'hatcherId');
        copy('haTotalEggsSet', 'totalEggsSet');
        copy('haHatched', 'hatchedCount');
        copy('haCulled', 'culledCount');
        copy('haDead', 'deadCount');
        copy('haHatchability', 'hatchabilityPct');
        copy('haFertility', 'fertilityPct');
        copy('haHof', 'hofPct');
        break;
      case 'setter_optimizing':
        copy('setterId', 'setterId');
        copy('soSetterId', 'setterId');
        copy('so_machineType', 'machineType');
        copy('so_setpointF', 'setpointF');
        copy('so_actualF', 'actualF');
        copy('so_batchSize', 'batchSize');
        copy('so_batchCount', 'batchCount');
        copy('so_totalEggsSet', 'totalEggsSet');
        copy('so_turningAngle', 'turningAngle');
        copy('soCo2', 'co2Ppm');
        copy('soBreed', 'estBreed');
        copy('soIncubationAge', 'incubationAgeDays');
        copy('soIncubationHours', 'incubationHours');
        copy('soEstReadings', 'estReadingsJson');
        copy('soEstAvg', 'estAvg');
        copy('soEstCv', 'estCvPct');
        break;
      case 'hatcher_optimizing':
        copy('hatcherId', 'hatcherId');
        copy('hoHatcherId', 'hatcherId');
        copy('hoIncubationAge', 'incubationAgeDays');
        copy('hoIncubationHours', 'incubationHours');
        copy('hoCo2', 'co2Ppm');
        copy('hoCvtReadings', 'cvtReadingsJson');
        copy('hoCvtAvg', 'cvtAvg');
        copy('hoCvtCv', 'cvtCvPct');
        copy('hoChickPanting', 'chickPanting');
        copy('ho_meconium', 'meconium');
        break;
    }
  }

  void _mergeEggTraySummary(
    Map<String, dynamic> auditMap,
    Map<String, Object?> values,
  ) {
    final merged = <String, Object?>{
      ..._firstEggTraySummary(auditMap['esUvTrays']),
      ...values,
    }..removeWhere((_, value) => value == null);
    if (merged.isEmpty) return;
    auditMap['esUvTrays'] = jsonEncode([merged]);
  }

  Map<String, Object?> _firstEggTraySummary(Object? raw) {
    if (raw == null) return const {};
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return Map<String, Object?>.from(decoded.first as Map);
      }
    } catch (_) {
      return const {};
    }
    return const {};
  }

  void _mergeBreakoutRow(
    Map<String, dynamic> map,
    Map<String, dynamic> row,
    String breakoutType,
  ) {
    void copy(String target, String source) {
      final value = row[source];
      if (value != null) map[target] = value;
    }

    map['ebBreakoutType'] = breakoutType;
    copy('ebStorageDays', 'storageDays');
    copy('ebBreakoutAgeDays', 'bmkAgeDays');
    copy('ebBmkAge', 'bmkAgeWeeks');
    copy('ebTraySize', 'traySize');
    copy('ebInfertileCount', 'infertileCount');
    copy('ebEarlyDeadCount', 'earlyDeadCount');
    copy('ebMidDeadCount', 'midDeadCount');
    copy('ebLateDeadCount', 'lateDeadCount');
    copy('ebExternalPipCount', 'externalPipCount');
    copy('ebCrackedCount', 'crackedCount');
    copy('ebContaminatedCount', 'contaminatedCount');
    if (row['early24hCount'] != null || row['early48hCount'] != null) {
      map['ebEarlyDeadCount'] = row['early24hCount'];
      map['ebMidDeadCount'] = row['early48hCount'];
      map['ebLateDeadCount'] = row['bloodRingCount'];
    }
  }

  List<StationSampleModel> _stationSamplesFromPanelRows(
    Map<String, List<Map<String, dynamic>>> rowsByPanel,
  ) {
    final primaryEntry = rowsByPanel.entries.firstWhere(
      (entry) => entry.value.isNotEmpty,
      orElse: () => const MapEntry('', []),
    );
    if (primaryEntry.value.isEmpty) return const [];
    return [
      for (final row in primaryEntry.value)
        _sampleFromPanelRow(primaryEntry.key, row),
    ];
  }

  StationSampleModel _sampleFromPanelRow(
    String table,
    Map<String, dynamic> row,
  ) {
    final scopeType = row['scopeType']?.toString() ?? 'pool';
    final sampleMode = row['mode']?.toString() == 'comparison'
        ? StationSampleModel.sampleModeComparison
        : StationSampleModel.sampleModePooled;
    return StationSampleModel(
      id:
          row['id']?.toString() ??
          '${widget.sessionId}:$table:${row['sampleIndex']}',
      auditSessionId: widget.sessionId,
      stationType: widget.stationKey,
      sectorType: _sectorTypeForTable(table),
      sampleKind: _sampleKindForScope(scopeType),
      sampleMode: sampleMode,
      comparisonType: _comparisonTypeForScope(scopeType),
      sampleIndex: _asInt(row['sampleIndex']) ?? 0,
      sampleLabel: row['scopeLabel']?.toString(),
      sampleType: _sampleTypeForTable(table),
      breakoutType: _breakoutTypeForTable(table),
      groupKey: row['groupKey']?.toString(),
      groupLabel: row['groupLabel']?.toString(),
      houseNo: scopeType == 'house' ? row['scopeLabel']?.toString() : null,
      houseLabel: scopeType == 'house' ? row['scopeLabel']?.toString() : null,
      storageDays: _asInt(row['storageDays']),
      incubationDay: _asInt(row['incubationAgeDays'] ?? row['bmkAgeDays']),
      setterNo: row['setterId']?.toString(),
      hatcherNo: row['hatcherId']?.toString(),
      notes: row['notes']?.toString(),
      createdAt: _parseDate(row['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updatedAt']) ?? DateTime.now(),
    );
  }

  String _sectorTypeForTable(String table) {
    return switch (table) {
      'egg_quality' => StationSampleModel.sectorEggQuality,
      'chick_weights' => StationSampleModel.sectorChickWeights,
      'fresh_egg_breakout' ||
      'candled_egg_breakout' ||
      'residue_breakout' => StationSampleModel.sectorHatchBreakout,
      'setter_optimizing' => StationSampleModel.sectorSetterOptimizing,
      'hatcher_optimizing' => StationSampleModel.sectorHatcherOptimizing,
      'chick_pasgar' ||
      'chick_yfbm' ||
      'chick_cvt' ||
      'chick_pm' => StationSampleModel.sectorChickQuality,
      _ => StationSampleModel.sectorDefault,
    };
  }

  String _sampleKindForScope(String scopeType) {
    return switch (scopeType) {
      'house' => StationSampleModel.sampleKindHouse,
      'setter' ||
      'hatcher' ||
      'setter_hatcher' => StationSampleModel.sampleKindMachine,
      'tray' => StationSampleModel.sampleKindTray,
      'batch' => StationSampleModel.sampleKindBatch,
      _ => StationSampleModel.sampleKindPooled,
    };
  }

  String? _comparisonTypeForScope(String scopeType) {
    return switch (scopeType) {
      'house' => StationSampleModel.comparisonTypeHouse,
      'setter' ||
      'hatcher' ||
      'setter_hatcher' => StationSampleModel.comparisonTypeMachine,
      'tray' => StationSampleModel.comparisonTypeTray,
      'batch' => StationSampleModel.comparisonTypeBatch,
      _ => null,
    };
  }

  String? _sampleTypeForTable(String table) {
    return switch (table) {
      'chick_pasgar' ||
      'chick_weights' ||
      'chick_yfbm' ||
      'chick_cvt' ||
      'chick_pm' => StationSampleModel.sampleTypeChickQualityHatchedBatch,
      'fresh_egg_breakout' => StationSampleModel.sampleTypeBreakoutFresh,
      'candled_egg_breakout' => StationSampleModel.sampleTypeBreakoutCandled10d,
      'residue_breakout' => StationSampleModel.sampleTypeBreakoutResidue21d,
      _ => StationSampleModel.sampleTypeDefault,
    };
  }

  String? _breakoutTypeForTable(String table) {
    return switch (table) {
      'fresh_egg_breakout' => StationSampleModel.breakoutTypeFresh,
      'candled_egg_breakout' => StationSampleModel.breakoutTypeCandled10d,
      'residue_breakout' => StationSampleModel.breakoutTypeResidue21d,
      _ => null,
    };
  }

  DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  static const _pmKeys = {
    'sampleSize',
    'collectionPoint',
    'omphalitisCount',
    'omphalitisSeverity',
    'gaseousCecaCount',
    'gaseousCecaSeverity',
    'unabsorbedYolkCount',
    'unabsorbedYolkSeverity',
    'perihepatitisCount',
    'perihepatitisSeverity',
    'pericarditisCount',
    'pericarditisSeverity',
    'airsacAcuteCount',
    'airsacAcuteSeverity',
    'airsacChronicCount',
    'airsacChronicSeverity',
    'pulmonaryGranulomaCount',
    'pulmonaryGranulomaSeverity',
    'swollenJointsCount',
    'swollenJointsSeverity',
    'stuntedOrgansCount',
    'stuntedOrgansSeverity',
    'pulmonaryHemorrhageCount',
    'pulmonaryHemorrhageSeverity',
    'gizzardErosionsCount',
    'gizzardErosionsSeverity',
    'airSacCaseationsCount',
    'airSacCaseationsSeverity',
    'nephritisCount',
    'nephritisSeverity',
    'generalSepticemiaCount',
    'generalSepticemiaSeverity',
    'gaspingPresent',
    'gaspingType',
    'exposedBrainCount',
    'ectopicVisceraCount',
    'extraLegsCount',
    'crossedBeakCount',
    'absentEyeBothCount',
    'absentEyeOneCount',
    'smallEyeCount',
    'hydrocephalyCount',
    'starGazerCount',
    'curledToesCount',
    'shortLegsCount',
    'spinalDeformityCount',
    'cardiacAnomalyCount',
    'conjoinedCount',
    'otherDeformityCount',
    'otherDeformityText',
    'suspectedCauseAuto',
    'suspectedCauseManual',
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StationInitialData>(
      future: _initialDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final initialData = snapshot.data ?? const _StationInitialData();
        final stationWidget = _buildStationWidget(initialData);
        return stationWidget ??
            const Center(child: Text('Station not available'));
      },
    );
  }

  Widget? _buildStationWidget(_StationInitialData initialData) {
    final initialAudit = initialData.stationAudits.isEmpty
        ? null
        : initialData.stationAudits.first;

    switch (widget.stationKey) {
      case 'egg':
        return EggStorageScreen(
          context: widget.context,
          initialAudit: initialAudit,
          initialAudits: initialData.stationAudits,
          initialStationSamples: initialData.stationSamples,
          stationController: widget.eggStorageController,
        );
      case 'chicks':
        return ChickQualityScreen(
          context: widget.context,
          initialAudit: initialAudit,
          initialAudits: initialData.stationAudits,
          initialStationSamples: initialData.stationSamples,
        );
      case 'hatch_analysis_egg_breakouts':
        return HatchAnalysisScreen(
          context: widget.context,
          initialAudit: initialAudit,
          initialAudits: initialData.stationAudits,
          initialStationSamples: initialData.stationSamples,
        );
      case 'setters':
        return SetterOptimizingScreen(
          context: widget.context,
          initialAudit: initialAudit,
          initialAudits: initialData.stationAudits,
          initialStationSamples: initialData.stationSamples,
        );
      case 'hatchers':
        return HatcherOptimizingScreen(
          context: widget.context,
          initialAudit: initialAudit,
        );
      default:
        return null;
    }
  }
}

class _StationInitialData {
  final List<AuditModel> stationAudits;
  final List<StationSampleModel> stationSamples;

  const _StationInitialData({
    this.stationAudits = const [],
    this.stationSamples = const [],
  });
}
