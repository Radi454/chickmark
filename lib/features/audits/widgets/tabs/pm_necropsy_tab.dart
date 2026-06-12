import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/audit_model.dart';
import '../audit_numeric_keyboard.dart';
import '../photo_button.dart';

class PmNecropsyTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final bool embedded;

  const PmNecropsyTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    this.embedded = false,
  });

  @override
  State<PmNecropsyTab> createState() => _PmNecropsyTabState();
}

class _PmNecropsyTabState extends State<PmNecropsyTab> {
  static const _severityOptions = ['Mild', 'Moderate', 'Severe'];

  late TextEditingController _sampleSizeController;
  late TextEditingController _collectionPointController;
  late TextEditingController _suspectedCauseManualController;

  final Map<String, TextEditingController> _lesionControllers = {};
  final List<_OtherLesionEntry> _otherLesions = [];

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
    _otherLesions.addAll(_decodeOtherLesions(widget.audit.pmOtherLesionsJson));
    if (_otherLesions.isEmpty) {
      _otherLesions.add(_OtherLesionEntry(name: 'Others'));
    }
  }

  @override
  void dispose() {
    _sampleSizeController.dispose();
    _collectionPointController.dispose();
    _suspectedCauseManualController.dispose();
    for (final c in _lesionControllers.values) {
      c.dispose();
    }
    for (final entry in _otherLesions) {
      entry.dispose();
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

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSampleMetadataCard(),
        const SizedBox(height: 16),
        _buildLesionCard(),
        const SizedBox(height: 16),
        _buildPhotosCard(),
        const SizedBox(height: 16),
        _buildSummaryCard(),
      ],
    );

    if (widget.embedded) return AuditNumericKeyboardScope(child: content);

    return AuditNumericKeyboardScope(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: content,
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
            AuditNumericField(
              controller: _sampleSizeController,
              enabled: !widget.isReadOnly,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Sample Size',
              ),
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
        'label': 'Air Sac Caseations',
        'field': 'pm_airSacCaseations',
        'count': widget.audit.pmAirSacCaseationsCount,
        'severity': widget.audit.pmAirSacCaseationsSeverity,
      },
      {
        'label': 'Urolithiasis (Urate Deposits)',
        'field': 'pm_urolithiasis',
        'count': widget.audit.pmUrolithiasisCount,
        'severity': widget.audit.pmUrolithiasisSeverity,
      },
      {
        'label': 'Nephritis',
        'field': 'pm_nephritis',
        'count': widget.audit.pmNephritisCount,
        'severity': widget.audit.pmNephritisSeverity,
      },
      {
        'label': 'General Septicemia',
        'field': 'pm_generalSepticemia',
        'count': widget.audit.pmGeneralSepticemiaCount,
        'severity': widget.audit.pmGeneralSepticemiaSeverity,
      },
      {
        'label': 'Gizzard Erosions',
        'field': 'pm_gizzardErosions',
        'count': widget.audit.pmGizzardErosionsCount,
        'severity': widget.audit.pmGizzardErosionsSeverity,
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
                Icon(
                  Icons.medical_services,
                  color: AppColors.primary,
                  size: 20,
                ),
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
                        Expanded(child: Text(label, style: AppTextStyles.body)),
                        SizedBox(
                          width: 80,
                          child: AuditNumericField(
                            controller: controller,
                            enabled: !widget.isReadOnly,
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
                                  child: Text(
                                    s,
                                    style: const TextStyle(fontSize: 12),
                                  ),
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
            const Divider(height: 20),
            _buildOtherLesionsHeader(),
            const SizedBox(height: 8),
            for (var i = 0; i < _otherLesions.length; i++)
              _buildOtherLesionRow(i),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherLesionsHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Others',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (!widget.isReadOnly)
          TextButton.icon(
            key: const ValueKey('pm-add-other-lesion'),
            onPressed: _addOtherLesion,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add other'),
          ),
      ],
    );
  }

  Widget _buildOtherLesionRow(int index) {
    final entry = _otherLesions[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('pm-other-lesion-name-$index'),
              controller: entry.nameController,
              enabled: !widget.isReadOnly,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Lesion name',
                isDense: true,
              ),
              onChanged: (_) => _syncOtherLesions(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: AuditNumericField(
              key: ValueKey('pm-other-lesion-count-$index'),
              controller: entry.countController,
              enabled: !widget.isReadOnly,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Count',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                isDense: true,
              ),
              onChanged: (_) => _syncOtherLesions(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: entry.severity,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Severity',
                contentPadding: EdgeInsets.symmetric(
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
              onChanged: widget.isReadOnly
                  ? null
                  : (value) {
                      setState(() => entry.severity = value);
                      _syncOtherLesions();
                    },
            ),
          ),
          if (!widget.isReadOnly && _otherLesions.length > 1) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Remove other lesion',
              onPressed: () => _removeOtherLesion(index),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
    );
  }

  List<_OtherLesionEntry> _decodeOtherLesions(String? source) {
    if (source == null || source.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);
        final name = (map['name'] as String? ?? '').trim();
        return _OtherLesionEntry(
          name: name.isEmpty ? 'Others' : name,
          count: _parseCount(map['count']),
          severity: map['severity'] as String?,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  int? _parseCount(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  void _addOtherLesion() {
    setState(() {
      _otherLesions.add(_OtherLesionEntry(name: 'Others'));
    });
    _syncOtherLesions();
  }

  void _removeOtherLesion(int index) {
    setState(() {
      _otherLesions.removeAt(index).dispose();
      if (_otherLesions.isEmpty) {
        _otherLesions.add(_OtherLesionEntry(name: 'Others'));
      }
    });
    _syncOtherLesions();
  }

  void _syncOtherLesions() {
    final entries = <Map<String, dynamic>>[];
    for (final entry in _otherLesions) {
      final name = entry.nameController.text.trim();
      final count = int.tryParse(entry.countController.text);
      final severity = entry.severity;
      final hasCustomName = name.isNotEmpty && name != 'Others';
      final hasCount = (count ?? 0) > 0;
      final hasSeverity = severity != null && severity.isNotEmpty;
      if (!hasCustomName && !hasCount && !hasSeverity) continue;
      final encodedEntry = <String, dynamic>{
        'name': name.isEmpty ? 'Others' : name,
      };
      if (count != null) {
        encodedEntry['count'] = count;
      }
      if (hasSeverity) {
        encodedEntry['severity'] = severity;
      }
      entries.add(encodedEntry);
    }

    widget.onFieldChanged(
      'pm_otherLesionsJson',
      entries.isEmpty ? null : jsonEncode(entries),
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
                fieldKey: 'pm_photo',
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
                    Text('Auto-Suggested Cause', style: AppTextStyles.caption),
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

class _OtherLesionEntry {
  final TextEditingController nameController;
  final TextEditingController countController;
  String? severity;

  _OtherLesionEntry({required String name, int? count, this.severity})
    : nameController = TextEditingController(text: name),
      countController = TextEditingController(
        text: (count ?? 0) > 0 ? count.toString() : '',
      );

  void dispose() {
    nameController.dispose();
    countController.dispose();
  }
}
