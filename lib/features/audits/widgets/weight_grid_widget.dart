import 'package:hatchaudit/localized_material.dart';

import 'audit_numeric_keyboard.dart';

enum WeightsMode { chick, egg }

class WeightGridWidget extends StatefulWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final bool enabled;
  final WeightsMode mode;
  final VoidCallback? onChanged;

  const WeightGridWidget({
    super.key,
    required this.controllers,
    required this.focusNodes,
    required this.enabled,
    this.mode = WeightsMode.chick,
    this.onChanged,
  });

  @override
  State<WeightGridWidget> createState() => _WeightGridWidgetState();
}

class _WeightGridWidgetState extends State<WeightGridWidget> {
  static const int _eggColumns = 4;
  static const double _eggSpacing = 8;
  static const String _navigationGroup = 'weight-grid';

  bool _changeScheduled = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isEggMode = widget.mode == WeightsMode.egg;
        final crossAxisCount = isEggMode
            ? _eggColumnCountForWidth(constraints.maxWidth)
            : 4;
        final childAspectRatio = isEggMode
            ? _eggAspectRatioForWidth(constraints.maxWidth)
            : 1.0;

        final grid = GridView.builder(
          itemCount: widget.controllers.length,
          shrinkWrap: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: isEggMode ? _eggSpacing : 8,
            crossAxisSpacing: isEggMode ? _eggSpacing : 8,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, index) =>
              _buildWeightCell(index, crossAxisCount),
        );

        return AuditNumericKeyboardScope(child: grid);
      },
    );
  }

  Widget _buildWeightCell(int index, int crossAxisCount) {
    final cellNumber = index + 1;
    final hasValue = widget.controllers[index].text.trim().isNotEmpty;

    if (widget.mode == WeightsMode.egg) {
      return _buildEggWeightCell(index, cellNumber, hasValue, crossAxisCount);
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: hasValue ? const Color(0xFFFFF7F0) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasValue ? const Color(0xFFF65C00) : Colors.grey[300]!,
          width: hasValue ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: hasValue ? const Color(0xFFFFE5D2) : Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$cellNumber',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: hasValue ? const Color(0xFFF65C00) : Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: AuditNumericField(
              controller: widget.controllers[index],
              focusNode: widget.focusNodes[index],
              enabled: widget.enabled,
              allowDecimal: true,
              maxDecimalPlaces: 1,
              navigationGroup: _navigationGroup,
              navigationRow: index ~/ crossAxisCount,
              navigationColumn: index % crossAxisCount,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: widget.enabled ? Colors.black : Colors.grey[600],
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(4, 3, 4, 2),
                isDense: true,
              ),
              onChanged: (_) {
                _scheduleChanged();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEggWeightCell(
    int index,
    int cellNumber,
    bool hasValue,
    int crossAxisCount,
  ) {
    const borderColor = Color(0xFFE2E8F0);
    const focusedBorderColor = Color(0xFFCBD5E1);
    const radius = BorderRadius.all(Radius.circular(14));
    const border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: borderColor, width: 1.2),
    );

    return SizedBox.expand(
      child: AuditNumericField(
        controller: widget.controllers[index],
        focusNode: widget.focusNodes[index],
        enabled: widget.enabled,
        allowDecimal: true,
        maxDecimalPlaces: 1,
        navigationGroup: _navigationGroup,
        navigationRow: index ~/ crossAxisCount,
        navigationColumn: index % crossAxisCount,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: widget.enabled
              ? const Color(0xFF111827)
              : const Color(0xFF9AA3B2),
        ),
        decoration: InputDecoration(
          hintText: '$cellNumber',
          hintStyle: TextStyle(
            color: hasValue ? Colors.transparent : const Color(0xFF9AA3B2),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.white,
          border: border,
          enabledBorder: border,
          disabledBorder: border,
          focusedBorder: const OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: focusedBorderColor, width: 1.4),
          ),
          contentPadding: EdgeInsets.zero,
          isDense: true,
          counterText: '',
        ),
        onChanged: (_) => _scheduleChanged(),
      ),
    );
  }

  int _eggColumnCountForWidth(double width) {
    if (!width.isFinite) return _eggColumns;
    if (width >= 980) return 8;
    if (width >= 700) return 6;
    if (width >= 520) return 5;
    return _eggColumns;
  }

  double _eggAspectRatioForWidth(double width) {
    if (!width.isFinite) return 2.9;
    if (width >= 700) return 3.25;
    if (width >= 520) return 3.0;
    return 2.65;
  }

  void _scheduleChanged() {
    if (_changeScheduled) return;
    _changeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _changeScheduled = false;
      setState(() {});
      widget.onChanged?.call();
    });
  }

  @override
  void dispose() {
    // Don't dispose controllers and focusNodes here as they're managed by the parent
    super.dispose();
  }
}
