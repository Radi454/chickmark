import 'package:hatchaudit/localized_material.dart';

import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/data/repositories/breeder_benchmark_repository.dart';
import 'package:hatchaudit/features/breeder/widgets/breeder_benchmark_profiles_view.dart';

/// Read-only list of official breeder benchmark profiles. No edit
/// affordances anywhere on this screen or the detail screen it opens —
/// benchmarks come only from the checked-in asset importer (see
/// lib/data/database/seeds/breeder_benchmark_seeds.dart).
///
/// Reached from Settings → Reference → "Official Benchmarks". The BMK
/// screen's Breeder Farm sector reads the same benchmarks as a dashboard
/// (`BreederBmkSectorView`) rather than as this list.
class BreederBenchmarkListScreen extends StatelessWidget {
  final BreederBenchmarkRepository? repository;

  const BreederBenchmarkListScreen({super.key, this.repository});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Official Benchmarks'),
      body: BreederBenchmarkProfilesView(repository: repository),
    );
  }
}
