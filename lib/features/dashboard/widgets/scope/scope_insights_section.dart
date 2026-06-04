import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import 'scope_sector_widget.dart';

/// "Scopes & Parameters" — the full audit comparison, grouped by station, each
/// station an expandable card of sector widgets. Ported from the prototype.
class ScopeInsightsSection extends StatelessWidget {
  const ScopeInsightsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoading =
        context.select<ScopeComparisonProvider, bool>((p) => p.isLoading);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.all(AppSizes.spaceXl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final station in ScopeConfigRegistry.stations)
            _StationCard(station: station),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.spaceSm,
        AppSizes.spaceMd,
        AppSizes.spaceSm,
        AppSizes.spaceSm,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.statusActiveBg,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: const Text(
              'SCOPES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Scopes & Parameters — full audit',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  final String station;

  const _StationCard({required this.station});

  @override
  Widget build(BuildContext context) {
    final sectors = ScopeConfigRegistry.forStation(station);
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceXs,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        side: const BorderSide(color: AppColors.borderDefault),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.spaceLg,
            vertical: AppSizes.spaceXs,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSizes.spaceMd,
            0,
            AppSizes.spaceMd,
            AppSizes.spaceSm,
          ),
          title: Text(
            station,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          children: [
            for (final s in sectors) ScopeSectorWidget(sectorId: s.id),
          ],
        ),
      ),
    );
  }
}
