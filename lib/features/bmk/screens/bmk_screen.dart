import 'dart:io';

import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/data/repositories/breeder_benchmark_repository.dart';
import 'package:hatchaudit/features/bmk/providers/bmk_provider.dart';
import 'package:hatchaudit/features/bmk/widgets/bmk_reference_widgets.dart';
import 'package:hatchaudit/features/breeder/widgets/breeder_bmk_sector_view.dart';
import 'package:hatchaudit/services/photo/photo_service.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:hatchaudit/widgets/section_card.dart';

enum _BmkMode { reference, admin }

class BmkScreen extends StatefulWidget {
  final PhotoService? photoService;
  final SupabaseService? supabaseService;
  final BreederBenchmarkRepository? breederBenchmarkRepository;

  const BmkScreen({
    super.key,
    this.photoService,
    this.supabaseService,
    this.breederBenchmarkRepository,
  });

  @override
  State<BmkScreen> createState() => _BmkScreenState();
}

class _BmkScreenState extends State<BmkScreen>
    with SingleTickerProviderStateMixin {
  final _breedFormKey = GlobalKey<FormState>();
  final _eggBreakoutFormKey = GlobalKey<FormState>();
  final _operationalFormKey = GlobalKey<FormState>();
  final _breedHatchabilityController = TextEditingController();
  final _breedFertilityController = TextEditingController();
  final _breedHofController = TextEditingController();
  final _breedProductionController = TextEditingController();
  final _breedEggWeightController = TextEditingController();
  final _breedChickWeightController = TextEditingController();
  final _ebInfertileController = TextEditingController();
  final _ebEarly24hController = TextEditingController();
  final _ebEarly48hController = TextEditingController();
  final _ebBloodRingController = TextEditingController();
  final _ebBlackEyeController = TextEditingController();
  final _ebEarlyDeadController = TextEditingController();
  final _ebMidDeadController = TextEditingController();
  final _ebLateDeadController = TextEditingController();
  final _ebExternalPipController = TextEditingController();
  final _ebCrackedController = TextEditingController();
  final _ebContamController = TextEditingController();
  final _opMinController = TextEditingController();
  final _opMaxController = TextEditingController();
  final _opTargetController = TextEditingController();
  final _opNotesController = TextEditingController();
  late final PhotoService _photoService = widget.photoService ?? PhotoService();
  late final SupabaseService _supabaseService =
      widget.supabaseService ?? SupabaseService();

  _BmkMode _mode = _BmkMode.reference;
  String? _breedEditKey;
  String? _ebEditKey;
  String? _opEditKey;
  bool _savingBreed = false;
  bool _savingEggBreakout = false;
  bool _savingOperational = false;

  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BmkProvider>().ensureInitialized();
    });
  }

  @override
  void dispose() {
    _breedHatchabilityController.dispose();
    _breedFertilityController.dispose();
    _breedHofController.dispose();
    _breedProductionController.dispose();
    _breedEggWeightController.dispose();
    _breedChickWeightController.dispose();
    _ebInfertileController.dispose();
    _ebEarly24hController.dispose();
    _ebEarly48hController.dispose();
    _ebBloodRingController.dispose();
    _ebBlackEyeController.dispose();
    _ebEarlyDeadController.dispose();
    _ebMidDeadController.dispose();
    _ebLateDeadController.dispose();
    _ebExternalPipController.dispose();
    _ebCrackedController.dispose();
    _ebContamController.dispose();
    _opMinController.dispose();
    _opMaxController.dispose();
    _opTargetController.dispose();
    _opNotesController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradientAppBar(
        title: 'BMK',
        toolbarHeight: isCompact ? 48 : 52,
        bottom: TabBar(
          key: const ValueKey('bmk-sector-tabs'),
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Hatchery'),
            Tab(text: 'Breeder Farm'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHatcherySector(isCompact),
          BreederBmkSectorView(
            key: const ValueKey('bmk-breeder-farm-sector'),
            repository: widget.breederBenchmarkRepository,
          ),
        ],
      ),
    );
  }

  /// Hatchery sector: the breed / egg-breakout / operational benchmarks that
  /// were the whole of this screen before the Breeder Farm tab existed.
  Widget _buildHatcherySector(bool isCompact) {
    return Consumer<BmkProvider>(
      builder: (context, bmk, child) {
        final user = context.watch<AuthProvider>().user;
        final canEditStandards =
            (user?.isApproved ?? false) &&
            ((user?.isAdmin ?? false) || (user?.isAuditor ?? false));
        if (!canEditStandards && _mode == _BmkMode.admin) {
          _mode = _BmkMode.reference;
        }
        // Global standards are cloud-writable by admins only
        // (bmk_operational_global_write). Auditors keep hatchery-scoped
        // override edits.
        bmk.setCanEditGlobalStandards(
          (user?.isApproved ?? false) && (user?.isAdmin ?? false),
        );
        _syncAdminControllers(bmk);

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
            isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
            isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
            AppSizes.spaceXl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canEditStandards) ...[
                    _buildModeToolbar(),
                    SizedBox(
                      height: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
                    ),
                  ],
                  if (_mode == _BmkMode.reference) ...[
                    _buildBreedSection(context, bmk),
                    SizedBox(
                      height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
                    ),
                    _buildEggBreakoutSection(context, bmk),
                    SizedBox(
                      height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
                    ),
                    _buildOperationalSection(context, bmk),
                  ] else ...[
                    _buildBreedAdminSection(context, bmk),
                    const SizedBox(height: AppSizes.spaceLg),
                    _buildEggBreakoutAdminSection(context, bmk),
                    const SizedBox(height: AppSizes.spaceLg),
                    _buildOperationalAdminSection(context, bmk),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreedSection(BuildContext context, BmkProvider bmk) {
    return BmkSectorCard(
      title: 'Breed Benchmarks',
      icon: Icons.analytics_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BmkControlShelf(
            primary: _buildBreedSelectorBar(bmk),
            secondary: BmkAgeControl(
              label: 'Reference age',
              value: bmk.breedAges.contains(bmk.selectedBreedAge)
                  ? bmk.selectedBreedAge
                  : null,
              ages: bmk.breedAges,
              onChanged: (age) {
                if (age != null) bmk.setBreedAge(age);
              },
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 520
                ? AppSizes.spaceSm
                : AppSizes.spaceLg,
          ),
          if (bmk.breedRow == null)
            const Center(
              child: Text('No data', style: TextStyle(color: Colors.grey)),
            )
          else
            BmkMetricGrid(
              key: const ValueKey('bmk-breed-metric-grid'),
              metrics: [
                // `bmk_breeds` stores 0.0 where a breed guide publishes no
                // value at this age, so a zero here means "not published",
                // not "the target is zero" — see formatBmkBenchmark.
                BmkMetric(
                  label: 'Hatchability',
                  value: _breedBenchmark(bmk.breedRow!.hatchabilityPct, '%'),
                ),
                BmkMetric(
                  label: 'Fertility',
                  value: _breedBenchmark(bmk.breedRow!.fertilityPct, '%'),
                ),
                BmkMetric(
                  label: 'HOF',
                  value: _breedBenchmark(bmk.breedRow!.hofPct, '%'),
                ),
                BmkMetric(
                  label: 'Production',
                  value: _breedBenchmark(bmk.breedRow!.productionPct, '%'),
                ),
                BmkMetric(
                  label: 'Egg weight',
                  value: _breedBenchmark(bmk.breedRow!.eggWeightG, ' g'),
                ),
                BmkMetric(
                  label: 'Chick weight',
                  value: _breedBenchmark(bmk.breedRow!.chickWeightG, ' g'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildModeToolbar() {
    return Container(
      key: const ValueKey('bmk-reference-mode-toolbar'),
      padding: const EdgeInsets.all(AppSizes.spaceXs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            label: 'Reference',
            icon: Icons.visibility_outlined,
            selected: _mode == _BmkMode.reference,
            onTap: () => setState(() => _mode = _BmkMode.reference),
          ),
          const SizedBox(width: AppSizes.spaceXs),
          _buildModeButton(
            label: 'Admin',
            icon: Icons.admin_panel_settings_outlined,
            selected: _mode == _BmkMode.admin,
            onTap: () => setState(() => _mode = _BmkMode.admin),
          ),
        ],
      ),
    );
  }

  void _showMetricSourceDialog(BuildContext context, BmkMetric metric) {
    final hasPhoto = metric.hasSourcePhoto;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(metric.label),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((metric.source ?? '').trim().isNotEmpty) ...[
                    Text('Source', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Text(metric.source!, style: AppTextStyles.body),
                  ],
                  if ((metric.sourceUrl ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: AppSizes.spaceMd),
                    Text('Link', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    InkWell(
                      key: metric.citationKey == null
                          ? null
                          : ValueKey('bmk-open-source-${metric.citationKey}'),
                      onTap: () => _openSourceUrl(context, metric.sourceUrl!),
                      child: Text(
                        metric.sourceUrl!,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                  if ((metric.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: AppSizes.spaceMd),
                    Text('Notes', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Text(metric.notes!, style: AppTextStyles.body),
                  ],
                  if (hasPhoto) ...[
                    const SizedBox(height: AppSizes.spaceMd),
                    Text('Photo', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.image_outlined, size: 18),
                        const SizedBox(width: AppSizes.spaceXs),
                        Expanded(
                          child: Text(
                            (metric.sourcePhotoRemotePath ?? '').isNotEmpty
                                ? 'Photo saved in cloud'
                                : 'Photo saved on this device',
                            style: AppTextStyles.body,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.spaceXs),
                    OutlinedButton.icon(
                      key: metric.citationKey == null
                          ? null
                          : ValueKey(
                              'bmk-view-source-photo-${metric.citationKey}',
                            ),
                      onPressed: () =>
                          _showSourcePhotoViewer(dialogContext, metric),
                      icon: const Icon(Icons.zoom_in_outlined),
                      label: const Text('View photo'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (metric.citationKey != null) ...[
              OutlinedButton.icon(
                key: ValueKey('bmk-add-source-photo-${metric.citationKey}'),
                onPressed: () =>
                    _addMetricSourcePhoto(context, dialogContext, metric),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(hasPhoto ? 'Replace photo' : 'Add photo'),
              ),
              if (hasPhoto)
                TextButton.icon(
                  key: ValueKey(
                    'bmk-delete-source-photo-${metric.citationKey}',
                  ),
                  onPressed: () =>
                      _deleteMetricSourcePhoto(context, dialogContext, metric),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete photo'),
                ),
            ],
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSourceUrl(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      messenger.showSnackBar(const SnackBar(content: Text('Invalid link')));
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  Future<void> _addMetricSourcePhoto(
    BuildContext context,
    BuildContext dialogContext,
    BmkMetric metric,
  ) async {
    final metricKey = metric.citationKey;
    if (metricKey == null) return;
    final provider = context.read<BmkProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(dialogContext);

    if (!provider.canEditGlobalStandards &&
        (provider.selectedHatcheryId == null ||
            provider.selectedHatcheryId!.isEmpty)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Global BMK defaults are admin-only. Pick a hatchery to save an '
            'override instead.',
          ),
        ),
      );
      return;
    }

    final photoPath = await _photoService.pickPhoto(
      fromCamera: false,
      imageQuality: 100,
    );
    if (photoPath == null || photoPath.isEmpty) return;
    final remotePath = await _supabaseService.uploadBmkOperationalSourcePhoto(
      localPath: photoPath,
      metricKey: metricKey,
      hatcheryId: provider.selectedHatcheryId,
    );
    await provider.saveOperationalSourcePhoto(
      metricKey: metricKey,
      photoPath: photoPath,
      remotePath: remotePath,
    );
    final oldRemotePath = metric.sourcePhotoRemotePath;
    if (remotePath != null &&
        oldRemotePath != null &&
        oldRemotePath.isNotEmpty) {
      await _supabaseService.deleteBmkOperationalSourcePhoto(oldRemotePath);
    }
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          remotePath == null
              ? 'Source photo saved locally; cloud upload unavailable'
              : 'Source photo saved',
        ),
      ),
    );
  }

  Future<void> _deleteMetricSourcePhoto(
    BuildContext context,
    BuildContext dialogContext,
    BmkMetric metric,
  ) async {
    final metricKey = metric.citationKey;
    if (metricKey == null) return;
    final provider = context.read<BmkProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(dialogContext);
    if (!provider.canEditGlobalStandards &&
        (provider.selectedHatcheryId == null ||
            provider.selectedHatcheryId!.isEmpty)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Global BMK defaults are admin-only. Pick a hatchery to save an '
            'override instead.',
          ),
        ),
      );
      return;
    }
    await _supabaseService.deleteBmkOperationalSourcePhoto(
      metric.sourcePhotoRemotePath,
    );
    final localPath = metric.sourcePhotoPath;
    if (localPath != null && localPath.isNotEmpty) {
      await _photoService.deletePhoto(localPath);
    }
    await provider.deleteOperationalSourcePhoto(metricKey: metricKey);
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Source photo deleted')),
    );
  }

  void _showSourcePhotoViewer(BuildContext context, BmkMetric metric) {
    final path = metric.sourcePhotoPath;
    final url = metric.sourcePhotoRemotePath;
    Widget image;
    if (path != null && path.trim().isNotEmpty) {
      image = Image.file(File(path), fit: BoxFit.contain);
    } else if (url != null && url.startsWith('http')) {
      image = Image.network(url, fit: BoxFit.contain);
    } else {
      image = const Center(child: Text('Photo preview is not available'));
    }

    showDialog<void>(
      context: context,
      builder: (viewerContext) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(metric.label),
              actions: [
                IconButton(
                  tooltip: context.tr('Close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(viewerContext).pop(),
                ),
              ],
            ),
            body: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: image,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return BmkSelectablePill(
      label: label,
      icon: icon,
      selected: selected,
      onTap: onTap,
    );
  }

  Widget _buildBreedSelectorBar(BmkProvider bmk) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 6
            : width >= 620
            ? 3
            : width >= 300
            ? 3
            : 2;
        const spacing = AppSizes.spaceXs;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          key: const ValueKey('bmk-breed-selector-bar'),
          spacing: spacing,
          runSpacing: spacing,
          children: BmkProvider.breeds.map((breed) {
            return SizedBox(
              width: itemWidth,
              child: BmkSelectablePill(
                label: breed,
                icon: bmk.selectedBreed == breed ? Icons.check : null,
                selected: bmk.selectedBreed == breed,
                onTap: () => bmk.setBreed(breed),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBreedAdminSection(BuildContext context, BmkProvider bmk) {
    return SectionCard(
      title: 'Breed BMK Admin',
      icon: Icons.edit_note_outlined,
      child: Form(
        key: _breedFormKey,
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
            _buildAgePicker(
              label: 'Age',
              value: bmk.breedAges.contains(bmk.selectedBreedAge)
                  ? bmk.selectedBreedAge
                  : null,
              ages: bmk.breedAges,
              onChanged: (age) {
                if (age != null) bmk.setBreedAge(age);
              },
            ),
            const SizedBox(height: 18),
            if (bmk.breedRow == null)
              const Center(
                child: Text('No data', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              _buildFieldGrid([
                _AdminNumberField(
                  label: 'Hatchability',
                  suffix: '%',
                  controller: _breedHatchabilityController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Fertility',
                  suffix: '%',
                  controller: _breedFertilityController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'HOF',
                  suffix: '%',
                  controller: _breedHofController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Production',
                  suffix: '%',
                  controller: _breedProductionController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Egg weight',
                  suffix: 'g',
                  controller: _breedEggWeightController,
                ),
                _AdminNumberField(
                  label: 'Chick weight',
                  suffix: 'g',
                  controller: _breedChickWeightController,
                ),
              ]),
              const SizedBox(height: 16),
              _buildAdminActions(
                isSaving: _savingBreed,
                onReset: () => _syncBreedControllers(bmk.breedRow, force: true),
                onSave: () => _saveBreedBenchmark(context, bmk),
                saveLabel: 'Save breed BMK',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEggBreakoutAdminSection(BuildContext context, BmkProvider bmk) {
    return SectionCard(
      title: 'Egg Breakout BMK Admin',
      icon: Icons.edit_note_outlined,
      child: Form(
        key: _eggBreakoutFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAgePicker(
              label: 'Age',
              value: bmk.ebAges.contains(bmk.selectedEbAge)
                  ? bmk.selectedEbAge
                  : null,
              ages: bmk.ebAges,
              onChanged: (age) {
                if (age != null) bmk.setEbAge(age);
              },
            ),
            const SizedBox(height: 18),
            if (bmk.ebRow == null)
              const Center(
                child: Text('No data', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              _buildFieldGrid([
                _AdminNumberField(
                  label: 'Infertile',
                  suffix: '%',
                  controller: _ebInfertileController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: '24 hours',
                  suffix: '%',
                  controller: _ebEarly24hController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: '48 hours',
                  suffix: '%',
                  controller: _ebEarly48hController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Blood Ring',
                  suffix: '%',
                  controller: _ebBloodRingController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Black Eye',
                  suffix: '%',
                  controller: _ebBlackEyeController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Early Dead',
                  suffix: '%',
                  controller: _ebEarlyDeadController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Mid Dead',
                  suffix: '%',
                  controller: _ebMidDeadController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Late Dead',
                  suffix: '%',
                  controller: _ebLateDeadController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'External Pip',
                  suffix: '%',
                  controller: _ebExternalPipController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Cracked',
                  suffix: '%',
                  controller: _ebCrackedController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Contaminated',
                  suffix: '%',
                  controller: _ebContamController,
                  isPercent: true,
                ),
              ]),
              const SizedBox(height: 16),
              _buildAdminActions(
                isSaving: _savingEggBreakout,
                onReset: () =>
                    _syncEggBreakoutControllers(bmk.ebRow, force: true),
                onSave: () => _saveEggBreakoutBenchmark(context, bmk),
                saveLabel: 'Save breakout BMK',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOperationalAdminSection(BuildContext context, BmkProvider bmk) {
    final selected = bmk.selectedOperationalStandard;
    return SectionCard(
      title: 'Operational BMK Admin',
      icon: Icons.tune_outlined,
      child: Form(
        key: _operationalFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOperationalHatcherySelector(bmk),
            const SizedBox(height: AppSizes.spaceMd),
            _buildOperationalSelector(bmk),
            const SizedBox(height: 18),
            if (selected == null)
              const Center(
                child: Text('No data', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              Text(
                '${selected.stationKey} · ${selected.sectorKey}',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSizes.spaceSm),
              _buildFieldGrid([
                _AdminNumberField(
                  label: 'Min',
                  suffix: selected.unit,
                  controller: _opMinController,
                  isPercent: selected.unit == '%',
                  requiredField: false,
                ),
                _AdminNumberField(
                  label: 'Max',
                  suffix: selected.unit,
                  controller: _opMaxController,
                  isPercent: selected.unit == '%',
                  requiredField: false,
                ),
                _AdminNumberField(
                  label: 'Target',
                  suffix: selected.unit,
                  controller: _opTargetController,
                  isPercent: selected.unit == '%',
                  requiredField: false,
                ),
              ]),
              const SizedBox(height: AppSizes.spaceMd),
              TextFormField(
                controller: _opNotesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Operational notes',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSizes.spaceMd),
              if (selected.source != null && selected.source!.isNotEmpty)
                Text(
                  'Source: ${selected.source}',
                  style: AppTextStyles.caption,
                ),
              const SizedBox(height: AppSizes.spaceMd),
              _buildAdminActions(
                isSaving: _savingOperational,
                onReset: () =>
                    _syncOperationalControllers(selected, force: true),
                onSave: () => _saveOperationalBenchmark(context, bmk),
                saveLabel: 'Save operational BMK',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAgePicker({
    required String label,
    required int? value,
    required List<int> ages,
    required ValueChanged<int?> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        DropdownButton<int>(
          value: value,
          items: ages.map((age) {
            return DropdownMenuItem(value: age, child: Text('${age}w'));
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildFieldGrid(List<_AdminNumberField> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 760
            ? 3
            : width >= 520
            ? 2
            : 1;
        final spacing = AppSizes.spaceMd;
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: fields.map((field) {
            return SizedBox(
              width: itemWidth,
              child: TextFormField(
                controller: field.controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: field.label,
                  suffixText: field.suffix,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (value) {
                  return _numberValidator(
                    value,
                    isPercent: field.isPercent,
                    requiredField: field.requiredField,
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAdminActions({
    required bool isSaving,
    required VoidCallback onReset,
    required VoidCallback onSave,
    required String saveLabel,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: isSaving ? null : onSave,
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(isSaving ? 'Saving' : saveLabel),
        ),
        OutlinedButton.icon(
          onPressed: isSaving ? null : onReset,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Reset'),
        ),
      ],
    );
  }

  Widget _buildEggBreakoutSection(BuildContext context, BmkProvider bmk) {
    return BmkSectorCard(
      title: 'Egg Breakout BMK',
      icon: Icons.egg_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BmkControlShelf(
            primary: _buildBreakoutTypeSelector(bmk),
            secondary: BmkAgeControl(
              label: 'Benchmark age',
              value: bmk.ebAges.contains(bmk.selectedEbAge)
                  ? bmk.selectedEbAge
                  : null,
              ages: bmk.ebAges,
              onChanged: (age) {
                if (age != null) bmk.setEbAge(age);
              },
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 520
                ? AppSizes.spaceSm
                : AppSizes.spaceLg,
          ),
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

  Widget _buildOperationalSection(BuildContext context, BmkProvider bmk) {
    return BmkSectorCard(
      title: 'Operational BMKs',
      icon: Icons.tune_outlined,
      child: bmk.operationalStandards.isEmpty
          ? const Center(
              child: Text('No data', style: TextStyle(color: Colors.grey)),
            )
          : _buildOperationalGroups(bmk.operationalStandards),
    );
  }

  Widget _buildOperationalGroups(List<BmkOperationalStandardModel> rows) {
    final grouped = <String, List<BmkOperationalStandardModel>>{};
    for (final row in rows) {
      final key = _operationalCategoryKey(row);
      grouped.putIfAbsent(key, () => []).add(row);
    }

    final children = <Widget>[];
    for (final category in _operationalCategories) {
      final categoryRows = grouped[category.key];
      if (categoryRows == null || categoryRows.isEmpty) continue;
      if (children.isNotEmpty) children.add(const SizedBox(height: 18));
      children.add(
        _OperationalCategorySection(
          title: category.label,
          child: BmkMetricGrid(
            key: ValueKey('bmk-operational-${category.key}-grid'),
            onCitationTap: (metric) => _showMetricSourceDialog(context, metric),
            metrics: categoryRows.map((row) {
              return BmkMetric(
                label: row.metricLabel,
                value: _formatOperationalValue(row),
                source: row.source,
                sourceUrl: row.sourceUrl,
                sourcePhotoPath: row.sourcePhotoPath,
                sourcePhotoRemotePath: row.sourcePhotoRemotePath,
                notes: row.notes,
                citationKey: row.metricKey,
              );
            }).toList(),
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('bmk-operational-metric-grid'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildOperationalSelector(BmkProvider bmk) {
    final rows = bmk.operationalStandards;
    final selected = bmk.selectedOperationalStandard;
    return Container(
      key: const ValueKey('bmk-operational-standard-selector'),
      constraints: const BoxConstraints(maxWidth: 520),
      child: DropdownButtonFormField<String>(
        initialValue: selected?.metricKey,
        decoration: const InputDecoration(
          labelText: 'Operational BMK',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: rows.map((row) {
          return DropdownMenuItem(
            value: row.metricKey,
            child: Text(
              row.metricLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (metricKey) {
          if (metricKey != null) bmk.setOperationalMetric(metricKey);
        },
      ),
    );
  }

  Widget _buildOperationalHatcherySelector(BmkProvider bmk) {
    return Container(
      key: const ValueKey('bmk-operational-hatchery-selector'),
      constraints: const BoxConstraints(maxWidth: 520),
      child: DropdownButtonFormField<String>(
        initialValue: bmk.selectedHatcheryId ?? '',
        decoration: const InputDecoration(
          labelText: 'BMK scope',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Global defaults')),
          for (final hatchery in bmk.operationalHatcheries)
            DropdownMenuItem(value: hatchery.id, child: Text(hatchery.label)),
        ],
        onChanged: (value) {
          bmk.setOperationalHatchery(
            value == null || value.isEmpty ? null : value,
          );
        },
      ),
    );
  }

  Widget _buildBreakoutTypeSelector(BmkProvider bmk) {
    final types = [
      _BreakoutTypeOption(type: EbType.fresh, label: 'Fresh'),
      _BreakoutTypeOption(type: EbType.candled, label: 'Candled'),
      _BreakoutTypeOption(type: EbType.residue, label: 'Residue'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 300 ? 3 : 1;
        final spacing = width < 520 ? AppSizes.spaceXs : AppSizes.spaceSm;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          key: const ValueKey('bmk-breakout-type-selector'),
          spacing: spacing,
          runSpacing: spacing,
          children: types.map((option) {
            final selected = bmk.selectedEbType == option.type;
            return SizedBox(
              width: itemWidth,
              child: BmkSelectablePill(
                label: option.label,
                selected: selected,
                onTap: () => bmk.setEbType(option.type),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEbParameters(BmkProvider bmk) {
    final eb = bmk.ebRow!;
    final type = bmk.selectedEbType;

    final List<BmkMetric> metrics;
    if (type == EbType.fresh) {
      metrics = [
        _breakoutMetric('Infertile', eb.infertilePct),
        _breakoutMetric('24 hours', eb.early24hPct),
        _breakoutMetric('48 hours', eb.early48hPct),
        _breakoutMetric('Blood ring', eb.bloodRingPct),
      ];
    } else if (type == EbType.candled) {
      metrics = [
        _breakoutMetric('Infertile', eb.infertilePct),
        _breakoutMetric('24 hours', eb.early24hPct),
        _breakoutMetric('48 hours', eb.early48hPct),
        _breakoutMetric('Blood ring', eb.bloodRingPct),
        _breakoutMetric('Black eye', eb.blackEyePct),
      ];
    } else {
      metrics = [
        _breakoutMetric('Infertile', eb.infertilePct),
        _breakoutMetric('Early dead', eb.earlyDeadPct),
        _breakoutMetric('Mid dead', eb.midDeadPct),
        _breakoutMetric('Late dead', eb.lateDeadPct),
        _breakoutMetric('External pip', eb.externalPipPct),
        _breakoutMetric('Cracked', eb.crackedPct),
        _breakoutMetric('Contaminated', eb.contamPct),
      ];
    }

    return BmkMetricGrid(
      key: const ValueKey('bmk-breakout-metric-grid'),
      metrics: metrics,
    );
  }

  BmkMetric _breakoutMetric(String label, double value) {
    return BmkMetric(label: label, value: '${_formatNumber(value)}%');
  }

  void _syncAdminControllers(BmkProvider bmk) {
    _syncBreedControllers(bmk.breedRow);
    _syncEggBreakoutControllers(bmk.ebRow);
    _syncOperationalControllers(bmk.selectedOperationalStandard);
  }

  void _syncBreedControllers(BmkBreedModel? row, {bool force = false}) {
    final key = row == null ? null : '${row.breed}-${row.ageWeek}';
    if (!force && key == _breedEditKey) return;
    _breedEditKey = key;
    _breedHatchabilityController.text = _formatNumber(row?.hatchabilityPct);
    _breedFertilityController.text = _formatNumber(row?.fertilityPct);
    _breedHofController.text = _formatNumber(row?.hofPct);
    _breedProductionController.text = _formatNumber(row?.productionPct);
    _breedEggWeightController.text = _formatNumber(row?.eggWeightG);
    _breedChickWeightController.text = _formatNumber(row?.chickWeightG);
  }

  void _syncEggBreakoutControllers(
    BmkEggBreakoutModel? row, {
    bool force = false,
  }) {
    final key = row == null ? null : '${row.ageWeek}';
    if (!force && key == _ebEditKey) return;
    _ebEditKey = key;
    _ebInfertileController.text = _formatNumber(row?.infertilePct);
    _ebEarly24hController.text = _formatNumber(row?.early24hPct);
    _ebEarly48hController.text = _formatNumber(row?.early48hPct);
    _ebBloodRingController.text = _formatNumber(row?.bloodRingPct);
    _ebBlackEyeController.text = _formatNumber(row?.blackEyePct);
    _ebEarlyDeadController.text = _formatNumber(row?.earlyDeadPct);
    _ebMidDeadController.text = _formatNumber(row?.midDeadPct);
    _ebLateDeadController.text = _formatNumber(row?.lateDeadPct);
    _ebExternalPipController.text = _formatNumber(row?.externalPipPct);
    _ebCrackedController.text = _formatNumber(row?.crackedPct);
    _ebContamController.text = _formatNumber(row?.contamPct);
  }

  void _syncOperationalControllers(
    BmkOperationalStandardModel? row, {
    bool force = false,
  }) {
    final key = row?.id;
    if (!force && key == _opEditKey) return;
    _opEditKey = key;
    _opMinController.text = _formatNumber(row?.minValue);
    _opMaxController.text = _formatNumber(row?.maxValue);
    _opTargetController.text = _formatNumber(row?.targetValue);
    _opNotesController.text = row?.notes ?? '';
  }

  Future<void> _saveBreedBenchmark(
    BuildContext context,
    BmkProvider bmk,
  ) async {
    if (_breedFormKey.currentState?.validate() != true) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingBreed = true);
    try {
      await bmk.saveSelectedBreedBenchmark(
        hatchabilityPct: _parseController(_breedHatchabilityController),
        fertilityPct: _parseController(_breedFertilityController),
        hofPct: _parseController(_breedHofController),
        productionPct: _parseController(_breedProductionController),
        eggWeightG: _parseController(_breedEggWeightController),
        chickWeightG: _parseController(_breedChickWeightController),
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Breed BMK saved')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save breed BMK: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingBreed = false);
    }
  }

  Future<void> _saveEggBreakoutBenchmark(
    BuildContext context,
    BmkProvider bmk,
  ) async {
    if (_eggBreakoutFormKey.currentState?.validate() != true) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingEggBreakout = true);
    try {
      await bmk.saveSelectedEggBreakoutBenchmark(
        infertilePct: _parseController(_ebInfertileController),
        early24hPct: _parseController(_ebEarly24hController),
        early48hPct: _parseController(_ebEarly48hController),
        bloodRingPct: _parseController(_ebBloodRingController),
        blackEyePct: _parseController(_ebBlackEyeController),
        earlyDeadPct: _parseController(_ebEarlyDeadController),
        midDeadPct: _parseController(_ebMidDeadController),
        lateDeadPct: _parseController(_ebLateDeadController),
        externalPipPct: _parseController(_ebExternalPipController),
        crackedPct: _parseController(_ebCrackedController),
        contamPct: _parseController(_ebContamController),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Egg Breakout BMK saved')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save Egg Breakout BMK: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingEggBreakout = false);
    }
  }

  Future<void> _saveOperationalBenchmark(
    BuildContext context,
    BmkProvider bmk,
  ) async {
    if (_operationalFormKey.currentState?.validate() != true) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingOperational = true);
    try {
      await bmk.saveSelectedOperationalStandard(
        minValue: _parseOptionalController(_opMinController),
        maxValue: _parseOptionalController(_opMaxController),
        targetValue: _parseOptionalController(_opTargetController),
        notes: _opNotesController.text.trim().isEmpty
            ? null
            : _opNotesController.text.trim(),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Operational BMK saved')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save operational BMK: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingOperational = false);
    }
  }

  String? _numberValidator(
    String? value, {
    required bool isPercent,
    bool requiredField = true,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty && !requiredField) return null;
    if (text.isEmpty) return 'Required';
    final number = double.tryParse(text);
    if (number == null) return 'Enter a number';
    if (number < 0) return 'Must be 0 or more';
    if (isPercent && number > 100) return 'Max 100';
    return null;
  }

  double _parseController(TextEditingController controller) {
    return double.parse(controller.text.trim());
  }

  double? _parseOptionalController(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.parse(text);
  }

  String _formatNumber(double? value) => formatBmkNumber(value);

  /// Breed reference values, with a stored zero rendered as "not published".
  String _breedBenchmark(double? value, String unit) =>
      formatBmkBenchmark(value, unit: unit, treatZeroAsMissing: true);

  String _formatOperationalValue(BmkOperationalStandardModel row) {
    final min = row.minValue;
    final max = row.maxValue;
    final target = row.targetValue;
    final unit = row.unit;
    if (min != null && max != null) {
      return '${_formatNumber(min)}-${_formatNumber(max)}$unit';
    }
    if (min != null) return '>= ${_formatNumber(min)}$unit';
    if (max != null) return '<= ${_formatNumber(max)}$unit';
    if (target != null) return '${_formatNumber(target)}$unit';
    return '--';
  }

  String _operationalCategoryKey(BmkOperationalStandardModel row) {
    if (row.metricKey == 'culled_chicks' || row.metricKey == 'dead_chicks') {
      return 'hatch_results';
    }
    if (row.metricKey == 'co2_max') return 'setters';
    if (row.metricKey == 'cv_alert' ||
        row.metricKey == 'uniformity_good' ||
        row.metricKey == 'shell_uv_affected') {
      return 'egg';
    }

    return switch (row.stationKey) {
      'egg' => 'egg',
      'chicks' => 'chicks',
      'hatch_results' || 'hatch_analysis' => 'hatch_results',
      'setters' => 'setters',
      'hatchers' => 'hatchers',
      _ => 'egg',
    };
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

const List<_OperationalCategory> _operationalCategories = [
  _OperationalCategory(key: 'egg', label: 'Egg'),
  _OperationalCategory(key: 'chicks', label: 'Chicks'),
  _OperationalCategory(key: 'hatch_results', label: 'Hatch Results'),
  _OperationalCategory(key: 'setters', label: 'Setters'),
  _OperationalCategory(key: 'hatchers', label: 'Hatchers'),
];

class _OperationalCategory {
  final String key;
  final String label;

  const _OperationalCategory({required this.key, required this.label});
}

class _OperationalCategorySection extends StatelessWidget {
  final String title;
  final Widget child;

  const _OperationalCategorySection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
            vertical: isCompact ? 4 : AppSizes.spaceXs,
          ),
          decoration: BoxDecoration(
            color: AppColors.activeBg,
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          ),
          child: Text(
            title,
            style: AppTextStyles.title.copyWith(
              color: AppColors.primary,
              fontSize: isCompact ? 13 : null,
            ),
          ),
        ),
        SizedBox(height: isCompact ? AppSizes.spaceXs : AppSizes.spaceSm),
        child,
      ],
    );
  }
}

class _BreakoutTypeOption {
  final EbType type;
  final String label;

  const _BreakoutTypeOption({required this.type, required this.label});
}

class _AdminNumberField {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final bool isPercent;
  final bool requiredField;

  const _AdminNumberField({
    required this.label,
    required this.suffix,
    required this.controller,
    this.isPercent = false,
    this.requiredField = true,
  });
}
