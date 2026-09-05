import 'package:hatchaudit/localized_material.dart';

import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/data/models/breeder_benchmark_models.dart';
import 'package:hatchaudit/data/repositories/breeder_benchmark_repository.dart';
import 'package:hatchaudit/features/breeder/screens/breeder_benchmark_detail_screen.dart';
import 'package:hatchaudit/widgets/section_card.dart';

/// Scaffold-less list of published breeder benchmark profiles, used by the
/// standalone `BreederBenchmarkListScreen`. The BMK screen's Breeder Farm
/// sector presents the same benchmarks as a dashboard instead
/// (`BreederBmkSectorView`). Read-only: benchmarks come only from the
/// checked-in asset importer (see
/// lib/data/database/seeds/breeder_benchmark_seeds.dart).
class BreederBenchmarkProfilesView extends StatefulWidget {
  final BreederBenchmarkRepository? repository;

  const BreederBenchmarkProfilesView({super.key, this.repository});

  @override
  State<BreederBenchmarkProfilesView> createState() =>
      _BreederBenchmarkProfilesViewState();
}

class _BreederBenchmarkProfilesViewState
    extends State<BreederBenchmarkProfilesView> {
  late final BreederBenchmarkRepository _repository =
      widget.repository ?? BreederBenchmarkRepository();
  late final Future<List<BreederBenchmarkProfile>> _profilesFuture = _repository
      .getProfiles();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BreederBenchmarkProfile>>(
      future: _profilesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final profiles = snapshot.data ?? const <BreederBenchmarkProfile>[];
        if (profiles.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSizes.cardPadding),
              child: Text(
                'No published benchmark profiles yet.',
                style: AppTextStyles.body,
              ),
            ),
          );
        }
        return ListView.builder(
          key: const ValueKey('breeder-benchmark-profile-list'),
          padding: const EdgeInsets.all(AppSizes.cardPadding),
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final profile = profiles[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.spaceMd),
              child: SectionCard(
                // ListTile paints its background and ink on the nearest
                // Material ancestor; SectionCard's DecoratedBox would hide
                // both, which trips a framework assertion in debug.
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.query_stats_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      profile.displayName,
                      style: AppTextStyles.title,
                    ),
                    subtitle: Text(
                      profile.guideVersion,
                      style: AppTextStyles.body,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BreederBenchmarkDetailScreen(
                            profile: profile,
                            repository: _repository,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
