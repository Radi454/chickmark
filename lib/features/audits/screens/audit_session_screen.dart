import 'dart:convert';

import 'package:flutter/material.dart';
import '../widgets/audit_access_guard.dart';
import 'package:provider/provider.dart';

import '../../../core/security/safe_debug_log.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/panel_dashboard_repository.dart';
import '../../../data/repositories/panel_sample_repository.dart';
import '../../../data/repositories/station_sample_repository.dart';
import '../../customers/screens/visit_detail_screen.dart';
import '../../dashboard/models/visit_session_summary.dart';
import '../../dashboard/providers/dashboard_provider.dart';
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
import '../../audits/widgets/audit_station_scroll_view.dart';
import '../../govee/providers/govee_capture_provider.dart';
import '../../govee/widgets/govee_floating_launcher.dart';
import '../../../providers/customers_provider.dart';
import '../models/egg_breakout_sample.dart';
import '../models/station_completion_validation.dart';

bool auditSessionCompletionRoutePredicate(Route<dynamic> route) {
  return route.settings.name == '/main' || route.isFirst;
}

class AuditSessionScreen extends StatefulWidget {
  final AuditRepository? auditRepository;
  final StationSampleRepository? stationSampleRepository;
  final PanelSampleRepository? panelSampleRepository;

  const AuditSessionScreen({
    super.key,
    this.auditRepository,
    this.stationSampleRepository,
    this.panelSampleRepository,
  });

  @override
  State<AuditSessionScreen> createState() => _AuditSessionScreenState();
}

enum _StationExitIntent { back, jump, forward, finalSave }

class _StationExitDecision {
  final StationCompletionValidation validation;
  final bool confirmed;

  const _StationExitDecision({
    required this.validation,
    required this.confirmed,
  });

  bool get canMove => confirmed && validation.canNavigate;
}

