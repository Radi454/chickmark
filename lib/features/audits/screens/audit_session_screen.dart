import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/audit_repository.dart';
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
import '../../audits/widgets/audit_keyboard_dismiss.dart';
import '../../govee/providers/govee_capture_provider.dart';
import '../../govee/screens/govee_screen.dart';
import '../../../core/navigation/shell_navigation_scope.dart';

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
  late final AuditRepository _auditRepository =
      widget.auditRepository ?? AuditRepository();
  late final StationSampleRepository _stationSampleRepository =
      widget.stationSampleRepository ?? StationSampleRepository();
  bool _showSavedAnimation = false;
  bool _isSavingStation = false;

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
          final showProgress =
              currentStationKey != 'hatch_analysis_egg_breakouts' &&
              currentStationKey != 'chicks';

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
                        child: Stack(
                          children: List.generate(
                            stationKeys.length,
                            (i) => Offstage(
                              offstage:
                                  i != sessionProvider.currentStationIndex,
                              child: _buildStationWidget(
                                sessionProvider,
                                stationKeys,
                                i,
                              ),
                            ),
                          ),
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

  PreferredSizeWidget _buildAppBar(AuditSessionProvider provider) {
    final stationKey = provider.stationKeys.isNotEmpty
        ? provider.stationKeys[provider.currentStationIndex]
        : null;
    final title = stationKey != null
        ? (AuditSessionProvider.stationDisplayLabels[stationKey] ?? 'Visit')
        : 'Visit';
    return GradientAppBar(title: title, toolbarHeight: 88);
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
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.completedText,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 64),
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
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 22),
      color: Colors.white,
      child: Row(
        children: List.generate(stationKeys.length, (index) {
          final isCompleted = completed.contains(stationKeys[index]);
          final isCurrent = index == provider.currentStationIndex;
          final isPast = index < provider.currentStationIndex;
          final isReached = isCompleted || isCurrent || isPast;

          return Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: isPast || isCompleted || isCurrent
                        ? () => _handleStationTap(provider, index, stationKeys)
                        : null,
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
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
                                    size: 30,
                                    color: Colors.white,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _shortStationLabel(displayLabels[index]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isReached
                                ? FontWeight.w800
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
                ),
                if (index < stationKeys.length - 1)
                  Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.only(top: 28),
                      color: isReached
                          ? AppColors.completedText
                          : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          );
        }),
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

    final auditContext = AuditContextData(
      auditType:
          AuditSessionProvider.stationKeyToAuditType[stationKey] ?? 'Egg',
      customerId: session.customerId,
      flockId: session.flockId,
      hatcheryId: session.hatcheryId,
      sessionId: session.id,
      breed: session.breed,
      setterId: null,
      hatcherId: null,
      flockEntryDate: null,
      flockAgeWeeks: session.flockAgeWeeks,
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
        auditRepository: _auditRepository,
        stationSampleRepository: _stationSampleRepository,
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

    return Container(
      key: const ValueKey('audit-session-navigation-footer'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
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
                    horizontal: 16,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            if (!isFirst) const SizedBox(width: 12),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(64),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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

    return Container(
      color: const Color(0xFFF5F7FB),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('audit-open-govee-readings'),
        onPressed: () async {
          final goveeProvider = context.read<GoveeCaptureProvider>();
          final shell = ShellNavigationScope.maybeOf(context);
          final navigator = Navigator.of(context);
          await goveeProvider.configure(
            customerId: session.customerId,
            hatcheryId: session.hatcheryId,
            place: spot.place,
          );
          if (shell != null) {
            shell.switchTab(4);
            return;
          }
          if (!navigator.mounted) return;
          await navigator.push(
            MaterialPageRoute<void>(builder: (_) => const GoveeScreen()),
          );
        },
        icon: const Icon(Icons.device_thermostat_outlined),
        label: const Text('Govee readings'),
      ),
    );
  }

  Future<void> _handleBackNavigation(BuildContext context) async {
    final shouldLeave = await _confirmStationExit(
      title: 'Leave visit?',
      actionLabel: 'Save and leave',
    );
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
    final shouldContinue = await _confirmStationExit(
      title: 'Leave station?',
      actionLabel: 'Save and continue',
    );
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
    final shouldMove = await _confirmStationExit(
      title: 'Go back to previous station?',
      actionLabel: 'Save and go back',
    );
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

    final shouldMove = await _confirmStationExit(
      title: 'Switch stations?',
      actionLabel: 'Save and switch',
    );
    if (!shouldMove) return;

    provider.goToStation(stationIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.stationTransitionComplete();
    });
  }

  Future<bool> _confirmStationExit({
    required String title,
    required String actionLabel,
  }) async {
    final stationAuditProvider = _currentStationProvider;
    if (stationAuditProvider == null) return true;

    if (!mounted) return false;
    if (stationAuditProvider.isDirty) {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: const Text(
            'This station has unsaved changes. Save before leaving this screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      );

      if (shouldSave != true) return false;
    }

    setState(() => _isSavingStation = true);
    var saved = false;
    try {
      final prepared = await _prepareCurrentStationForExit();
      saved = prepared ? await _saveCurrentStation() : false;
      if (!mounted) return false;
      if (saved) {
        await _showStationSavedPulse();
      } else {
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

  Future<void> _showStationSavedPulse() async {
    if (!mounted) return;
    setState(() => _showSavedAnimation = true);
    await Future.delayed(const Duration(milliseconds: 520));
    if (!mounted) return;
    setState(() => _showSavedAnimation = false);
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
}

class _StationFrame extends StatefulWidget {
  final String stationKey;
  final AuditContextData context;
  final String sessionId;
  final AuditRepository auditRepository;
  final StationSampleRepository stationSampleRepository;
  final EggStorageStationController? eggStorageController;

  const _StationFrame({
    required this.stationKey,
    required this.context,
    required this.sessionId,
    required this.auditRepository,
    required this.stationSampleRepository,
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
      final audits = await widget.auditRepository.getAuditsBySessionId(
        widget.sessionId,
      );
      final stationAudits =
          audits
              .where((audit) => audit.auditType == widget.context.auditType)
              .toList()
            ..sort((a, b) => a.hatchNumber.compareTo(b.hatchNumber));
      final samples = await widget.stationSampleRepository.getSamplesForStation(
        widget.sessionId,
        widget.stationKey,
      );
      return _StationInitialData(
        stationAudits: stationAudits,
        stationSamples: samples,
      );
    } catch (_) {
      return const _StationInitialData();
    }
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
