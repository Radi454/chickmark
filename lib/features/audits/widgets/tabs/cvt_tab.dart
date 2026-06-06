import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_thresholds.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/calculation_utils.dart';
import '../../../../core/utils/temp_converter.dart';
import '../../../../data/models/audit_model.dart';
import '../../../../data/models/photo_model.dart';
import '../../../../data/repositories/photo_repository.dart';
import '../../../../providers/app_provider.dart';
import '../../../../services/ocr/ocr_service.dart';
import '../../../../services/photo/photo_service.dart';
import '../../models/est_grid_data.dart';
import '../../ocr_capture/ocr_capture_config.dart';
import '../../ocr_capture/ocr_capture_launcher.dart';
import '../../providers/audit_provider.dart';
import '../audit_numeric_keyboard.dart';
import '../est_grid_widget.dart';

class CvtTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final bool embedded;

  const CvtTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    this.embedded = false,
  });

  @override
  State<CvtTab> createState() => _CvtTabState();
}

class _CvtTabState extends State<CvtTab> {
  final Map<String, TextEditingController> _controllers = {
    for (final key in EstGridData.scanKeys) key: TextEditingController(),
  };
  final Map<String, FocusNode> _focusNodes = {
    for (final key in EstGridData.scanKeys) key: FocusNode(),
  };
  final Map<String, String?> _photos = {
    for (final key in EstGridData.scanKeys) key: null,
  };
  final OcrService _ocrService = OcrService();
  final PhotoService _photoService = PhotoService();
  final PhotoRepository _photoRepository = PhotoRepository();

  @override
  void initState() {
    super.initState();
    _loadReadings(widget.audit);
    _loadPhotos(widget.audit);
    _updateCalculations(notify: false);
  }

