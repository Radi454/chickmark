import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/status_badge.dart';
import '../providers/audits_list_provider.dart';

/// Expandable card for one audit visit: header (customer/flock, status, sync,
/// menu), progress summary, and on expand a row per selected station with its
/// data status, sync state, and per-station actions.
class SessionCard extends StatefulWidget {
  final SessionView view;
  final SessionDisplayResolver resolver;
  final bool canEdit;
  final VoidCallback onResumeVisit;
  final void Function(int stationIndex) onOpenStation;
  final VoidCallback onDelete;
  final void Function(String stationKey) onClearStation;

  const SessionCard({
    super.key,
    required this.view,
    required this.resolver,
    required this.canEdit,
    required this.onResumeVisit,
    required this.onOpenStation,
    required this.onDelete,
    required this.onClearStation,
  });

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.view.session;
    final isCompleted = session.status == 'completed';
    final customerName = widget.resolver.customerName(session.customerId);
    final hatcheryName = widget.resolver.hatcheryName(session.hatcheryId);
    final flockLabel = widget.resolver.flockLabel(session.flockId);
    final breed =
        session.breed ?? widget.resolver.flockBreed(session.flockId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusBadge(
                        status: isCompleted ? 'completed' : 'active',
                        label: isCompleted ? 'Completed' : 'In Progress',
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          [
                            customerName,
                            if (hatcheryName.isNotEmpty) hatcheryName,
                          ].join(' · '),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _SyncChip(sync: widget.view.sync),
                      if (widget.canEdit) _visitMenu(),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _subtitle(flockLabel, breed, session.flockAgeWeeks),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _progressRow(),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ...List.generate(widget.view.stations.length, (index) {
              return _StationRow(
                station: widget.view.stations[index],
                canEdit: widget.canEdit,
                onOpen: () => widget.onOpenStation(index),
                onClear: () =>
                    widget.onClearStation(widget.view.stations[index].key),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _visitMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Visit actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'resume':
            widget.onResumeVisit();
            break;
          case 'delete':
            widget.onDelete();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'resume',
          child: ListTile(
            leading: Icon(Icons.play_arrow_outlined),
            title: Text('Resume visit'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: AppColors.statusError),
            title: Text('Delete visit'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _progressRow() {
    final total = widget.view.total;
    final completed = widget.view.completed;
    final ratio = total == 0 ? 0.0 : completed / total;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.statusNeutralBg,
              valueColor: const AlwaysStoppedAnimation(AppColors.statusGood),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$completed/$total stations',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  String _subtitle(String flockLabel, String? breed, int? ageWeeks) {
    final parts = <String>[
      if (flockLabel.isNotEmpty) flockLabel,
      if (breed != null && breed.isNotEmpty) breed,
      if (ageWeeks != null && ageWeeks > 0) '${ageWeeks}w',
      HatchDateUtils.formatDisplayDate(widget.view.session.date),
    ];
    final updated = _relativeTime(widget.view.session.updatedAt);
    return '${parts.join(' · ')}  ·  updated $updated';
  }
}

class _StationRow extends StatelessWidget {
  final StationView station;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  const _StationRow({
    required this.station,
    required this.canEdit,
    required this.onOpen,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(_stationIcon(station.key), size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                station.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _dataStatusChip(station.status),
            const SizedBox(width: 8),
            _SyncDot(sync: station.sync),
            if (canEdit)
              PopupMenuButton<String>(
                tooltip: 'Station actions',
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (value) {
                  if (value == 'open') onOpen();
                  if (value == 'clear') onClear();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      leading: Icon(Icons.open_in_new, size: 20),
                      title: Text('Open / Re-Audit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    enabled: station.status != StationDataStatus.empty,
                    child: const ListTile(
                      leading: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppColors.statusError,
                      ),
                      title: Text('Clear station'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              )
            else
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _dataStatusChip(StationDataStatus status) {
    final (label, bg, fg) = switch (status) {
      StationDataStatus.done => ('Done', AppColors.statusGoodBg, AppColors.statusGood),
      StationDataStatus.inProgress => (
        'In Progress',
        AppColors.statusActiveBg,
        AppColors.statusActive,
      ),
      StationDataStatus.empty => (
        'Empty',
        AppColors.statusNeutralBg,
        AppColors.statusNeutralText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  IconData _stationIcon(String key) {
    return switch (key) {
      'egg' => Icons.egg_outlined,
      'chicks' => Icons.cruelty_free_outlined,
      'hatch_analysis_egg_breakouts' => Icons.biotech_outlined,
      'setters' => Icons.device_thermostat_outlined,
      'hatchers' => Icons.local_fire_department_outlined,
      _ => Icons.science_outlined,
    };
  }
}

/// Header pill summarising a visit's sync state.
class _SyncChip extends StatelessWidget {
  final String sync;

  const _SyncChip({required this.sync});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _style(sync);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: 'Sync: $label',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _style(String sync) {
    return switch (sync) {
      'synced' => (Icons.cloud_done_outlined, AppColors.statusGood, 'Synced'),
      'failed' => (Icons.cloud_off_outlined, AppColors.statusError, 'Failed'),
      _ => (Icons.cloud_upload_outlined, _pendingColor, 'Pending'),
    };
  }
}

/// Compact per-station sync indicator.
class _SyncDot extends StatelessWidget {
  final String sync;

  const _SyncDot({required this.sync});

  @override
  Widget build(BuildContext context) {
    if (sync == 'none') {
      return const SizedBox(width: 10, height: 10);
    }
    final color = switch (sync) {
      'synced' => AppColors.statusGood,
      'failed' => AppColors.statusError,
      _ => _pendingColor,
    };
    return Tooltip(
      message: 'Sync: ${sync[0].toUpperCase()}${sync.substring(1)}',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

const Color _pendingColor = Color(0xFFB45309); // amber-700

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return HatchDateUtils.formatDisplayDate(time);
}
