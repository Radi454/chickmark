import 'package:hatchaudit/localized_material.dart';
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
import '../logic/egg_station_reconstruction.dart';
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
                        key: const ValueKey('audit-session-station-content'),
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
                tooltip: context.tr('View final results'),
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
      customersProvider = context.watch<CustomersProvider>();
    } on ProviderNotFoundException {
      customersProvider = null;
    }
    final flock = customersProvider?.flockById(session.flockId);
    final sessionFlockAgeWeeks = session.flockAgeWeeks;
    final currentFlockAgeWeeks = flock?.currentAgeWeeks.toInt();
    final resolvedFlockAgeWeeks =
        (currentFlockAgeWeeks != null && currentFlockAgeWeeks > 0
            ? currentFlockAgeWeeks
            : null) ??
        (sessionFlockAgeWeeks != null && sessionFlockAgeWeeks > 0
            ? sessionFlockAgeWeeks
            : null);
    final sessionBreed = session.breed;
    final flockBreed = flock?.breed.trim();

    final auditContext = AuditContextData(
      auditType:
          AuditSessionProvider.stationKeyToAuditType[stationKey] ?? 'Egg',
      customerId: session.customerId,
      flockId: session.flockId,
      hatcheryId: session.hatcheryId,
      sessionId: session.id,
      breed: flockBreed != null && flockBreed.isNotEmpty
          ? flockBreed
          : sessionBreed != null && sessionBreed.trim().isNotEmpty
          ? sessionBreed
          : null,
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
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: status,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      if (!isFirst) ...[
                        SizedBox(width: 48, child: backButton(compact: true)),
                        const SizedBox(width: 8),
                      ],
                      SizedBox(width: 48, child: clearButton(compact: true)),
                      const SizedBox(width: 8),
                      Expanded(child: nextButton(compact: true)),
                      // Spacer to prevent the floating action button from overlapping the Save button
                      const SizedBox(width: 64),
                    ],
                  ),
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
              flockId: session.flockId,
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
      final reconstruction = reconstructStation(
        stationKey: widget.stationKey,
        sessionId: widget.sessionId,
        context: widget.context,
        rowsByPanel: rowsByPanel,
      );
      return _StationInitialData(
        stationAudits: reconstruction.stationAudits,
        stationSamples: reconstruction.stationSamples,
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
          key: ValueKey(
            'chicks:${widget.sessionId}:${widget.context.breed ?? ''}:${widget.context.flockAgeWeeks ?? ''}',
          ),
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