class _AuditSessionScreenState extends State<AuditSessionScreen> {
  final Map<String, AuditProvider> _stationAuditProviders = {};
  final Map<String, EggStorageStationController> _eggStorageControllers = {};
  final Set<String> _mountedStationKeys = <String>{};
  final PanelDashboardRepository _panelDashboardRepository =
      PanelDashboardRepository();
  String? _mountedSessionId;
  bool _showSavedAnimation = false;
  bool _isSavingStation = false;
  bool _isClearingStation = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChanged);
    _resetMountedStationState();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
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
    if (!AuditAccess.allowed(context)) return const AuditAccessDenied();
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
          final showProgress = stationKeys.isNotEmpty;
          final hideStationChrome = _shouldHideStationChrome(context);

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
                      if (!hideStationChrome)
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
                      if (!hideStationChrome)
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
      _resetMountedStationState();
      _mountedSessionId = sessionId;
    }

    _mountedStationKeys.removeWhere((key) => !stationKeys.contains(key));
    if (currentStationKey != null) {
      _mountedStationKeys.add(currentStationKey);
    }
  }

  void _resetMountedStationState() {
    for (final provider in _stationAuditProviders.values) {
      provider.dispose();
    }
    _stationAuditProviders.clear();
    _eggStorageControllers.clear();
    _mountedStationKeys.clear();
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
    return GradientAppBar(
      title: title,
      actions: provider.isSessionComplete
          ? [
              IconButton(
                tooltip: 'View final results',
                icon: const Icon(Icons.dashboard_outlined),
                onPressed: () => _openFinalResults(provider.currentSession!),
              ),
            ]
          : null,
    );
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
                  final nodeColor = isCurrent
                      ? AppColors.primary
                      : isReached
                      ? AppColors.completedText
                      : Colors.grey.shade300;

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
                              color: nodeColor,
                              border: isCurrent
                                  ? Border.all(
                                      color: AppColors.primaryLight,
                                      width: 2,
                                    )
                                  : null,
                              boxShadow: isCurrent
                                  ? const [
                                      BoxShadow(
                                        color: AppColors.cardShadowElevated,
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: isCurrent
                                  ? Container(
                                      key: ValueKey(
                                        'audit-session-progress-current-marker-$index',
                                      ),
                                      width: 13,
                                      height: 13,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                        border: Border.all(
                                          color: AppColors.primaryLight,
                                          width: 2,
                                        ),
                                      ),
                                    )
                                  : isReached
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
                              fontWeight: isCurrent
                                  ? FontWeight.w800
                                  : isReached
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isCurrent
                                  ? AppColors.primary
                                  : isReached
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
      final p = AuditProvider(
        panelSampleRepository: widget.panelSampleRepository,
      );
      return p;
    });

    return ChangeNotifierProvider.value(
      key: ValueKey('${session.id}:$stationKey'),
      value: stationProvider,
      child: _StationFrame(
        stationKey: stationKey,
        context: auditContext,
        sessionId: session.id,
        panelSampleRepository:
            widget.panelSampleRepository ?? PanelSampleRepository(),
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
    final isBusy =
        provider.isMovingToStation || _isSavingStation || _isClearingStation;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardOpen =
                auditStationKeyboardInset(context) > 0 ||
                _hasFocusedEditableText;
            final useKeyboardCompactFooter =
                keyboardOpen && constraints.maxWidth < 600;
            final useStackedFooter =
                constraints.maxWidth < 420 && !useKeyboardCompactFooter;

            Widget backButton({bool compact = false}) {
              final button = compact
                  ? OutlinedButton(
                      key: const ValueKey('audit-session-back-action'),
                      onPressed: isBusy
                          ? null
                          : () => _handlePreviousStation(provider),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        minimumSize: const Size(44, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Icon(Icons.arrow_back, size: 18),
                    )
                  : OutlinedButton.icon(
                      key: const ValueKey('audit-session-back-action'),
                      onPressed: isBusy
                          ? null
                          : () => _handlePreviousStation(provider),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
              return compact ? Tooltip(message: 'Back', child: button) : button;
            }

            Widget clearButton({bool compact = false}) {
              final icon = _isClearingStation
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 18);
              final button = compact
                  ? OutlinedButton(
                      key: const ValueKey('audit-session-clear-action'),
                      onPressed: isBusy || stationProvider == null
                          ? null
                          : () => _handleClearStation(provider),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.statusError,
                        side: const BorderSide(color: AppColors.statusError),
                        minimumSize: const Size(44, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: icon,
                    )
                  : OutlinedButton.icon(
                      key: const ValueKey('audit-session-clear-action'),
                      onPressed: isBusy || stationProvider == null
                          ? null
                          : () => _handleClearStation(provider),
                      icon: icon,
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.statusError,
                        side: const BorderSide(color: AppColors.statusError),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
              return compact
                  ? Tooltip(message: 'Clear station', child: button)
                  : button;
            }

            Widget nextButton({bool compact = false}) {
              return ElevatedButton.icon(
                key: const ValueKey('audit-session-next-action'),
                onPressed: isBusy
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
                      : _isClearingStation
                      ? 'Clearing...'
                      : (isLast ? 'Save' : 'Next Station'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: Size(44, compact ? 48 : 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }

            Widget? autosaveStatus() {
              if (stationProvider == null) return null;
              return ChangeNotifierProvider<AuditProvider>.value(
                value: stationProvider,
                child: const AuditAutosaveStatus(),
              );
            }

            if (useKeyboardCompactFooter) {
              return KeyedSubtree(
                key: const ValueKey('audit-session-footer-keyboard-mode'),
                child: Row(
                  children: [
                    if (!isFirst) ...[
                      SizedBox(width: 48, child: backButton(compact: true)),
                      const SizedBox(width: 8),
                    ],
                    SizedBox(width: 48, child: clearButton(compact: true)),
                    const SizedBox(width: 8),
                    Expanded(child: nextButton(compact: true)),
                  ],
                ),
              );
            }

            if (useStackedFooter) {
              final status = autosaveStatus();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (status != null) ...[
                    Align(alignment: Alignment.centerLeft, child: status),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      if (!isFirst) ...[
                        Expanded(child: backButton()),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: clearButton()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: nextButton()),
                ],
              );
            }

            final status = autosaveStatus();
            return Row(
              children: [
                if (!isFirst) ...[backButton(), const SizedBox(width: 12)],
                if (status != null) ...[status, const SizedBox(width: 12)],
                clearButton(),
                const SizedBox(width: 12),
                Expanded(child: nextButton()),
              ],
            );
          },
        ),
      ),
    );
  }

  bool get _hasFocusedEditableText {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    return focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _shouldHideStationChrome(BuildContext context) {
    return auditStationKeyboardInset(context) > 0 || _hasFocusedEditableText;
  }

  Future<void> _handleClearStation(AuditSessionProvider provider) async {
    if (_isSavingStation || _isClearingStation) return;
    if (provider.currentSession == null ||
        provider.currentStationIndex < 0 ||
        provider.currentStationIndex >= provider.stationKeys.length) {
      return;
    }
    final stationAuditProvider = _currentStationProvider;
    if (stationAuditProvider == null) return;

    final confirmed = await _showClearStationDialog();
    if (!confirmed || !mounted) return;

    final stationKey = provider.stationKeys[provider.currentStationIndex];
    setState(() => _isClearingStation = true);
    try {
      final cleared = await stationAuditProvider.clearStationData(stationKey);
      if (!mounted) return;
      if (!cleared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not clear station. Try again.')),
        );
        return;
      }
      await provider.removeCurrentStationCompletion();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Station cleared.')));
    } finally {
      if (mounted) setState(() => _isClearingStation = false);
    }
  }

  Future<bool> _showClearStationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear station?'),
          content: const Text('Fields and saved rows will be removed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.statusError,
              ),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
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
    final decision = await _confirmStationExit(intent: _StationExitIntent.back);
    if (!decision.canMove) return;
    if (!mounted) return;
    await _removeCompletionIfNeeded(
      this.context.read<AuditSessionProvider>(),
      decision,
    );
    if (!mounted) return;

    final sessionProvider = this.context.read<AuditSessionProvider>();
    final sessionId = sessionProvider.currentSession?.id;
    Navigator.of(this.context).pop();
    _clearSessionAfterRoutePop(sessionProvider, sessionId);
  }

  Future<void> _clearSessionAfterRoutePop(
    AuditSessionProvider sessionProvider,
    String? sessionId,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (sessionProvider.currentSession?.id == sessionId) {
      sessionProvider.clearCurrentSession();
    }
  }

  Future<void> _handleNextOrSave(AuditSessionProvider provider) async {
    if (_isSavingStation) return;
    final wasSessionCompleted = provider.isSessionComplete;
    final isLast =
        provider.currentStationIndex == provider.stationKeys.length - 1;

    // Reviewing a completed visit: Next is pure navigation. Skipping the
    // save/validate path keeps already-completed stations from being un-marked
    // when their persisted data no longer satisfies the latest core-data rules.
    if (wasSessionCompleted && !isLast) {
      provider.goToNextStation();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.stationTransitionComplete();
      });
      return;
    }

    final decision = await _confirmStationExit(
      intent: isLast
          ? _StationExitIntent.finalSave
          : _StationExitIntent.forward,
    );
    if (!decision.canMove) return;

    if (decision.validation.shouldMarkCompleted) {
      await provider.markCurrentStationCompleted();
    } else {
      await _removeCompletionIfNeeded(provider, decision);
    }

    if (!isLast) {
      provider.goToNextStation();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.stationTransitionComplete();
      });
    } else if (!decision.validation.shouldMarkCompleted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Station saved without completing the visit.'),
        ),
      );
    } else if (wasSessionCompleted) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Station saved.')));
    } else {
      await provider.completeSession();
      if (!mounted) return;
      setState(() => _showSavedAnimation = true);
      await Future.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;
      Navigator.of(context).popUntil(auditSessionCompletionRoutePredicate);
    }
  }

  Future<void> _openFinalResults(AuditSessionModel session) async {
    final panelRows = await _panelDashboardRepository.getPanelRowsBySession(
      session.id,
    );
    final visit = VisitSessionSummary.fromPanelRows(
      session: session,
      panelRowsByTable: panelRows,
    );

    if (!mounted) return;
    try {
      await context.read<DashboardProvider>().selectVisitSession(visit);
    } on ProviderNotFoundException {
      // The session screen is used in isolated tests without the dashboard tree.
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => VisitDetailScreen(visit: visit)),
    );
  }

  Future<void> _handlePreviousStation(AuditSessionProvider provider) async {
    final decision = await _confirmStationExit(intent: _StationExitIntent.back);
    if (!decision.canMove) return;
    await _removeCompletionIfNeeded(provider, decision);

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

    final decision = await _confirmStationExit(intent: _StationExitIntent.jump);
    if (!decision.canMove) return;
    await _removeCompletionIfNeeded(provider, decision);

    provider.goToStation(stationIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.stationTransitionComplete();
    });
  }

  Future<void> _removeCompletionIfNeeded(
    AuditSessionProvider provider,
    _StationExitDecision decision,
  ) async {
    if (decision.validation.shouldMarkCompleted) return;
    if (provider.isStationCompleted) {
      await provider.removeCurrentStationCompletion();
    }
  }

  Future<_StationExitDecision> _confirmStationExit({
    required _StationExitIntent intent,
  }) async {
    final sessionProvider = context.read<AuditSessionProvider>();
    final stationKey =
        sessionProvider.currentSession == null ||
            sessionProvider.currentStationIndex < 0 ||
            sessionProvider.currentStationIndex >=
                sessionProvider.stationKeys.length
        ? ''
        : sessionProvider.stationKeys[sessionProvider.currentStationIndex];
    final stationAuditProvider = _currentStationProvider;
    if (stationAuditProvider == null) {
      return _StationExitDecision(
        validation: StationCompletionValidation.complete(stationKey),
        confirmed: true,
      );
    }

    if (!mounted) {
      return _StationExitDecision(
        validation: StationCompletionValidation.failed(stationKey),
        confirmed: false,
      );
    }

    setState(() => _isSavingStation = true);
    var validation = StationCompletionValidation.failed(stationKey);
    try {
      final prepared = await _prepareCurrentStationForExit();
      final saved = prepared ? await _saveCurrentStation() : false;
      if (!mounted) {
        return _StationExitDecision(validation: validation, confirmed: false);
      }
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save station. Try again.')),
        );
      } else {
        validation = stationAuditProvider.validateStationCompletion(stationKey);
        if (validation.status == StationCompletionStatus.failed) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(validation.message)));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save station. Try again.')),
        );
      }
      validation = StationCompletionValidation.failed(stationKey);
    } finally {
      if (mounted) setState(() => _isSavingStation = false);
    }

    if (!validation.canNavigate || !mounted) {
      return _StationExitDecision(validation: validation, confirmed: false);
    }
    if (!validation.needsIncompleteConfirmation) {
      return _StationExitDecision(validation: validation, confirmed: true);
    }

    final confirmed = await _showIncompleteStationDialog(intent);
    return _StationExitDecision(
      validation: validation,
      confirmed: confirmed && mounted,
    );
  }

  Future<bool> _showIncompleteStationDialog(_StationExitIntent intent) async {
    final body = switch (intent) {
      _StationExitIntent.finalSave =>
        'This station was saved, but it does not have enough core data to complete the visit. Continue saving it as incomplete?',
      _StationExitIntent.forward =>
        'This station was saved, but it does not have enough core data to mark complete. Continue to the next station without completing it?',
      _StationExitIntent.jump =>
        'This station was saved, but it does not have enough core data to mark complete. Continue to the selected station without completing it?',
      _StationExitIntent.back =>
        'This station was saved, but it does not have enough core data to mark complete. Leave it incomplete and continue?',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Continue without completing?'),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
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
    } catch (e, st) {
      // Never silently swallow a reconstruction failure: a thrown mapper or
      // malformed row would otherwise look identical to "no saved data" and
      // leave the station blank with no trace. Log, then degrade to empty.
      safeDebugLog(
        'Failed reconstructing panel data for station ${widget.stationKey} '
        '(session ${widget.sessionId})',
        error: e,
        stackTrace: st,
      );
      return const _StationInitialData();
    }
  }

  List<String> _panelTablesForStation(String stationKey) {
    return switch (stationKey) {
      'egg' => const ['egg_storage', 'egg_quality'],
      'chicks' => const ['chick_quality', 'chick_weights'],
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
    final eggDrafts = _eggAuditDraftsFromPanelRows(rowsByPanel);
    if (eggDrafts != null) return eggDrafts;

    final grouped = <int, List<({String table, Map<String, dynamic> row})>>{};
    final groupIndexes = <String, int>{};
    for (final entry in rowsByPanel.entries) {
      for (final row in entry.value) {
        final index = widget.stationKey == 'hatch_analysis_egg_breakouts'
            ? 0
            : groupIndexes.putIfAbsent(
                _panelRowIdentityKey(row),
                () => groupIndexes.length,
              );
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
    final mode = _rowHasHierarchy(first) ? 'comparison' : 'pool';
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
      'compareGroupKey': _rowHasHierarchy(first)
          ? 'panel-hierarchy-${widget.sessionId}'
          : null,
      'hatchNumber': sampleIndex + 1,
      'notes': first['notes'],
    };

    for (final record in records) {
      _mergePanelRowIntoAuditMap(map, record.table, record.row);
    }
    return map;
  }

  List<AuditModel>? _eggAuditDraftsFromPanelRows(
    Map<String, List<Map<String, dynamic>>> rowsByPanel,
  ) {
    if (widget.stationKey != 'egg') return null;
    final qualityRows =
        rowsByPanel['egg_quality'] ?? const <Map<String, dynamic>>[];
    if (qualityRows.isEmpty) return null;

    final pooledStorageRecords =
        (rowsByPanel['egg_storage'] ?? const <Map<String, dynamic>>[])
            .where((row) => !_rowHasHierarchy(row))
            .map((row) => (table: 'egg_storage', row: row))
            .toList();

    return [
      for (final entry in qualityRows.asMap().entries)
        AuditModel.fromMap(
          _auditMapFromPanelRows(entry.key, [
            (table: 'egg_quality', row: entry.value),
            ...pooledStorageRecords,
          ]),
        ),
    ];
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
        copy('esEggStorageDays', 'storagePeriodDays');
        copy('es_estReadingsJson', 'estReadingsJson');
        copy('es_estAvg', 'estAvg');
        copy('es_estCv', 'estCvPct');
        copy('esTurningTimes', 'turningTimes');
        copy('es_traySpacing', 'traySpacing');
        copy('es_coolerProximity', 'coolerProximity');
        copy('es_condensation', 'condensationPresent');
        _mergeEggTraySummary(map, {'upsideDown': row['upsideDownCount']});
        break;
      case 'egg_quality':
        copy('esEggQualityStorageDays', 'storagePeriodDays');
        copy('es_uvSampleSize', 'uvTrayEggCount');
        copy('es_uvCuticleDamageCount', 'uvCuticleDamageCount');
        copy('es_uvWashingEvidenceCount', 'uvWashedCount');
        copy('es_uvFecalCount', 'uvDirtyCount');
        _mergeEggTraySummary(map, {
          'totalEggs': row['uvTrayEggCount'],
          'cuticleDamage': row['uvCuticleDamageCount'],
          'washed': row['uvWashedCount'],
          'dirty': row['uvDirtyCount'],
          'qualityTouched': true,
        });
        copy('esEggWeights', 'eggWeightsJson');
        copy('esEggSampleSize', 'eggSampleSize');
        copy('esEggAvgWeight', 'eggAvgWeight');
        copy('esEggUniformityPct', 'eggUniformityPct');
        copy('esEggCvPct', 'eggCvPct');
        copy('esEggBmkAge', 'eggBmkAgeWeeks');
        copy('esEggBmkWeight', 'eggBmkWeight');
        break;
      case 'chick_quality':
        copy('pasgarSampleSize', 'pasgarSampleSize');
        copy('pasgarReflexes', 'pasgarReflexesCount');
        copy('pasgarBeak', 'pasgarBeakCount');
        copy('pasgarNavel', 'pasgarNavelCount');
        copy('pasgarBelly', 'pasgarBellyCount');
        copy('pasgarLeg', 'pasgarLegCount');
        copy('pasgarFeatherDev', 'pasgarFeatherDevCount');
        copy('pasgarFinalScore', 'pasgarFinalScore');
        copy('yfbmPhoto', 'yfbmPhoto');
        copy('yfbmEntries', 'yfbmEntriesJson');
        copy('yfbmAvgPct', 'yfbmAvgPct');
        copy('yfbmCvPct', 'yfbmCvPct');
        copy('cvtReadingsJson', 'cvtReadingsJson');
        copy('cvtPhotosJson', 'cvtPhotosJson');
        copy('cvtSampleSize', 'cvtSampleSize');
        copy('cvtTopBasket', 'cvtTopBasket');
        copy('cvtTopTemp', 'cvtTopTemp');
        copy('cvtTopPhoto', 'cvtTopPhoto');
        copy('cvtMiddleBasket', 'cvtMiddleBasket');
        copy('cvtMiddleTemp', 'cvtMiddleTemp');
        copy('cvtMiddlePhoto', 'cvtMiddlePhoto');
        copy('cvtBottomBasket', 'cvtBottomBasket');
        copy('cvtBottomTemp', 'cvtBottomTemp');
        copy('cvtBottomPhoto', 'cvtBottomPhoto');
        copy('cvtAvg', 'cvtAvgTemp');
        copy('cvtCvPct', 'cvtCvPct');
        copy('pm_sampleSize', 'pmSampleSize');
        copy('pm_collectionPoint', 'pmCollectionPoint');
        copy('pm_omphalitisCount', 'pmOmphalitisCount');
        copy('pm_omphalitisSeverity', 'pmOmphalitisSeverity');
        copy('pm_gaseousCecaCount', 'pmGaseousCecaCount');
        copy('pm_gaseousCecaSeverity', 'pmGaseousCecaSeverity');
        copy('pm_unabsorbedYolkCount', 'pmUnabsorbedYolkCount');
        copy('pm_unabsorbedYolkSeverity', 'pmUnabsorbedYolkSeverity');
        copy('pm_perihepatitisCount', 'pmPerihepatitisCount');
        copy('pm_perihepatitisSeverity', 'pmPerihepatitisSeverity');
        copy('pm_pericarditisCount', 'pmPericarditisCount');
        copy('pm_pericarditisSeverity', 'pmPericarditisSeverity');
        copy('pm_airsacAcuteCount', 'pmAirsacAcuteCount');
        copy('pm_airsacAcuteSeverity', 'pmAirsacAcuteSeverity');
        copy('pm_airsacChronicCount', 'pmAirsacChronicCount');
        copy('pm_airsacChronicSeverity', 'pmAirsacChronicSeverity');
        copy('pm_pulmonaryGranulomaCount', 'pmPulmonaryGranulomaCount');
        copy('pm_pulmonaryGranulomaSeverity', 'pmPulmonaryGranulomaSeverity');
        copy('pm_swollenJointsCount', 'pmSwollenJointsCount');
        copy('pm_swollenJointsSeverity', 'pmSwollenJointsSeverity');
        copy('pm_stuntedOrgansCount', 'pmStuntedOrgansCount');
        copy('pm_stuntedOrgansSeverity', 'pmStuntedOrgansSeverity');
        copy('pm_pulmonaryHemorrhageCount', 'pmPulmonaryHemorrhageCount');
        copy('pm_pulmonaryHemorrhageSeverity', 'pmPulmonaryHemorrhageSeverity');
        copy('pm_gizzardErosionsCount', 'pmGizzardErosionsCount');
        copy('pm_gizzardErosionsSeverity', 'pmGizzardErosionsSeverity');
        copy('pm_airSacCaseationsCount', 'pmAirSacCaseationsCount');
        copy('pm_airSacCaseationsSeverity', 'pmAirSacCaseationsSeverity');
        copy('pm_urolithiasisCount', 'pmUrolithiasisCount');
        copy('pm_urolithiasisSeverity', 'pmUrolithiasisSeverity');
        copy('pm_nephritisCount', 'pmNephritisCount');
        copy('pm_nephritisSeverity', 'pmNephritisSeverity');
        copy('pm_generalSepticemiaCount', 'pmGeneralSepticemiaCount');
        copy('pm_generalSepticemiaSeverity', 'pmGeneralSepticemiaSeverity');
        copy('pm_otherLesionsJson', 'pmOtherLesionsJson');
        copy('pm_suspectedCauseAuto', 'pmSuspectedCauseAuto');
        copy('pm_suspectedCauseManual', 'pmSuspectedCauseManual');
        copy('pm_photosJson', 'pmPhotosJson');
        copy('culledChicksTotalEggSet', 'culledChicksTotalEggSet');
        copy('culledChicksAnalysisJson', 'culledChicksAnalysisJson');
        copy('culledChicksAffectedPct', 'culledChicksAffectedPct');
        copy('culledChicksTopCategory', 'culledChicksTopCategory');
        copy('culledChicksTopSubtype', 'culledChicksTopSubtype');
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
      case 'fresh_egg_breakout':
        _mergeBreakoutRow(map, row, 'freshEggBreakout');
        break;
      case 'candled_egg_breakout':
        _mergeBreakoutRow(map, row, 'candledEggBreakout');
        break;
      case 'residue_breakout':
        _mergeBreakoutRow(map, row, 'residueHatchDay');
        copy('setterId', 'setter');
        copy('hatcherId', 'hatcher');
        copy('haTotalEggsSet', 'totalEggsSet');
        copy('haHatched', 'hatchedCount');
        copy('haCulled', 'culledCount');
        copy('haDead', 'deadCount');
        copy('haHatchability', 'hatchabilityPct');
        copy('haFertility', 'fertilityPct');
        copy('haHof', 'hofPct');
        break;
      case 'setter_optimizing':
        copy('setterId', 'setter');
        copy('soSetterId', 'setter');
        copy('so_machineType', 'machineType');
        copy('so_setpointF', 'setpointF');
        copy('so_actualF', 'actualF');
        copy('so_setpointRh', 'setpointRh');
        copy('so_actualRh', 'actualRh');
        copy('so_batchSize', 'batchSize');
        copy('so_batchCount', 'batchCount');
        copy('so_totalEggsSet', 'totalEggsSet');
        copy('so_turningAngle', 'turningAngle');
        copy('soCo2', 'co2Ppm');
        copy('soCo2Photo', 'co2Photo');
        copy('soBreed', 'estBreed');
        copy('soIncubationAge', 'incubationAgeDays');
        copy('soIncubationHours', 'incubationHours');
        copy('soEstReadings', 'estReadingsJson');
        copy('soEstPhotos', 'estPhotosJson');
        copy('so_estSamplesJson', 'estSamplesJson');
        copy('soEstAvg', 'estAvg');
        copy('soEstCv', 'estCvPct');
        copy('so_machineScreenPhoto', 'machineScreenPhoto');
        break;
      case 'hatcher_optimizing':
        copy('hatcherId', 'hatcher');
        copy('hoHatcherId', 'hatcher');
        copy('ho_setpointF', 'setpointF');
        copy('ho_setpointRh', 'setpointRh');
        copy('hoIncubationAge', 'incubationAgeDays');
        copy('hoIncubationHours', 'incubationHours');
        copy('hoCo2', 'co2Ppm');
        copy('hoCo2Photo', 'co2Photo');
        copy('hoCvtReadings', 'cvtReadingsJson');
        copy('hoCvtPhotos', 'cvtPhotosJson');
        copy('hoCvtAvg', 'cvtAvg');
        copy('hoCvtCv', 'cvtCvPct');
        copy('hoChickPanting', 'chickPanting');
        copy('hoChickPantingPhoto', 'chickPantingPhoto');
        copy('ho_meconium', 'meconium');
        copy('ho_transferDay', 'transferDay');
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
    copy('ebStorageDays', 'storagePeriodDays');
    copy('haStorageDays', 'storagePeriodDays');
    copy('houseId', 'house');
    copy('setterId', 'setter');
    copy('hatcherId', 'hatcher');
    copy('ebBreakoutAgeDays', 'candlingDay');
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
    _mergeBreakoutTrayEntry(map, row, breakoutType);
  }

  void _mergeBreakoutTrayEntry(
    Map<String, dynamic> map,
    Map<String, dynamic> row,
    String breakoutType,
  ) {
    final type = EggBreakoutType.fromStorageValue(breakoutType);
    final counts = <String, int>{};
    void addCount(String key, String column) {
      final value = _asInt(row[column]);
      if (value != null && value > 0) counts[key] = value;
    }

    addCount('infertile', 'infertileCount');
    if (type == EggBreakoutType.residueHatchDay) {
      addCount('earlyDead', 'earlyDeadCount');
      addCount('midDead', 'midDeadCount');
      addCount('lateDead', 'lateDeadCount');
      addCount('externalPip', 'externalPipCount');
      addCount('cracked', 'crackedCount');
      addCount('contaminated', 'contaminatedCount');
    } else {
      addCount('early24h', 'early24hCount');
      addCount('early48h', 'early48hCount');
      addCount('early72hBloodRing', 'bloodRingCount');
      if (type == EggBreakoutType.candledEggBreakout) {
        addCount('blackEye', 'blackEyeCount');
      }
    }

    final existing = EggBreakoutSampleEntry.decodeList(
      map['ebTrayBreakoutJson']?.toString(),
      fallbackBreakoutType: type,
    );
    final label =
        _asText(row['tray']) ??
        _asText(row['scopeLabel']) ??
        'Tray ${existing.length + 1}';
    final next = EggBreakoutSampleEntry.tray(
      id: _asText(row['id']) ?? 'tray-${existing.length + 1}',
      label: label,
      house: _asText(row['house']),
      setter: _asText(row['setter']),
      hatcher: _asText(row['hatcher']),
      trolley: _asText(row['trolley']),
      tray: _asText(row['tray']) ?? label,
      position: _asText(row['position']),
      traySize: _asInt(row['traySize']),
      breakoutType: type,
      counts: counts,
    );
    map['ebTrayBreakoutJson'] = EggBreakoutSampleEntry.encodeList([
      ...existing,
      next,
    ]);
  }

  List<StationSampleModel> _stationSamplesFromPanelRows(
    Map<String, List<Map<String, dynamic>>> rowsByPanel,
  ) {
    final primaryEntry = _stationSampleSourceRows(rowsByPanel);
    if (primaryEntry.value.isEmpty) return const [];
    return [
      for (final entry in primaryEntry.value.asMap().entries)
        _sampleFromPanelRow(
          primaryEntry.key,
          entry.value,
          fallbackIndex: entry.key + 1,
        ),
    ];
  }

  MapEntry<String, List<Map<String, dynamic>>> _stationSampleSourceRows(
    Map<String, List<Map<String, dynamic>>> rowsByPanel,
  ) {
    if (widget.stationKey == 'egg') {
      final qualityRows = rowsByPanel['egg_quality'];
      if (qualityRows != null && qualityRows.isNotEmpty) {
        return MapEntry('egg_quality', qualityRows);
      }
    }
    return rowsByPanel.entries.firstWhere(
      (entry) => entry.value.isNotEmpty,
      orElse: () => const MapEntry('', []),
    );
  }

  StationSampleModel _sampleFromPanelRow(
    String table,
    Map<String, dynamic> row, {
    required int fallbackIndex,
  }) {
    final scopeType = _scopeTypeForRow(row);
    final sampleMode = _rowHasHierarchy(row)
        ? StationSampleModel.sampleModeComparison
        : StationSampleModel.sampleModePooled;
    final sampleIndex = _asInt(row['sampleIndex']) ?? fallbackIndex;
    final sampleLabel = _sampleLabelForRow(row) ?? 'Sample $sampleIndex';
    return StationSampleModel(
      id: row['id']?.toString() ?? '${widget.sessionId}:$table:$sampleIndex',
      auditSessionId: widget.sessionId,
      stationType: widget.stationKey,
      sectorType: _sectorTypeForTable(table),
      sampleKind: _sampleKindForScope(scopeType),
      sampleMode: sampleMode,
      comparisonType: _comparisonTypeForScope(scopeType),
      sampleIndex: sampleIndex,
      sampleLabel: sampleLabel,
      sampleType: _sampleTypeForTable(table),
      breakoutType: _breakoutTypeForTable(table),
      groupKey: _rowHasHierarchy(row)
          ? 'panel-hierarchy-${widget.sessionId}'
          : null,
      groupLabel: _rowHasHierarchy(row) ? 'Hierarchy comparison' : null,
      houseNo: _asText(row['house']),
      houseLabel: _asText(row['house']),
      storageDays: _asInt(row['storagePeriodDays']),
      incubationDay: _asInt(row['incubationAgeDays'] ?? row['candlingDay']),
      setterNo: _asText(row['setter']),
      hatcherNo: _asText(row['hatcher']),
      notes: row['notes']?.toString(),
      createdAt: _parseDate(row['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updatedAt']) ?? DateTime.now(),
    );
  }

  String _panelRowIdentityKey(Map<String, dynamic> row) {
    return [
      _asText(row['house']) ?? '',
      _asText(row['setter']) ?? '',
      _asText(row['hatcher']) ?? '',
      _asText(row['trolley']) ?? '',
      _asText(row['tray']) ?? '',
      _asText(row['position']) ?? '',
    ].join('|');
  }

  bool _rowHasHierarchy(Map<String, dynamic> row) {
    return _asText(row['house']) != null ||
        _asText(row['setter']) != null ||
        _asText(row['hatcher']) != null ||
        _asText(row['trolley']) != null ||
        _asText(row['tray']) != null ||
        _asText(row['position']) != null;
  }

  String _scopeTypeForRow(Map<String, dynamic> row) {
    if (_asText(row['tray']) != null) return 'tray';
    if (_asText(row['trolley']) != null) return 'trolley';
    if (_asText(row['setter']) != null && _asText(row['hatcher']) != null) {
      return 'setter_hatcher';
    }
    if (_asText(row['setter']) != null) return 'setter';
    if (_asText(row['hatcher']) != null) return 'hatcher';
    if (_asText(row['house']) != null) return 'house';
    return 'pool';
  }

  String? _sampleLabelForRow(Map<String, dynamic> row) {
    final setter = _asText(row['setter']);
    final hatcher = _asText(row['hatcher']);
    if (setter != null && hatcher != null) return '$setter$hatcher';
    return _asText(row['tray']) ??
        _asText(row['trolley']) ??
        setter ??
        hatcher ??
        _asText(row['house']);
  }

  String _sectorTypeForTable(String table) {
    return switch (table) {
      'egg_quality' => StationSampleModel.sectorEggQuality,
      'chick_weights' => StationSampleModel.sectorChickWeights,
      'chick_quality' => StationSampleModel.sectorChickQuality,
      'fresh_egg_breakout' ||
      'candled_egg_breakout' ||
      'residue_breakout' => StationSampleModel.sectorHatchBreakout,
      'setter_optimizing' => StationSampleModel.sectorSetterOptimizing,
      'hatcher_optimizing' => StationSampleModel.sectorHatcherOptimizing,
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
      'chick_quality' ||
      'chick_weights' ||
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

  String? _asText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

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
          initialAudits: initialData.stationAudits,
          initialStationSamples: initialData.stationSamples,
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
