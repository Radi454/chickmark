import 'dart:async';

import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/customers_provider.dart';
import '../../../services/supabase/startup_sync_service.dart';
import '../../../widgets/chick_mark_logo.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/providers/settings_provider.dart';

class StartupSyncScreen extends StatefulWidget {
  const StartupSyncScreen({super.key});

  @override
  State<StartupSyncScreen> createState() => _StartupSyncScreenState();
}

class _StartupSyncScreenState extends State<StartupSyncScreen> {
  static const Duration _startupSyncGracePeriod = Duration(milliseconds: 1500);

  final StartupSyncService _syncService = StartupSyncService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupSync());
    });
  }

  Future<void> _runStartupSync() async {
    final settings = context.read<SettingsProvider>();
    // Don't flag incoming changes on the very first sync (nothing local yet) —
    // only once the device has synced before.
    final collectIncoming = settings.hasSyncedBefore;
    settings.markSyncing();
    // Wrap the sync future so outcomes (online + counts) land in
    // SettingsProvider regardless of whether the grace-period timer wins.
    final syncFuture = _syncService
        .run(
          userId: context.read<AuthProvider>().user?.id,
          collectIncoming: collectIncoming,
        )
        .then((outcome) async {
          await settings.recordSync(
            online: outcome.online,
            pushed: outcome.pushed,
            pulled: outcome.pulled,
            incoming: outcome.incomingSessions,
            otherIncoming: outcome.otherIncomingCount,
          );
          return outcome;
        })
        .catchError((Object error, StackTrace stackTrace) async {
          await settings.recordSync(
            online: false,
            pushed: 0,
            pulled: 0,
            error: error.toString(),
          );
          return SyncOutcome.offline;
        });
    await Future.any<dynamic>([
      syncFuture,
      Future<void>.delayed(_startupSyncGracePeriod),
    ]);

    if (!mounted) return;
    await context.read<CustomersProvider>().loadCustomers(
      currentUser: context.read<AuthProvider>().user,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/main');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ChickMarkLogo(logoSize: 128, animated: true),
                const SizedBox(height: 26),
                const _CheckmarkLoader(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckmarkLoader extends StatefulWidget {
  const _CheckmarkLoader();

  @override
  State<_CheckmarkLoader> createState() => _CheckmarkLoaderState();
}

class _CheckmarkLoaderState extends State<_CheckmarkLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: const Size(132, 36),
            painter: _CheckmarkLoaderPainter(progress: _controller.value),
          );
        },
      ),
    );
  }
}

class _CheckmarkLoaderPainter extends CustomPainter {
  final double progress;

  const _CheckmarkLoaderPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final checkPath = Path()
      ..moveTo(size.width * 0.18, size.height * 0.55)
      ..lineTo(size.width * 0.43, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.44,
        size.width * 0.84,
        size.height * 0.18,
      );
    final basePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(checkPath, basePaint);

    final activePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final metric = checkPath.computeMetrics().first;
    final easedProgress = Curves.easeInOutCubic.transform(progress);
    final activePath = metric.extractPath(0, metric.length * easedProgress);
    canvas.drawPath(activePath, activePaint);

    final tangent = metric.getTangentForOffset(metric.length * easedProgress);
    if (tangent == null) return;
    final markerPaint = Paint()
      ..color = const Color(0xFFFFC400)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(tangent.position, 4.5, markerPaint);
  }

  @override
  bool shouldRepaint(covariant _CheckmarkLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
