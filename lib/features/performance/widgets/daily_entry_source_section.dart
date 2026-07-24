import 'package:hatchaudit/localized_material.dart';

import '../../../data/models/broiler_daily_record_models.dart';

class DailyEntrySourceSection extends StatelessWidget {
  const DailyEntrySourceSection({
    super.key,
    required this.sources,
    this.onAddSource,
  });

  final List<DailyRecordSourceDraft> sources;
  final VoidCallback? onAddSource;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final source in sources)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.attach_file),
            title: Text(
              source.originalFilename ??
                  source.localPath ??
                  source.sourceKind.storageKey,
            ),
            subtitle: Text(source.uploadState),
            trailing: source.uploadError == null
                ? const Icon(Icons.check_circle_outline, color: Colors.green)
                : const Icon(Icons.error_outline, color: Colors.red),
          ),
        if (sources.isEmpty)
          Text(
            'No source documents attached',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (onAddSource != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onAddSource,
              icon: const Icon(Icons.add),
              label: const Text('Add source'),
            ),
          ),
      ],
    );
  }
}
