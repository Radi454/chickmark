import 'package:hatchaudit/localized_material.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/activity_log_model.dart';
import '../../../data/repositories/activity_log_repository.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final ActivityLogRepository _repository = ActivityLogRepository();
  bool _isLoading = true;
  List<ActivityLogModel> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Activity Log',
        actions: [
          IconButton(
            tooltip: context.tr('Clear old logs'),
            icon: const Icon(Icons.auto_delete_outlined),
            onPressed: _clearOldLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? const Center(child: Text('No activity recorded yet'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return ListTile(
                    leading: Icon(_iconFor(entry.action)),
                    title: Text(_titleFor(entry)),
                    subtitle: Text(_subtitleFor(entry)),
                    trailing: Text(
                      _formatDate(entry.timestamp),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.end,
                      textDirection: TextDirection.ltr,
                    ),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _load() async {
    final entries = await _repository.getRecent();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _clearOldLogs() async {
    await _repository.pruneOlderThan(const Duration(days: 90));
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs older than 90 days cleared')),
    );
  }

  IconData _iconFor(String action) {
    switch (action) {
      case 'create':
        return Icons.add_circle_outline;
      case 'update':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline;
      case 'login':
        return Icons.login_outlined;
      case 'sync':
        return Icons.sync_outlined;
      case 'sync_conflict':
        return Icons.warning_amber_outlined;
      default:
        return Icons.history;
    }
  }

  String _titleFor(ActivityLogModel entry) {
    final entity = entry.entityType == null ? '' : '${entry.entityType} ';
    final entityId = entry.entityId == null ? '' : ' ${entry.entityId}';
    return '${entry.action.toUpperCase()} ${entity.trim()}$entityId'.trim();
  }

  String _subtitleFor(ActivityLogModel entry) {
    final details = entry.details?.trim();
    if (details == null || details.isEmpty) {
      return 'User ${entry.userId}';
    }
    return 'User ${entry.userId} · $details';
  }

  String _formatDate(DateTime value) {
    return HatchDateUtils.formatDisplayDateTime(value).replaceFirst(' ', '\n');
  }
}
