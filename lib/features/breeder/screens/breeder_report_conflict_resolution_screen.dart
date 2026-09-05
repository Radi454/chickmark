import 'dart:convert';

import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/repositories/sync_conflict_repository.dart';
import '../../../services/breeder/breeder_report_conflict_service.dart';
import '../../auth/providers/auth_provider.dart';

/// Conflict resolution UI for the daily-report sync aggregate
/// (breeder-flock-performance ticket 15, design doc section 5.3 and 13.1):
/// "A production manager picks or merges the correct data." This screen
/// shows both preserved versions (this device's rejected push and the
/// cloud's winning aggregate) side by side and lets the manager choose
/// which one the report keeps going forward.
///
/// "Merging" is not a separate third button: a manager who wants a blend of
/// both sides resolves by keeping local, is returned to the report's
/// pre-conflict state (Draft, if it was mid-edit), and hand-edits the
/// child rows there to match what should actually be true before letting
/// the next sync push it — exactly like an ordinary correction, just
/// prompted by a conflict instead of a data-entry mistake.
class BreederReportConflictResolutionScreen extends StatefulWidget {
  const BreederReportConflictResolutionScreen({
    super.key,
    required this.reportId,
    this.conflictService,
  });

  final String reportId;
  final BreederReportConflictService? conflictService;

  @override
  State<BreederReportConflictResolutionScreen> createState() =>
      _BreederReportConflictResolutionScreenState();
}

class _BreederReportConflictResolutionScreenState
    extends State<BreederReportConflictResolutionScreen> {
  late final BreederReportConflictService _conflictService =
      widget.conflictService ?? BreederReportConflictService();

  late Future<SyncConflict?> _conflictFuture;
  bool _resolving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _conflictFuture = _conflictService.openConflictFor(widget.reportId);
  }

  Map<String, dynamic>? _decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final decoded = jsonDecode(json);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<void> _resolve(BreederConflictResolution resolution) async {
    final reviewedBy = context.read<AuthProvider>().user?.id ?? 'unknown';
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      await _conflictService.resolve(
        reportId: widget.reportId,
        resolution: resolution,
        reviewedBy: reviewedBy,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _error = error.toString();
        _resolving = false;
      });
    }
  }

  Widget _summaryCard(String title, Map<String, dynamic>? aggregate) {
    final header = aggregate?['header'] as Map?;
    final movementCount = (aggregate?['movements'] as List?)?.length ?? 0;
    final feedCount = (aggregate?['feed_entries'] as List?)?.length ?? 0;
    final eggCount =
        (aggregate?['egg_production_entries'] as List?)?.length ?? 0;
    final inventoryCount =
        (aggregate?['inventory_movements'] as List?)?.length ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('State: ${header?['state'] ?? '—'}'),
            Text('Revision: ${header?['revision'] ?? '—'}'),
            Text('Notes: ${header?['notes'] ?? '—'}'),
            Text('Inside temperature: ${header?['inside_temperature'] ?? '—'}'),
            Text(
              'Outside temperature: ${header?['outside_temperature'] ?? '—'}',
            ),
            const SizedBox(height: 8),
            Text('Bird movements: $movementCount'),
            Text('Feed entries: $feedCount'),
            Text('Egg production entries: $eggCount'),
            Text('Inventory movements: $inventoryCount'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(title: context.tr('Resolve Sync Conflict')),
      body: FutureBuilder<SyncConflict?>(
        future: _conflictFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final conflict = snapshot.data;
          if (conflict == null) {
            return Center(
              child: Text(context.tr('No open sync conflict for this report.')),
            );
          }
          final local = _decode(conflict.localDataJson);
          final remote = _decode(conflict.remoteDataJson);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This report was edited on more than one device while '
                  'offline. Choose which version to keep — the other is '
                  'discarded once you decide. Nothing is submitted or '
                  'approved until this is resolved.',
                ),
                const SizedBox(height: AppSizes.cardPadding),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppSizes.cardPadding,
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                _summaryCard('This device (rejected)', local),
                const SizedBox(height: AppSizes.cardPadding),
                _summaryCard('Cloud (currently saved)', remote),
                const SizedBox(height: AppSizes.cardPadding * 1.5),
                ElevatedButton(
                  onPressed: _resolving
                      ? null
                      : () => _resolve(BreederConflictResolution.keepLocal),
                  child: Text(context.tr("Keep this device's version")),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _resolving
                      ? null
                      : () => _resolve(BreederConflictResolution.keepRemote),
                  child: Text(context.tr('Keep the cloud version')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
