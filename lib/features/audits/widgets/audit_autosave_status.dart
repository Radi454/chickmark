import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../providers/audit_provider.dart';

class AuditAutosaveStatus extends StatelessWidget {
  final bool onDark;

  const AuditAutosaveStatus({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final state = context.select<AuditProvider, _AutosaveStatusState>((p) {
      return _AutosaveStatusState(
        isReadOnly: p.isReadOnly,
        isDirty: p.isDirty,
        isAutosaving: p.isAutosaving,
        lastAutosavedAt: p.lastAutosavedAt,
        autosaveError: p.autosaveError,
      );
    });
    if (state.isReadOnly) return const SizedBox.shrink();

    final view = _statusView(state);
    if (view == null) return const SizedBox.shrink();

    final foreground = onDark ? Colors.white : view.color;
    final background = onDark
        ? Colors.white.withValues(alpha: 0.16)
        : view.color.withValues(alpha: 0.10);
    final border = onDark
        ? Colors.white.withValues(alpha: 0.22)
        : view.color.withValues(alpha: 0.24);

    return Tooltip(
      message: view.tooltip,
      child: Container(
        key: const ValueKey('audit-autosave-status'),
        constraints: const BoxConstraints(maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(view.icon, size: 15, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                view.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _AutosaveStatusView? _statusView(_AutosaveStatusState state) {
    if (state.autosaveError != null) {
      return const _AutosaveStatusView(
        label: 'Autosave issue',
        tooltip: 'Draft could not be autosaved. Save will retry.',
        icon: Icons.warning_amber_rounded,
        color: AppColors.statusWarning,
      );
    }
    if (state.isAutosaving) {
      return const _AutosaveStatusView(
        label: 'Saving draft',
        tooltip: 'Saving a local draft',
        icon: Icons.sync_rounded,
        color: AppColors.primary,
      );
    }
    if (state.isDirty) {
      return const _AutosaveStatusView(
        label: 'Save pending',
        tooltip: 'Draft autosave is queued',
        icon: Icons.schedule_rounded,
        color: AppColors.statusWarning,
      );
    }
    if (state.lastAutosavedAt != null) {
      return const _AutosaveStatusView(
        label: 'Draft saved',
        tooltip: 'Local draft saved on this device',
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.statusGood,
      );
    }
    return null;
  }
}

class _AutosaveStatusState {
  final bool isReadOnly;
  final bool isDirty;
  final bool isAutosaving;
  final DateTime? lastAutosavedAt;
  final String? autosaveError;

  const _AutosaveStatusState({
    required this.isReadOnly,
    required this.isDirty,
    required this.isAutosaving,
    required this.lastAutosavedAt,
    required this.autosaveError,
  });

  @override
  bool operator ==(Object other) {
    return other is _AutosaveStatusState &&
        other.isReadOnly == isReadOnly &&
        other.isDirty == isDirty &&
        other.isAutosaving == isAutosaving &&
        other.lastAutosavedAt == lastAutosavedAt &&
        other.autosaveError == autosaveError;
  }

  @override
  int get hashCode => Object.hash(
    isReadOnly,
    isDirty,
    isAutosaving,
    lastAutosavedAt,
    autosaveError,
  );
}

class _AutosaveStatusView {
  final String label;
  final String tooltip;
  final IconData icon;
  final Color color;

  const _AutosaveStatusView({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
  });
}
