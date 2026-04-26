import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/audit_model.dart';
import '../photo_button.dart';

class PmNecropsyTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;

  const PmNecropsyTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
  });

  @override
  State<PmNecropsyTab> createState() => _PmNecropsyTabState();
}

class _PmNecropsyTabState extends State<PmNecropsyTab> {
  static const _severityOptions = ['Mild', 'Moderate', 'Severe'];
  static const _gaspingTypes = [
    'Abdominal',
    'Thoracic',
    'Obstructive',
    'Mixed',
  ];

  late TextEditingController _sampleSizeController;
  late TextEditingController _collectionPointController;
  late TextEditingController _suspectedCauseManualController;

  final Map<String, TextEditingController> _lesionControllers = {};
  final Map<String, TextEditingController> _deformityControllers = {};
  late TextEditingController _otherDeformityTextController;

  @override
  void initState() {
    super.initState();
    _sampleSizeController = TextEditingController(
      text: widget.audit.pmSampleSize?.toString() ?? '',
    );
    _collectionPointController = TextEditingController(
      text: widget.audit.pmCollectionPoint ?? '',
    );
    _suspectedCauseManualController = TextEditingController(
      text: widget.audit.pmSuspectedCauseManual ?? '',
    );
    _otherDeformityTextController = TextEditingController(
      text: widget.audit.pmOtherDeformityText ?? '',
    );
  }

