import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_page_route.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/utils/scorecard_formatter.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/models/visit_session_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/govee_capture_chart.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/hatch_analysis_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/egg_breakout_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/stub_sections.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/customers/screens/visit_detail_screen.dart';
import 'package:hatchaudit/widgets/app_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthProvider>().user;
      context.read<DashboardProvider>().init(currentUser: user);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: const GradientAppBar(title: 'Dashboard'),
          body: Column(
            children: [
              _buildCascadeFilter(provider),
              Expanded(child: _buildContent(context, provider)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCascadeFilter(DashboardProvider provider) {
    return AppCard(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.cardPadding,
        AppSizes.cardPadding,
        AppSizes.cardPadding,
        0,
      ),
      color: AppColors.surfaceVariant,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: provider.selectedCustomerId,
                  decoration: const InputDecoration(
                    labelText: 'Customer',
                    isDense: true,
                  ),
                  items: [
                    if (provider.canUseAllCustomers)
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All customers'),
                      ),
                    ...provider.customers.map((c) {
                      return DropdownMenuItem(value: c.id, child: Text(c.name));
                    }),
                  ],
                  onChanged: (v) {
                    provider.setCustomer(v);
                  },
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: provider.selectedFlockId,
                  decoration: const InputDecoration(
                    labelText: 'Flock',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All flocks'),
                    ),
                    ...provider.flocks.map((f) {
                      return DropdownMenuItem(
                        value: f.id,
                        child: Text(f.flockId),
                      );
                    }),
                  ],
                  onChanged: (v) {
                    provider.setFlock(v);
                  },
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: provider.selectedBmkAge,
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...provider.availableBmkAges.map((a) {
                      return DropdownMenuItem(value: a, child: Text('${a}w'));
                    }),
                  ],
                  onChanged: (v) => provider.setBmkAge(v),
                ),
              ),
              if (provider.hasActiveFilters) ...[
                const SizedBox(width: AppSizes.spaceSm),
                TextButton.icon(
                  onPressed: provider.clearFilters,
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, DashboardProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.customers.isEmpty && provider.flocks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            SizedBox(height: AppSizes.spaceLg),
            Text('No customer or flock data yet', style: AppTextStyles.title),
            SizedBox(height: AppSizes.spaceSm),
            Text(
              'Add a customer and flock to see dashboard insights.',
              style: AppTextStyles.caption,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      children: [
        if (provider.visitSessions.isNotEmpty) ...[
          _buildVisitSessionsSection(context, provider),
          const SizedBox(height: AppSizes.spaceLg),
        ],
        const HatchAnalysisSection(),
        const SizedBox(height: AppSizes.spaceLg),
        const EggBreakoutSection(),
        const SizedBox(height: AppSizes.spaceLg),
        const ChickQualitySection(),
        const SizedBox(height: AppSizes.spaceLg),
        const EggStorageSection(),
        const SizedBox(height: AppSizes.spaceLg),
        const SetterOptimizingSection(),
        const SizedBox(height: AppSizes.spaceLg),
        const HatcherOptimizingSection(),
      ],
    );
  }

  Widget _buildVisitSessionsSection(
    BuildContext context,
    DashboardProvider provider,
  ) {
    final session = provider.selectedVisitSession;
    if (session == null) {
      return AppCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.spaceLg),
          child: Row(
            children: [
              const Icon(Icons.route, color: AppColors.inactiveTab, size: 20),
              const SizedBox(width: AppSizes.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Visit Sessions', style: AppTextStyles.title),
                    const SizedBox(height: AppSizes.spaceXs),
                    Text(
                      'Complete a hatchery visit to see session summaries here.',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AppCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        title: const Text('Visit Sessions', style: AppTextStyles.sectionTitle),
        subtitle: Text(
          '${provider.visitSessions.length} recent visit${provider.visitSessions.length == 1 ? '' : 's'}',
          style: AppTextStyles.caption,
        ),
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceLg,
          vertical: AppSizes.spaceSm,
        ),
        childrenPadding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
        children: [
          _buildSessionSelector(context, provider),
          _buildSessionScorecards(session),
          _buildSessionFindings(session),
          _buildSessionPmScore(session),
          _buildSessionHatchBudget(session),
          _buildSessionGoveeCaptures(provider),
          _buildSessionViewDetailButton(context, session),
        ],
      ),
    );
  }

  Widget _buildSessionSelector(
    BuildContext context,
    DashboardProvider provider,
  ) {
    final sessions = provider.visitSessions;
    final localizations = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Wrap(
        spacing: AppSizes.spaceSm,
        children: sessions.map((s) {
          final isSelected =
              provider.selectedVisitSession?.session.id == s.session.id;
          return ChoiceChip(
            label: Text(localizations.formatShortDate(s.session.date)),
            selected: isSelected,
            onSelected: (_) {
              provider.selectVisitSession(s);
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSessionScorecards(VisitSessionSummary session) {
    if (session.scorecards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Wrap(
        spacing: AppSizes.spaceSm,
        runSpacing: AppSizes.spaceSm,
        children: session.scorecards.map((sc) {
          final color = ScorecardFormatter.statusColor(sc.status);
          return _summaryBadge(
            color: color,
            child: Text(
              '${sc.stationLabel}: ${ScorecardFormatter.statusLabel(sc.status)}',
              style: AppTextStyles.badgeLabel.copyWith(color: color),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSessionFindings(VisitSessionSummary session) {
    final findings = session.findingsSummary;
    if (findings == null || findings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('Findings', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.spaceXs),
          Wrap(
            spacing: AppSizes.spaceSm,
            runSpacing: AppSizes.spaceXs,
            children: [
              if (findings.greenCount > 0)
                _findingChip('Good', findings.greenCount, AppColors.statusGood),
              if (findings.amberCount > 0)
                _findingChip(
                  'Caution',
                  findings.amberCount,
                  AppColors.statusWarning,
                ),
              if (findings.redCount > 0)
                _findingChip(
                  'Critical',
                  findings.redCount,
                  AppColors.statusError,
                ),
            ],
          ),
          if (findings.findings.isNotEmpty) ...[
            const SizedBox(height: AppSizes.spaceSm),
            ...findings.findings.take(3).map((f) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceXs),
                child: Text('• ${f.title}', style: AppTextStyles.badgeLabel),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _findingChip(String label, int count, Color color) {
    return _summaryBadge(
      color: color,
      child: Text(
        '$label: $count',
        style: AppTextStyles.badgeLabel.copyWith(color: color),
      ),
    );
  }

  Widget _buildSessionPmScore(VisitSessionSummary session) {
    final pm = session.pmScoreSummary;
    if (pm == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('PM Necropsy', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.spaceXs),
          Wrap(
            spacing: AppSizes.spaceMd,
            children: [
              Text('Lesions: ${pm.totalLesions}'),
              Text('Deformities: ${pm.totalDeformities}'),
              if (pm.gaspingPresent)
                Text('Gasping: ${pm.gaspingType ?? 'Yes'}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionHatchBudget(VisitSessionSummary session) {
    final hb = session.hatchBudgetSummary;
    if (hb == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('Hatch Budget', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.spaceXs),
          Wrap(
            spacing: AppSizes.spaceMd,
            children: [
              Text('Set: ${hb.totalEggsSet}'),
              Text('Hatched: ${hb.healthyHatched}'),
              if (hb.hatchabilityPct != null)
                Text('Hatch%: ${hb.hatchabilityPct!.toStringAsFixed(1)}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionGoveeCaptures(DashboardProvider provider) {
    if (provider.isLoadingGoveeCaptures) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.spaceLg,
          vertical: AppSizes.spaceSm,
        ),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    final captures = provider.goveeCaptures;
    if (captures.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('Govee Readings', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.spaceSm),
          ...captures.map(
            (summary) => Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
              child: GoveeCaptureChart(summary: summary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionViewDetailButton(
    BuildContext context,
    VisitSessionSummary session,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                AppPageRoute(
                  builder: (context) => VisitDetailScreen(visit: session),
                ),
              );
            },
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View visit summary'),
          ),
        ],
      ),
    );
  }

  Widget _summaryBadge({required Color color, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceMd,
        vertical: AppSizes.spaceXs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }
}
