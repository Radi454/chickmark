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
  final List<String?> _defectErrors = List.filled(
    CalculationUtils.pasgarTrackedDefectCategoryCount,
    null,
  );

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

    for (
      var i = 0;
      i < CalculationUtils.pasgarTrackedDefectCategoryCount;
      i++
    ) {
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
    for (
      var i = 0;
      i < CalculationUtils.pasgarTrackedDefectCategoryCount;
      i++
    ) {
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
      defectCounts
          .take(CalculationUtils.pasgarScoredDefectCategoryCount)
          .toList(),
    );

    final content = widget.embedded
        ? _buildEmbeddedContent(pasgarScore)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _referenceCard(
                key: const ValueKey('pasgar-sample-size-card'),
                title: 'Sample Size',
                children: [_buildSampleSizeField()],
              ),
              const SizedBox(height: 64),
              _referenceCard(
                key: const ValueKey('pasgar-defect-counts-card'),
                title: 'Defect Counts',
                children: [
                  _buildDefectInput(0, 'Reflexes'),
                  const SizedBox(height: 18),
                  _buildDefectInput(1, 'Beak'),
                  const SizedBox(height: 18),
                  _buildDefectInput(2, 'Navel'),
                  const SizedBox(height: 18),
                  _buildDefectInput(3, 'Belly'),
                  const SizedBox(height: 18),
                  _buildDefectInput(4, 'Leg'),
                  const SizedBox(height: 18),
                  _buildDefectInput(5, 'Feather Dev'),
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
        children: [_cardTitle(title), const SizedBox(height: 24), ...children],
      ),
    );
  }

  Widget _buildEmbeddedContent(double pasgarScore) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEmbeddedSampleSizeRow(),
        const SizedBox(height: AppSizes.spaceSm),
        _buildEmbeddedDefectList(),
        const SizedBox(height: AppSizes.spaceSm),
        _buildScoreCard(pasgarScore),
      ],
    );
  }

  Widget _buildEmbeddedSampleSizeRow() {
    return Container(
      key: const ValueKey('pasgar-sample-size-card'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceMd,
        vertical: AppSizes.spaceSm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Number of chicks sampled',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: AppSizes.spaceMd),
          SizedBox(width: 92, child: _buildSampleSizeField(compactRow: true)),
        ],
      ),
    );
  }

  Widget _buildEmbeddedDefectList() {
    const rows = [
      (0, 'Reflexes'),
      (1, 'Beak'),
      (2, 'Navel'),
      (3, 'Belly'),
      (4, 'Leg'),
      (5, 'Feather Dev'),
    ];

    return Container(
      key: const ValueKey('pasgar-defect-counts-card'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.spaceMd,
                vertical: AppSizes.spaceSm,
              ),
              child: _buildDefectInput(rows[i].$1, rows[i].$2),
            ),
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.divider),
          ],
        ],
      ),
    );
  }

  Widget _cardTitle(String title) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.heading.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildSampleSizeField({bool compactRow = false}) {
    return AuditNumericField(
      controller: _sampleSizeController,
      enabled: !widget.isReadOnly,
      textAlign: compactRow ? TextAlign.center : TextAlign.start,
      decoration: compactRow
          ? _compactInputDecoration(_sampleSizeError)
          : _inputDecoration(
              label: 'Number of chicks sampled',
              errorText: _sampleSizeError,
            ),
      style: AppTextStyles.body.copyWith(
        fontSize: compactRow ? 18 : 24,
        fontWeight: FontWeight.w800,
      ),
      onChanged: (value) {
        setState(() {
          _validateSampleSize();
        });
        widget.onFieldChanged('pasgarSampleSize', int.tryParse(value) ?? 0);
        _persistScore();
      },
    );
  }

  InputDecoration _inputDecoration({required String label, String? errorText}) {
    final compact = widget.embedded;
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          compact ? AppSizes.inputRadius : 20,
        ),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          compact ? AppSizes.inputRadius : 20,
        ),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          compact ? AppSizes.inputRadius : 20,
        ),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      labelText: label,
      labelStyle: AppTextStyles.caption.copyWith(
        color: AppColors.primary,
        fontSize: compact ? 12 : 16,
        fontWeight: FontWeight.w800,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? AppSizes.spaceMd : 32,
        vertical: compact ? AppSizes.spaceMd : 26,
      ),
      errorText: errorText,
    );
  }

  Widget _buildScoreCard(double pasgarScore) {
    final scoreColor = pasgarScore >= 9.5
        ? AppColors.greenTab
        : pasgarScore >= 9.0
        ? Colors.orange
        : Colors.red;

    if (widget.embedded) {
      return Container(
        key: const ValueKey('pasgar-score-card'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceMd,
          vertical: AppSizes.spaceMd,
        ),
        decoration: BoxDecoration(
          color: AppColors.statusGoodBg,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(color: AppColors.statusGood.withAlpha(48)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'PASGAR Score',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${pasgarScore.toStringAsFixed(1)}/10',
              style: AppTextStyles.heading.copyWith(
                fontSize: 24,
                color: scoreColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('pasgar-score-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
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
    );
  }

  Widget _buildDefectInput(int index, String label) {
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

    final compact = widget.embedded;
    final controlGap = compact ? AppSizes.spaceXs : 12.0;
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _defectStepperButton(
          tooltip: 'Decrease $label',
          onPressed: canDecrease
              ? () => _setDefectCount(index, count - 1)
              : null,
          icon: Icons.remove_circle_outline,
          color: AppColors.textSecondary,
        ),
        SizedBox(width: controlGap),
        SizedBox(
          width: compact ? 52 : 110,
          child: AuditNumericField(
            controller: _controllers[index],
            enabled: !widget.isReadOnly,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              fontSize: compact ? 15 : 22,
              fontWeight: FontWeight.w700,
            ),
            decoration: _defectInputDecoration(
              _defectErrors[index],
              compact: compact,
            ),
            onChanged: (value) {
              _updateDefectCount(index, value);
            },
          ),
        ),
        SizedBox(width: compact ? AppSizes.spaceXs : 0),
        _defectStepperButton(
          tooltip: 'Increase $label',
          onPressed: canIncrease
              ? () => _setDefectCount(index, count + 1)
              : null,
          icon: Icons.add_circle_outline,
          color: AppColors.textPrimary,
        ),
        SizedBox(width: compact ? AppSizes.spaceSm : 0),
        PhotoButton(
          photoPath: widget.audit.toMap()[photoFields[index]] as String?,
          enabled: !widget.isReadOnly,
          size: compact ? 36 : 56,
          onPhotoCaptured: (path) =>
              widget.onFieldChanged(photoFields[index], path),
        ),
      ],
    );

    Widget labelBlock({required bool stacked}) {
      final labelFontSize = compact ? (stacked ? 15.0 : 16.0) : 24.0;
      final percentFontSize = compact ? 12.0 : 16.0;
      return Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                fontSize: labelFontSize,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _defectPercent(index),
            style: AppTextStyles.caption.copyWith(
              color: isAlert ? AppColors.statusError : AppColors.textSecondary,
              fontSize: percentFontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isAlert) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.warning_amber,
              color: AppColors.statusError,
              size: 18,
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout = compact && constraints.maxWidth < 380;
        if (compactLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              labelBlock(stacked: true),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: controls,
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: labelBlock(stacked: false)),
            const SizedBox(width: 10),
            controls,
          ],
        );
      },
    );
  }

  Widget _defectStepperButton({
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
    required Color color,
  }) {
    final compact = widget.embedded;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: compact ? 24 : 36),
      color: color,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 28 : 48,
        height: compact ? 32 : 48,
      ),
    );
  }

  InputDecoration _defectInputDecoration(
    String? errorText, {
    bool compact = false,
  }) {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          compact ? AppSizes.inputRadius : 16,
        ),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          compact ? AppSizes.inputRadius : 16,
        ),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          compact ? AppSizes.inputRadius : 16,
        ),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? AppSizes.spaceSm : 12,
        vertical: compact ? 10 : 20,
      ),
      errorText: errorText,
    );
  }

  InputDecoration _compactInputDecoration(String? errorText) {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.inputRadius),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.inputRadius),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.inputRadius),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceSm,
      ),
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
        .take(CalculationUtils.pasgarScoredDefectCategoryCount)
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
    return '${(CalculationUtils.percentOf(count, sampleSize) ?? 0.0).toStringAsFixed(1)}%';
  }

  bool _isDefectAlert(int index) {
    final sampleSize = _sampleSize;
    if (sampleSize <= 0) return false;
    final count = int.tryParse(_controllers[index].text) ?? 0;
    return (CalculationUtils.percentOf(count, sampleSize) ?? 0.0) > 20;
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
