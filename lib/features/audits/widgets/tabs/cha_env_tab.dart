import 'package:flutter/material.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/audit_model.dart';
import '../govee_sector.dart';
import '../photo_button.dart';

class ChaEnvTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final VoidCallback onSave;

  const ChaEnvTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    required this.onSave,
  });

  @override
  State<ChaEnvTab> createState() => _ChaEnvTabState();
}

class _ChaEnvTabState extends State<ChaEnvTab> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GoveeSector(isAvailable: false, isConnected: false, onScanTap: () {}),
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
                  Text(
                    'Environmental Readings',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNumericField(
                    'CO2 (ppm)',
                    'chaCo2',
                    widget.audit.chaCo2,
                    'chaCo2Photo',
                  ),
                  const SizedBox(height: 12),
                  _buildNumericField(
                    'PM10 (µg/m³)',
                    'chaPm10',
                    widget.audit.chaPm10,
                    'chaPm10Photo',
                  ),
                  const SizedBox(height: 12),
                  _buildNumericField(
                    'PM2.5 (µg/m³)',
                    'chaPm25',
                    widget.audit.chaPm25,
                    'chaPm25Photo',
                  ),
                  const SizedBox(height: 12),
                  _buildNumericField(
                    'Air Velocity (m/s)',
                    'chaAirVelocitySpot1',
                    widget.audit.chaAirVelocitySpot1,
                    'chaAirVelocitySpot1Photo',
                  ),
                  const SizedBox(height: 12),
                  _buildNumericField(
                    'Air Inlet (°F)',
                    'chaAirInlet',
                    widget.audit.chaAirInlet,
                    'chaAirInletPhoto',
                  ),
                  const SizedBox(height: 12),
                  _buildNumericField(
                    'Air Outlet (°F)',
                    'chaAirOutlet',
                    widget.audit.chaAirOutlet,
                    'chaAirOutletPhoto',
                  ),
                  const SizedBox(height: 12),
                  _buildNumericField(
                    'Noise Level (dB)',
                    'chaNoiseLevel',
                    widget.audit.chaNoiseLevel,
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

  Widget _buildNumericField(
    String label,
    String fieldKey,
    double? value,
    String photoField,
  ) {
    final controller = TextEditingController(text: value?.toString() ?? '');
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
}
