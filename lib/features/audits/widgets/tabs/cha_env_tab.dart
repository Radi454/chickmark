import 'package:flutter/material.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/field_validators.dart';
import '../../../../data/models/audit_model.dart';
import '../photo_button.dart';

class ChaEnvTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final String auditSessionId;
  final Function(String key, dynamic value) onFieldChanged;

  const ChaEnvTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.auditSessionId,
    required this.onFieldChanged,
  });

  @override
  State<ChaEnvTab> createState() => _ChaEnvTabState();
}

class _ChaEnvTabState extends State<ChaEnvTab> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    _initController('chaCo2', widget.audit.chaCo2);
    _initController('chaPm10', widget.audit.chaPm10);
    _initController('chaPm25', widget.audit.chaPm25);
    _initController('chaAirVelocitySpot1', widget.audit.chaAirVelocitySpot1);
    _initController('chaAirVelocitySpot2', widget.audit.chaAirVelocitySpot2);
    _initController('chaAirVelocitySpot3', widget.audit.chaAirVelocitySpot3);
    _initController('chaAirInlet', widget.audit.chaAirInlet);
    _initController('chaAirOutlet', widget.audit.chaAirOutlet);
    _initController('chaNoiseLevel', widget.audit.chaNoiseLevel);
  }

  void _initController(String key, double? value) {
    _controllers[key] = TextEditingController(text: value?.toString() ?? '');
    _errors[key] = null;
  }

  String? _validator(String key, String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    switch (key) {
      case 'chaCo2':
        return FieldValidators.co2(v);
      case 'chaAirVelocitySpot1':
      case 'chaAirVelocitySpot2':
      case 'chaAirVelocitySpot3':
        return FieldValidators.airVelocity(v);
      case 'chaAirInlet':
      case 'chaAirOutlet':
        return FieldValidators.temperature(v, isFahrenheit: true);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  Text(
                    'Environmental Readings',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildValidatedField('CO2 (ppm)', 'chaCo2', 'chaCo2Photo'),
                  const SizedBox(height: 12),
                  _buildNumericField('PM10 (µg/m³)', 'chaPm10', 'chaPm10Photo'),
                  const SizedBox(height: 12),
                  _buildNumericField(
                    'PM2.5 (µg/m³)',
                    'chaPm25',
                    'chaPm25Photo',
                  ),
                  const SizedBox(height: 12),
                  _buildValidatedField(
                    'Air Velocity Spot 1 (m/s)',
                    'chaAirVelocitySpot1',
                    'chaAirVelocitySpot1Photo',
                  ),
                  const SizedBox(height: 12),
                  _buildValidatedField(
                    'Air Velocity Spot 2 (m/s)',
                    'chaAirVelocitySpot2',
                    'chaAirVelocitySpot2Photo',
                  ),
                  const SizedBox(height: 12),
                  _buildValidatedField(
                    'Air Velocity Spot 3 (m/s)',
                    'chaAirVelocitySpot3',
                    'chaAirVelocitySpot3Photo',
                  ),
                  const SizedBox(height: 12),
                  _buildValidatedField(
                    'Air Inlet (°F)',
                    'chaAirInlet',
                    'chaAirInletPhoto',
                  ),
                  const SizedBox(height: 12),
                  _buildValidatedField(
                    'Air Outlet (°F)',
                    'chaAirOutlet',
                    'chaAirOutletPhoto',
                  ),
                  const SizedBox(height: 12),
                  _buildNumericField(
                    'Noise Level (dB)',
                    'chaNoiseLevel',
                    'chaNoiseLevelPhoto',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidatedField(
    String label,
    String fieldKey,
    String photoField,
  ) {
    final controller = _controllers[fieldKey]!;
    final error = _errors[fieldKey];
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !widget.isReadOnly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: label,
              errorText: error,
            ),
            onChanged: (v) {
              setState(() {
                _errors[fieldKey] = _validator(fieldKey, v);
              });
              widget.onFieldChanged(fieldKey, double.tryParse(v));
            },
          ),
        ),
        const SizedBox(width: 8),
        PhotoButton(
          photoPath: widget.audit.toMap()[photoField],
          enabled: !widget.isReadOnly,
          onPhotoCaptured: (path) => widget.onFieldChanged(photoField, path),
        ),
      ],
    );
  }

  Widget _buildNumericField(String label, String fieldKey, String photoField) {
    final controller = _controllers[fieldKey]!;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !widget.isReadOnly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: label,
            ),
            onChanged: (v) =>
                widget.onFieldChanged(fieldKey, double.tryParse(v)),
          ),
        ),
        const SizedBox(width: 8),
        PhotoButton(
          photoPath: widget.audit.toMap()[photoField],
          enabled: !widget.isReadOnly,
          onPhotoCaptured: (path) => widget.onFieldChanged(photoField, path),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