  @override
  void dispose() {
    _sampleSizeController.dispose();
    _collectionPointController.dispose();
    _suspectedCauseManualController.dispose();
    _otherDeformityTextController.dispose();
    for (final c in _lesionControllers.values) {
      c.dispose();
    }
    for (final c in _deformityControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _lesionController(String key, int? initialValue) {
    if (!_lesionControllers.containsKey(key)) {
      _lesionControllers[key] = TextEditingController(
        text: (initialValue ?? 0) > 0 ? initialValue.toString() : '',
      );
    }
    return _lesionControllers[key]!;
  }

  TextEditingController _deformityController(String key, int? initialValue) {
    if (!_deformityControllers.containsKey(key)) {
      _deformityControllers[key] = TextEditingController(
        text: (initialValue ?? 0) > 0 ? initialValue.toString() : '',
      );
    }
    return _deformityControllers[key]!;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSampleMetadataCard(),
          const SizedBox(height: 16),
          _buildLesionCard(),
          const SizedBox(height: 16),
          _buildGaspingCard(),
          const SizedBox(height: 16),
          _buildDeformityCard(),
          const SizedBox(height: 16),
          _buildPhotosCard(),
          const SizedBox(height: 16),
          _buildSummaryCard(),
        ],
      ),
    );
  }

  Widget _buildSampleMetadataCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.biotech, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Sample Metadata',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sampleSizeController,
              enabled: !widget.isReadOnly,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Sample Size',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) {
                widget.onFieldChanged(
                  'pm_sampleSize',
                  int.tryParse(value) ?? 0,
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _collectionPointController,
              enabled: !widget.isReadOnly,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Collection Point',
              ),
              onChanged: (value) {
                widget.onFieldChanged('pm_collectionPoint', value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLesionCard() {
    final lesions = [
      {
        'label': 'Omphalitis',
        'field': 'pm_omphalitis',
        'count': widget.audit.pmOmphalitisCount,
        'severity': widget.audit.pmOmphalitisSeverity,
      },
      {
        'label': 'Gaseous Ceca',
        'field': 'pm_gaseousCeca',
        'count': widget.audit.pmGaseousCecaCount,
        'severity': widget.audit.pmGaseousCecaSeverity,
      },
      {
        'label': 'Unabsorbed Yolk',
        'field': 'pm_unabsorbedYolk',
        'count': widget.audit.pmUnabsorbedYolkCount,
        'severity': widget.audit.pmUnabsorbedYolkSeverity,
      },
      {
        'label': 'Perihepatitis',
        'field': 'pm_perihepatitis',
        'count': widget.audit.pmPerihepatitisCount,
        'severity': widget.audit.pmPerihepatitisSeverity,
      },
      {
        'label': 'Pericarditis',
        'field': 'pm_pericarditis',
        'count': widget.audit.pmPericarditisCount,
        'severity': widget.audit.pmPericarditisSeverity,
      },
      {
        'label': 'Airsac Acute',
        'field': 'pm_airsacAcute',
        'count': widget.audit.pmAirsacAcuteCount,
        'severity': widget.audit.pmAirsacAcuteSeverity,
      },
      {
        'label': 'Airsac Chronic',
        'field': 'pm_airsacChronic',
        'count': widget.audit.pmAirsacChronicCount,
        'severity': widget.audit.pmAirsacChronicSeverity,
      },
      {
        'label': 'Pulmonary Granuloma',
        'field': 'pm_pulmonaryGranuloma',
        'count': widget.audit.pmPulmonaryGranulomaCount,
        'severity': widget.audit.pmPulmonaryGranulomaSeverity,
      },
      {
        'label': 'Swollen Joints',
        'field': 'pm_swollenJoints',
        'count': widget.audit.pmSwollenJointsCount,
        'severity': widget.audit.pmSwollenJointsSeverity,
      },
      {
        'label': 'Stunted Organs',
        'field': 'pm_stuntedOrgans',
        'count': widget.audit.pmStuntedOrgansCount,
        'severity': widget.audit.pmStuntedOrgansSeverity,
      },
      {
        'label': 'Pulmonary Hemorrhage',
        'field': 'pm_pulmonaryHemorrhage',
        'count': widget.audit.pmPulmonaryHemorrhageCount,
        'severity': widget.audit.pmPulmonaryHemorrhageSeverity,
      },
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medical_services, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Lesion Observations',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...lesions.map((lesion) {
              final label = lesion['label'] as String;
              final fieldBase = lesion['field'] as String;
              final count = lesion['count'] as int?;
              final severity = lesion['severity'] as String?;
              final countKey = '${fieldBase}Count';
              final severityKey = '${fieldBase}Severity';
              final controller = _lesionController(fieldBase, count);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(label, style: AppTextStyles.body),
                        ),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: controller,
                            enabled: !widget.isReadOnly,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: 'Count',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              isDense: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (value) {
                              widget.onFieldChanged(
                                countKey,
                                int.tryParse(value) ?? 0,
                              );
                              setState(() {});
                            },
                          ),
                        ),
                        if (widget.isReadOnly) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              severity ?? 'N/A',
                              style: AppTextStyles.caption,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: severity,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: 'Severity',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                isDense: true,
                              ),
                              items: _severityOptions.map((s) {
                                return DropdownMenuItem(
                                  value: s,
                                  child: Text(s, style: const TextStyle(fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (value) {
                                widget.onFieldChanged(severityKey, value);
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildGaspingCard() {
    final gaspingPresent = widget.audit.pmGaspingPresent ?? false;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.air, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Gasping',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(
                'Gasping Present',
                style: AppTextStyles.body,
              ),
              value: gaspingPresent,
              contentPadding: EdgeInsets.zero,
              activeTrackColor: AppColors.primary,
              onChanged: widget.isReadOnly
                  ? null
                  : (value) {
                      widget.onFieldChanged('pm_gaspingPresent', value ? 1 : 0);
                      setState(() {});
                    },
            ),
            if (gaspingPresent) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.audit.pmGaspingType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Gasping Type',
                ),
                items: _gaspingTypes.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: widget.isReadOnly
                    ? null
                    : (value) {
                        widget.onFieldChanged('pm_gaspingType', value);
                        setState(() {});
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeformityCard() {
    final deformities = [
      {
        'label': 'Exposed Brain',
        'field': 'pm_exposedBrainCount',
        'value': widget.audit.pmExposedBrainCount,
      },
      {
        'label': 'Ectopic Viscera',
        'field': 'pm_ectopicVisceraCount',
        'value': widget.audit.pmEctopicVisceraCount,
      },
      {
        'label': 'Extra Legs',
        'field': 'pm_extraLegsCount',
        'value': widget.audit.pmExtraLegsCount,
      },
      {
        'label': 'Crossed Beak',
        'field': 'pm_crossedBeakCount',
        'value': widget.audit.pmCrossedBeakCount,
      },
      {
        'label': 'Absent Eye (Both)',
        'field': 'pm_absentEyeBothCount',
        'value': widget.audit.pmAbsentEyeBothCount,
      },
      {
        'label': 'Absent Eye (One)',
        'field': 'pm_absentEyeOneCount',
        'value': widget.audit.pmAbsentEyeOneCount,
      },
      {
        'label': 'Small Eye',
        'field': 'pm_smallEyeCount',
        'value': widget.audit.pmSmallEyeCount,
      },
      {
        'label': 'Hydrocephaly',
        'field': 'pm_hydrocephalyCount',
        'value': widget.audit.pmHydrocephalyCount,
      },
      {
        'label': 'Star Gazer',
        'field': 'pm_starGazerCount',
        'value': widget.audit.pmStarGazerCount,
      },
      {
        'label': 'Curled Toes',
        'field': 'pm_curledToesCount',
        'value': widget.audit.pmCurledToesCount,
      },
      {
        'label': 'Short Legs',
        'field': 'pm_shortLegsCount',
        'value': widget.audit.pmShortLegsCount,
      },
      {
        'label': 'Spinal Deformity',
        'field': 'pm_spinalDeformityCount',
        'value': widget.audit.pmSpinalDeformityCount,
      },
      {
        'label': 'Cardiac Anomaly',
        'field': 'pm_cardiacAnomalyCount',
        'value': widget.audit.pmCardiacAnomalyCount,
      },
      {
        'label': 'Conjoined',
        'field': 'pm_conjoinedCount',
        'value': widget.audit.pmConjoinedCount,
      },
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.accessible, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Deformities',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...deformities.map((def) {
              final label = def['label'] as String;
              final fieldKey = def['field'] as String;
              final value = def['value'] as int?;
              final controller = _deformityController(fieldKey, value);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: AppTextStyles.body),
                    ),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: controller,
                        enabled: !widget.isReadOnly,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'Count',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) {
                          widget.onFieldChanged(
                            fieldKey,
                            int.tryParse(value) ?? 0,
                          );
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Other Deformity',
                    style: AppTextStyles.body,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _deformityController(
                      'pm_otherDeformityCount',
                      widget.audit.pmOtherDeformityCount,
                    ),
                    enabled: !widget.isReadOnly,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Count',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (value) {
                      widget.onFieldChanged(
                        'pm_otherDeformityCount',
                        int.tryParse(value) ?? 0,
                      );
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            if ((widget.audit.pmOtherDeformityCount ?? 0) > 0 ||
                !widget.isReadOnly) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _otherDeformityTextController,
                enabled: !widget.isReadOnly,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Other Deformity Description',
                ),
                onChanged: (value) {
                  widget.onFieldChanged('pm_otherDeformityText', value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosCard() {
    final photosJson = widget.audit.pmPhotosJson;
    List<String> photoPaths = [];
    if (photosJson != null && photosJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(photosJson);
        if (decoded is List) {
          photoPaths = decoded.cast<String>();
        }
      } catch (_) {}
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_camera, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'PM Necropsy Photos',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!widget.isReadOnly)
              PhotoButton(
                photoPath: null,
                enabled: !widget.isReadOnly,
                onPhotoCaptured: (path) {
                  final updatedPaths = List<String>.from(photoPaths);
                  updatedPaths.add(path);
                  widget.onFieldChanged(
                    'pm_photosJson',
                    jsonEncode(updatedPaths),
                  );
                  setState(() {});
                },
              ),
            if (photoPaths.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${photoPaths.length} photo(s) attached',
                style: AppTextStyles.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'PM Summary',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.audit.pmSuspectedCauseAuto != null &&
                widget.audit.pmSuspectedCauseAuto!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto-Suggested Cause',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.audit.pmSuspectedCauseAuto!,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _suspectedCauseManualController,
              enabled: !widget.isReadOnly,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Manual Suspected Cause (override)',
              ),
              onChanged: (value) {
                widget.onFieldChanged('pm_suspectedCauseManual', value);
              },
            ),
          ],
        ),
      ),
    );
  }
}
