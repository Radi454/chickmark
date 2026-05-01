import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/calculation_utils.dart';
import '../../../../core/utils/field_validators.dart';
import '../../../../data/models/audit_model.dart';
import '../audit_numeric_keyboard.dart';
import '../photo_button.dart';

class PasgarTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final bool embedded;

  const PasgarTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    this.embedded = false,
  });

  @override
  State<PasgarTab> createState() => _PasgarTabState();
}

class _PasgarTabState extends State<PasgarTab> {
  final List<TextEditingController> _controllers = [];
  final TextEditingController _sampleSizeController = TextEditingController();
  String? _sampleSizeError;
  final List<String?> _defectErrors = List.filled(6, null);

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _sampleSizeController.text =
        widget.audit.pasgarSampleSize?.toString() ?? '40';

    final defectCounts = [
      widget.audit.pasgarReflexes ?? 0,
      widget.audit.pasgarBeak ?? 0,
      widget.audit.pasgarNavel ?? 0,
      widget.audit.pasgarBelly ?? 0,
      widget.audit.pasgarLeg ?? 0,
      widget.audit.pasgarFeatherDev ?? 0,
    ];

    for (var i = 0; i < 6; i++) {
      _controllers.add(TextEditingController(text: defectCounts[i].toString()));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.isReadOnly && widget.audit.pasgarSampleSize == null) {
        widget.onFieldChanged('pasgarSampleSize', 40);
        _persistScore();
      }
    });
  }

  int get _sampleSize => int.tryParse(_sampleSizeController.text) ?? 0;

  void _validateSampleSize() {
    _sampleSizeError = FieldValidators.sampleSize(_sampleSizeController.text);
    for (var i = 0; i < 6; i++) {
      _defectErrors[i] = FieldValidators.pasgarCount(
        _controllers[i].text,
        sampleSize: _sampleSize,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sampleSize = _sampleSize;
    final defectCounts = _controllers
        .map((c) => int.tryParse(c.text) ?? 0)
        .toList();

    final pasgarScore = CalculationUtils.pasgarScore(
      sampleSize,
      defectCounts.take(5).toList(),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _referenceCard(
          key: const ValueKey('pasgar-sample-size-card'),
          title: 'Sample Size',
          icon: Icons.numbers,
          children: [
            AuditNumericField(
              controller: _sampleSizeController,
              enabled: !widget.isReadOnly,
              decoration: _inputDecoration(
                label: 'Number of chicks sampled',
                errorText: _sampleSizeError,
              ),
              style: AppTextStyles.body.copyWith(fontSize: 24),
              onChanged: (value) {
                setState(() {
                  _validateSampleSize();
                });
                widget.onFieldChanged(
                  'pasgarSampleSize',
                  int.tryParse(value) ?? 0,
                );
                _persistScore();
              },
            ),
          ],
        ),
        SizedBox(height: widget.embedded ? 16 : 64),
        _referenceCard(
          key: const ValueKey('pasgar-defect-counts-card'),
          title: 'Defect Counts',
          icon: Icons.warning,
          children: [
            _buildDefectInput(0, 'Reflexes', Icons.accessibility_new),
            const SizedBox(height: 18),
            _buildDefectInput(1, 'Beak', Icons.pets),
            const SizedBox(height: 18),
            _buildDefectInput(2, 'Navel', Icons.healing),
            const SizedBox(height: 18),
            _buildDefectInput(3, 'Belly', Icons.circle_outlined),
            const SizedBox(height: 18),
            _buildDefectInput(4, 'Leg', Icons.directions_walk),
            const SizedBox(height: 18),
            _buildDefectInput(5, 'Feather Dev', Icons.air),
          ],
        ),
        const SizedBox(height: 24),
        _buildScoreCard(pasgarScore),
      ],
    );

    if (widget.embedded) return AuditNumericKeyboardScope(child: content);

    return AuditNumericKeyboardScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 700
              ? 48.0
              : AppSizes.cardPadding;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              48,
              horizontalPadding,
              120,
            ),
            child: content,
          );
        },
      ),
    );
  }

  Widget _referenceCard({
    required Key key,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(title, icon),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _cardTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 32),
        const SizedBox(width: 20),
        Text(
          title,
          style: AppTextStyles.heading.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({required String label, String? errorText}) {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      labelText: label,
      labelStyle: AppTextStyles.caption.copyWith(
        color: AppColors.primary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
      errorText: errorText,
    );
  }

  Widget _buildScoreCard(double pasgarScore) {
    final scoreColor = pasgarScore >= 9.5
        ? AppColors.greenTab
        : pasgarScore >= 9.0
        ? Colors.orange
        : Colors.red;

    return Container(
      key: const ValueKey('pasgar-score-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PASGAR Score',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${pasgarScore.toStringAsFixed(1)}/10',
                style: AppTextStyles.heading.copyWith(
                  fontSize: 32,
                  color: scoreColor,
                ),
              ),
            ],
          ),
          Icon(Icons.assessment, size: 48, color: scoreColor),
        ],
      ),
    );
  }

  Widget _buildDefectInput(int index, String label, IconData icon) {
    final sampleSize = _sampleSize;
    final count = int.tryParse(_controllers[index].text) ?? 0;
    final canDecrease = !widget.isReadOnly && count > 0;
    final canIncrease =
        !widget.isReadOnly && (sampleSize <= 0 || count < sampleSize);
    final photoFields = [
      'pasgarReflexesPhoto',
      'pasgarBeakPhoto',
      'pasgarNavelPhoto',
      'pasgarBellyPhoto',
      'pasgarLegPhoto',
      'pasgarFeatherDevPhoto',
    ];
    final isAlert = _isDefectAlert(index);

    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 30),
        const SizedBox(width: 22),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.body.copyWith(fontSize: 24, height: 1.2),
              ),
              Text(
                _defectPercent(index),
                style: AppTextStyles.caption.copyWith(
                  color: isAlert ? Colors.red : Colors.grey,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        if (isAlert)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.warning_amber, color: Colors.red, size: 20),
          ),
        IconButton(
          tooltip: 'Decrease $label',
          onPressed: canDecrease
              ? () => _setDefectCount(index, count - 1)
              : null,
          icon: const Icon(Icons.remove_circle_outline, size: 36),
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: AuditNumericField(
            controller: _controllers[index],
            enabled: !widget.isReadOnly,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(fontSize: 22),
            decoration: _defectInputDecoration(_defectErrors[index]),
            onChanged: (value) {
              _updateDefectCount(index, value);
            },
          ),
        ),
        IconButton(
          tooltip: 'Increase $label',
          onPressed: canIncrease
              ? () => _setDefectCount(index, count + 1)
              : null,
          icon: const Icon(Icons.add_circle_outline, size: 36),
          color: AppColors.textPrimary,
        ),
        PhotoButton(
          photoPath: widget.audit.toMap()[photoFields[index]] as String?,
          enabled: !widget.isReadOnly,
          size: 56,
          onPhotoCaptured: (path) =>
              widget.onFieldChanged(photoFields[index], path),
        ),
      ],
    );
  }

  InputDecoration _defectInputDecoration(String? errorText) {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      errorText: errorText,
    );
  }

  void _updateDefectCount(int index, String value) {
    final sampleSize = _sampleSize;
    final parsed = int.tryParse(value) ?? 0;
    final count = sampleSize > 0 ? parsed.clamp(0, sampleSize).toInt() : parsed;
    final fieldNames = [
      'pasgarReflexes',
      'pasgarBeak',
      'pasgarNavel',
      'pasgarBelly',
      'pasgarLeg',
      'pasgarFeatherDev',
    ];
    if (_controllers[index].text != count.toString()) {
      _controllers[index].text = count.toString();
      _controllers[index].selection = TextSelection.collapsed(
        offset: _controllers[index].text.length,
      );
    }
    setState(() {
      _defectErrors[index] = FieldValidators.pasgarCount(
        count.toString(),
        sampleSize: sampleSize,
      );
    });
    widget.onFieldChanged(fieldNames[index], count);
    _persistScore();
  }

  void _setDefectCount(int index, int count) {
    _controllers[index].text = count.toString();
    _updateDefectCount(index, count.toString());
  }

  void _persistScore() {
    final sampleSize = _sampleSize;
    final scoredDefects = _controllers
        .take(5)
        .map((c) => int.tryParse(c.text) ?? 0)
        .toList();
    widget.onFieldChanged(
      'pasgarFinalScore',
      CalculationUtils.pasgarScore(sampleSize, scoredDefects),
    );
  }

  String _defectPercent(int index) {
    final sampleSize = _sampleSize;
    if (sampleSize <= 0) return '0.0%';
    final count = int.tryParse(_controllers[index].text) ?? 0;
    return '${((count / sampleSize) * 100).toStringAsFixed(1)}%';
  }

  bool _isDefectAlert(int index) {
    final sampleSize = _sampleSize;
    if (sampleSize <= 0) return false;
    final count = int.tryParse(_controllers[index].text) ?? 0;
    return (count / sampleSize) * 100 > 20;
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    _sampleSizeController.dispose();
    super.dispose();
  }
}
