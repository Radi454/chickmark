import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

class AuditWorkbenchShell extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const AuditWorkbenchShell({
    super.key,
    required this.children,
    this.maxWidth = 1040,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 20),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class AuditHeroDetail {
  final String label;
  final String value;

  const AuditHeroDetail({required this.label, required this.value});
}

class AuditStationHero extends StatelessWidget {
  final Key? heroKey;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<AuditHeroDetail> details;

  const AuditStationHero({
    super.key,
    this.heroKey,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: heroKey,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F9F8F), Color(0xFF2458C9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final titleBlock = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(70)),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.badge.copyWith(
                        color: Colors.white.withAlpha(210),
                        letterSpacing: 0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.heading.copyWith(
                        color: Colors.white,
                        fontSize: wide ? 28 : 24,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white.withAlpha(220),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final detailGrid = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final detail in details) _AuditHeroDetailTile(detail),
            ],
          );

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [titleBlock, const SizedBox(height: 16), detailGrid],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 9, child: titleBlock),
              const SizedBox(width: 18),
              Expanded(flex: 8, child: detailGrid),
            ],
          );
        },
      ),
    );
  }
}

class _AuditHeroDetailTile extends StatelessWidget {
  final AuditHeroDetail detail;

  const _AuditHeroDetailTile(this.detail);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 190),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(34),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withAlpha(65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              detail.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withAlpha(205),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              detail.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuditPanelColumns extends StatelessWidget {
  final List<Widget> left;
  final List<Widget> right;
  final double breakpoint;

  const AuditPanelColumns({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = 900,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _PanelColumn(children: left)),
              const SizedBox(width: 16),
              Expanded(child: _PanelColumn(children: right)),
            ],
          );
        }
        return _PanelColumn(children: [...left, ...right]);
      },
    );
  }
}

class _PanelColumn extends StatelessWidget {
  final List<Widget> children;

  const _PanelColumn({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          children[i],
        ],
      ],
    );
  }
}

class AuditWorkbenchPanel extends StatelessWidget {
  final Key? panelKey;
  final String mark;
  final IconData icon;
  final String title;
  final String meta;
  final String? statusLabel;
  final Color? statusColor;
  final Widget child;

  const AuditWorkbenchPanel({
    super.key,
    this.panelKey,
    required this.mark,
    required this.icon,
    required this.title,
    required this.meta,
    this.statusLabel,
    this.statusColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: panelKey,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final titleBlock = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.infoBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withAlpha(45),
                          ),
                        ),
                        child: Text(
                          mark,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(icon, size: 18, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.title.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                meta,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );

                  final pill = statusLabel == null || statusColor == null
                      ? null
                      : _AuditStatusPill(
                          label: statusLabel!,
                          color: statusColor!,
                        );

                  if (pill == null) return titleBlock;
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [titleBlock, const SizedBox(height: 10), pill],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleBlock),
                      const SizedBox(width: 10),
                      pill,
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _AuditStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AuditMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const AuditMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value.isEmpty ? '--' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.heading.copyWith(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