  @override
  void didUpdateWidget(covariant CvtTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audit.id != widget.audit.id) {
      _clearGrid();
      _loadReadings(widget.audit);
      _loadPhotos(widget.audit);
      _updateCalculations(notify: false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    unawaited(_ocrService.dispose());
    super.dispose();
  }

  void _clearGrid() {
    for (final controller in _controllers.values) {
      controller.clear();
    }
    for (final key in _photos.keys.toList()) {
      _photos[key] = null;
    }
  }

  void _loadReadings(AuditModel audit) {
    final decoded = _decodeReadings(audit.cvtReadingsJson);
    if (decoded.isEmpty) {
      _loadLegacyReadings(audit);
      return;
    }
    for (final entry in decoded.entries) {
      _controllers[entry.key]?.text = _formatForEntryUnit(entry.value);
    }
  }

  void _loadLegacyReadings(AuditModel audit) {
    final legacy = <String, double?>{
      'front_top': audit.cvtTopTemp,
      'middle_middle': audit.cvtMiddleTemp,
      'back_bottom': audit.cvtBottomTemp,
    };
    for (final entry in legacy.entries) {
      final value = entry.value;
      if (value != null) {
        _controllers[entry.key]?.text = _formatForEntryUnit(value);
      }
    }
  }

  void _loadPhotos(AuditModel audit) {
    final decoded = _decodePhotos(audit.cvtPhotosJson);
    if (decoded.isEmpty) {
      _photos['front_top'] = audit.cvtTopPhoto;
      _photos['middle_middle'] = audit.cvtMiddlePhoto;
      _photos['back_bottom'] = audit.cvtBottomPhoto;
      return;
    }
    for (final entry in decoded.entries) {
      if (_photos.containsKey(entry.key)) {
        _photos[entry.key] = entry.value;
      }
    }
  }

  Map<String, double> _decodeReadings(String? json) {
    if (json == null || json.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return {};
      return EstGridData.normalizeReadings(decoded);
    } catch (_) {
      return {};
    }
  }

  Map<String, String> _decodePhotos(String? json) {
    if (json == null || json.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is String &&
              (entry.value as String).trim().isNotEmpty)
            entry.key.toString(): entry.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  String _formatForEntryUnit(double valueF) => valueF.toStringAsFixed(1);

  double? _controllerValueF(String key) {
    final parsed = double.tryParse(_controllers[key]?.text.trim() ?? '');
    if (parsed == null) return null;
    return parsed;
  }

  Map<String, double> _currentReadingsF() {
    final readings = <String, double>{};
    for (final key in EstGridData.scanKeys) {
      final value = _controllerValueF(key);
      if (value != null) readings[key] = double.parse(value.toStringAsFixed(1));
    }
    return readings;
  }

  Map<String, String> _currentPhotoPaths() {
    final photos = <String, String>{};
    for (final entry in _photos.entries) {
      final path = entry.value;
      if (path != null && path.trim().isNotEmpty) {
        photos[entry.key] = path;
      }
    }
    return photos;
  }

  void _updateCalculations({bool notify = true}) {
    final readings = _currentReadingsF();
    final temps = readings.values.toList();
    final photos = _currentPhotoPaths();
    final avg = temps.isEmpty ? null : CalculationUtils.average(temps);
    final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;

    void update(String key, Object? value) {
      if (notify) widget.onFieldChanged(key, value);
    }

    update('cvtReadingsJson', readings.isEmpty ? null : jsonEncode(readings));
    update('cvtPhotosJson', photos.isEmpty ? null : jsonEncode(photos));
    update('cvtAvg', avg);
    update('cvtCvPct', temps.isEmpty ? null : cv);
    update('cvtSampleSize', temps.isEmpty ? null : temps.length);

    final representative = _representativeLegacyValues(readings);
    update('cvtTopTemp', representative['top']);
    update('cvtMiddleTemp', representative['middle']);
    update('cvtBottomTemp', representative['bottom']);
    update('cvtTopBasket', representative['top'] == null ? null : 'Front Top');
    update(
      'cvtMiddleBasket',
      representative['middle'] == null ? null : 'Middle Middle',
    );
    update(
      'cvtBottomBasket',
      representative['bottom'] == null ? null : 'Back Bottom',
    );
  }

  Map<String, double?> _representativeLegacyValues(
    Map<String, double> readings,
  ) {
    double? firstForLevel(String level) {
      for (final location in EstGridData.locations) {
        final value = readings[EstGridData.key(location, level)];
        if (value != null) return value;
      }
      return null;
    }

    return {
      'top': readings['front_top'] ?? firstForLevel('top'),
      'middle': readings['middle_middle'] ?? firstForLevel('middle'),
      'bottom': readings['back_bottom'] ?? firstForLevel('bottom'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final readings = _currentReadingsF();
    final temps = readings.values.toList();
    final avg = temps.isEmpty ? null : CalculationUtils.average(temps);
    final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;
    final showCelsius =
        context.watch<AppProvider>().tempUnit == TempUnit.celsius;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'AVG Temp',
                avg == null
                    ? '--'
                    : showCelsius
                    ? TempConverter.display(avg, showCelsius: true)
                    : '${avg.toStringAsFixed(1)}°F',
                avg == null
                    ? null
                    : avg >= AppThresholds.cvtMin &&
                          avg <= AppThresholds.cvtMax,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                'CV %',
                temps.isEmpty ? '--' : '${cv.toStringAsFixed(1)}%',
                temps.isEmpty ? null : cv <= AppThresholds.cvAlertPct,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGridHeader(),
                const SizedBox(height: 12),
                EstGridWidget(
                  key: const ValueKey('cvt-temperature-grid'),
                  controllers: _controllers,
                  focusNodes: _focusNodes,
                  photos: _photos,
                  enabled: !widget.isReadOnly,
                  showPhotoCapture: false,
                  unitSuffix: '°F',
                  tempStatusFn: CalculationUtils.cvtStatus,
                  tempZoneFn: CalculationUtils.cvtZone,
                  onValueChanged: (_, _) {
                    _updateCalculations();
                    setState(() {});
                  },
                  onPhotoCaptured: (key, path) {
                    unawaited(_handlePhotoCaptured(key, path));
                  },
                  onMissingPhotoRequested: (key) {
                    unawaited(_attachMissingPhoto(key));
                  },
                  onClearRequested: (key) {
                    unawaited(_clearPoint(key));
                  },
                ),
              ],
            ),
          ),
        ),
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

  Widget _buildGridHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CVT Grid',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '103-105°F / 39.4-40.6°C',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.greenTab,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: widget.isReadOnly ? null : _openCapture,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan readings'),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, bool? isGood) {
    final color = isGood == null
        ? Colors.blueGrey
        : isGood
        ? AppColors.greenTab
        : Colors.red;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.heading.copyWith(fontSize: 24, color: color),
          ),
        ],
      ),
    );
  }

  /// Launch the reusable full-screen OCR capture flow (CVT, °F), pre-populated
  /// with the current grid, then merge confirmed readings via [_savePoint]
  /// (+ evidence photo records). Persistence + sync unchanged.
  Future<void> _openCapture() async {
    if (widget.isReadOnly) return;
    final result = await OcrCaptureLauncher.push(
      context,
      OcrCaptureConfig(
        title: 'Chick Vent Temperature',
        unitSuffix: '°F',
        convertCelsiusToFahrenheit: true,
        initialReadings: _currentReadingsF(),
        initialPhotos: _currentPhotoPaths(),
        tempStatusFn: CalculationUtils.cvtStatus,
        tempZoneFn: CalculationUtils.cvtZone,
        targetLabelBuilder: _targetLabel,
        readOnly: widget.isReadOnly,
      ),
      ocrService: _ocrService,
      photoService: _photoService,
    );
    if (result == null || result.isEmpty || !mounted) return;
    final draftId = context.read<AuditProvider>().activeDraft.id;
    OcrCaptureLauncher.apply(result, (key, path, value) {
      _savePoint(key, path, value);
      if (path.isNotEmpty) unawaited(_saveEvidencePhotoRecord(draftId, path));
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${result.readings.length} CVT readings.')),
    );
  }

  void _savePoint(String key, String path, double displayValue) {
    setState(() {
      _photos[key] = path;
      _controllers[key]?.text = displayValue.toStringAsFixed(1);
    });
    _updateCalculations();
  }

  Future<void> _handlePhotoCaptured(String key, String path) async {
    final existingValue = _controllerValueF(key);
    final existingPhoto = _photos[key];
    if (existingValue != null &&
        (existingPhoto == null || existingPhoto.trim().isEmpty)) {
      setState(() {
        _photos[key] = path;
      });
      _updateCalculations();
      await _saveEvidencePhotoRecord(
        context.read<AuditProvider>().activeDraft.id,
        path,
      );
      return;
    }

    final readingC = await _ocrService.recognizeThermoScanReadingCelsius(path);
    if (!mounted) return;
    final valueController = TextEditingController(
      text: readingC == null
          ? ''
          : TempConverter.toFahrenheit(readingC).toStringAsFixed(1),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_targetLabel(key)),
        content: AuditNumericKeyboardScope(
          child: AuditNumericField(
            controller: valueController,
            allowDecimal: true,
            maxDecimalPlaces: 1,
            decoration: InputDecoration(
              labelText: 'Temperature',
              suffixText: '°F',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(valueController.text);
    valueController.dispose();
    if (!mounted || confirmed != true || parsed == null) return;
    _savePoint(key, path, parsed);
    await _saveEvidencePhotoRecord(
      context.read<AuditProvider>().activeDraft.id,
      path,
    );
  }

  Future<void> _attachMissingPhoto(String key) async {
    if (widget.isReadOnly || _controllerValueF(key) == null) return;
    final path = await _photoService.pickPhoto(fromCamera: true);
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() {
      _photos[key] = path;
    });
    _updateCalculations();
    await _saveEvidencePhotoRecord(
      context.read<AuditProvider>().activeDraft.id,
      path,
    );
  }

  Future<void> _clearPoint(String key) async {
    if (widget.isReadOnly) return;
    final controller = _controllers[key];
    if (controller == null) return;
    final previousValue = controller.text;
    final previousPhoto = _photos[key];
    if (previousValue.trim().isEmpty &&
        (previousPhoto == null || previousPhoto.trim().isEmpty)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this reading and photo?'),
        content: Text(_targetLabel(key)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      controller.clear();
      _photos[key] = null;
    });
    _updateCalculations();
  }

  Future<void> _saveEvidencePhotoRecord(String draftId, String path) async {
    final sessionId = widget.audit.sessionId;
    if (draftId.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty ||
        path.trim().isEmpty) {
      return;
    }
    final existing = await _photoRepository.getByFilePath(path);
    final photo = PhotoModel(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      filePath: path,
      description: 'cvt',
      createdAt: existing?.createdAt ?? DateTime.now(),
      sessionId: sessionId,
      panelName: 'chick_quality',
      panelRowId: '$sessionId:chick_quality:$draftId',
      fieldKey: 'cvt',
      uploadStatus: existing?.uploadStatus ?? 'local',
    );
    await _photoRepository.saveLocalPhoto(photo);
  }

  String _targetLabel(String key) {
    final parts = key.split('_');
    if (parts.length != 2) return key;
    return '${EstGridData.label(parts[0])} - ${EstGridData.label(parts[1])}';
  }
}
