import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/features/bmk/providers/bmk_provider.dart';
import 'package:hatchaudit/widgets/section_card.dart';

class BmkScreen extends StatefulWidget {
  const BmkScreen({super.key});

  @override
  State<BmkScreen> createState() => _BmkScreenState();
}

class _BmkScreenState extends State<BmkScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BmkProvider>().ensureInitialized();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'BMK'),
      body: Consumer<BmkProvider>(
        builder: (context, bmk, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBreedSection(context, bmk),
                const SizedBox(height: 24),
                _buildEggBreakoutSection(context, bmk),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBreedSection(BuildContext context, BmkProvider bmk) {
    return SectionCard(
      title: 'Breed Benchmarks',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _buildBreedRow(bmk, BmkProvider.breeds.take(3).toList()),
              const SizedBox(height: 8),
              _buildBreedRow(bmk, BmkProvider.breeds.skip(3).toList()),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Age: ',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              DropdownButton<int>(
                value: bmk.breedAges.contains(bmk.selectedBreedAge)
                    ? bmk.selectedBreedAge
                    : null,
                items: bmk.breedAges.map((age) {
                  return DropdownMenuItem(value: age, child: Text('${age}w'));
                }).toList(),
                onChanged: (age) {
                  if (age != null) bmk.setBreedAge(age);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (bmk.breedRow == null)
            const Center(
              child: Text('No data', style: TextStyle(color: Colors.grey)),
            )
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.2,
              children: [
                _buildMetricTile(
                  'Hatchability %',
                  '${bmk.breedRow!.hatchabilityPct}%',
                ),
                _buildMetricTile(
                  'Fertility %',
                  '${bmk.breedRow!.fertilityPct}%',
                ),
                _buildMetricTile('HOF %', '${bmk.breedRow!.hofPct}%'),
                _buildMetricTile(
                  'Production %',
                  '${bmk.breedRow!.productionPct}%',
                ),
                _buildMetricTile(
                  'Egg Weight (g)',
                  '${bmk.breedRow!.eggWeightG}',
                ),
                _buildMetricTile(
                  'Chick Weight (g)',
                  '${bmk.breedRow!.chickWeightG}',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEggBreakoutSection(BuildContext context, BmkProvider bmk) {
    return SectionCard(
      title: 'Egg Breakout BMK',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilterChip(
                label: const Text('🥚 Fresh'),
                selected: bmk.selectedEbType == EbType.fresh,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: bmk.selectedEbType == EbType.fresh
                      ? Colors.white
                      : Colors.black87,
                ),
                onSelected: (_) => bmk.setEbType(EbType.fresh),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('🔍 Candled'),
                selected: bmk.selectedEbType == EbType.candled,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: bmk.selectedEbType == EbType.candled
                      ? Colors.white
                      : Colors.black87,
                ),
                onSelected: (_) => bmk.setEbType(EbType.candled),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('🐣 Residue'),
                selected: bmk.selectedEbType == EbType.residue,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: bmk.selectedEbType == EbType.residue
                      ? Colors.white
                      : Colors.black87,
                ),
                onSelected: (_) => bmk.setEbType(EbType.residue),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Age: ',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              DropdownButton<int>(
                value: bmk.ebAges.contains(bmk.selectedEbAge)
                    ? bmk.selectedEbAge
                    : null,
                items: bmk.ebAges.map((age) {
                  return DropdownMenuItem(value: age, child: Text('${age}w'));
                }).toList(),
                onChanged: (age) {
                  if (age != null) bmk.setEbAge(age);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (bmk.ebRow == null)
            const Center(
              child: Text('No data', style: TextStyle(color: Colors.grey)),
            )
          else
            _buildEbParameters(bmk),
        ],
      ),
    );
  }

  Widget _buildEbParameters(BmkProvider bmk) {
    final eb = bmk.ebRow!;
    final type = bmk.selectedEbType;

    final Map<String, double> params;
    if (type == EbType.fresh) {
      params = {
        'Infertile': eb.infertilePct,
        'Early Dead 24h': eb.early24hPct,
        'Early Dead 48h': eb.early48hPct,
        'Blood Ring': eb.bloodRingPct,
      };
    } else if (type == EbType.candled) {
      params = {
        'Infertile': eb.infertilePct,
        'Early Dead 24h': eb.early24hPct,
        'Early Dead 48h': eb.early48hPct,
        'Blood Ring': eb.bloodRingPct,
        'Mid Black Eye': eb.midBlackEyePct,
      };
    } else {
      params = {
        'Infertile': eb.infertilePct,
        'Early Dead': eb.earlyDeadPct,
        'Mid Black Eye': eb.midBlackEyePct,
        'Feathers': eb.feathersPct,
        'Turned': eb.turnedPct,
        'Internal Pip': eb.internalPipPct,
        'Late Dead': eb.lateDeadPct,
        'External Pip': eb.externalPipPct,
        'Exposed Brain': eb.exposedBrainPct,
        'Crossed Beak': eb.crossedBeakPct,
        'Contaminated': eb.contamPct,
        'Cracked': eb.crackedPct,
      };
    }

    final entries = params.entries.toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                entry.key,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.value}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreedRow(BmkProvider bmk, List<String> breeds) {
    return Row(
      children: breeds.map((breed) {
        final isSelected = bmk.selectedBreed == breed;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Center(child: Text(breed)),
              selected: isSelected,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              onSelected: (_) => bmk.setBreed(breed),
            ),
          ),
        );
      }).toList(),
    );
  }
}
