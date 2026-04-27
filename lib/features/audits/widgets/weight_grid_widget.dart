import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const int _eggColumns = 25;
  static const double _eggCellWidth = 48;
  static const double _eggSpacing = 4;

  bool _changeScheduled = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        final isEggMode = widget.mode == WeightsMode.egg;
        final crossAxisCount = isEggMode ? _eggColumns : 4;
        final childAspectRatio = isEggMode ? 1.15 : 1.0;

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
          itemBuilder: (context, index) => _buildWeightCell(index),
        );

        if (!isEggMode) return grid;

        final gridWidth =
            (_eggColumns * _eggCellWidth) + ((_eggColumns - 1) * _eggSpacing);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: SizedBox(width: gridWidth, child: grid),
        );
      },
    );
  }

  Widget _buildWeightCell(int index) {
    final cellNumber = index + 1;
    final hasValue = widget.controllers[index].text.trim().isNotEmpty;

    if (widget.mode == WeightsMode.egg) {
      return _buildEggWeightCell(index, cellNumber, hasValue);
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
            child: TextField(
              controller: widget.controllers[index],
              focusNode: widget.focusNodes[index],
              enabled: widget.enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
              ],
              textInputAction: index < widget.focusNodes.length - 1
                  ? TextInputAction.next
                  : TextInputAction.done,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onSubmitted: (_) {
                if (index < widget.focusNodes.length - 1) {
                  FocusScope.of(
                    context,
                  ).requestFocus(widget.focusNodes[index + 1]);
                } else {
                  FocusScope.of(context).unfocus();
                }
              },
              onChanged: (_) {
                _scheduleChanged();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEggWeightCell(int index, int cellNumber, bool hasValue) {
    final activeColor = const Color(0xFFF65C00);

    return Container(
      decoration: BoxDecoration(
        color: hasValue ? const Color(0xFFFFF8F2) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasValue ? activeColor : const Color(0xFFE5E7EB),
          width: hasValue ? 1.3 : 1,
        ),
      ),
      child: TextField(
        controller: widget.controllers[index],
        focusNode: widget.focusNodes[index],
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: widget.enabled ? Colors.black87 : Colors.grey[600],
        ),
        decoration: InputDecoration(
          hintText: '$cellNumber',
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 10,
          ),
          isDense: true,
          counterText: '',
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
        ],
        textInputAction: index < widget.focusNodes.length - 1
            ? TextInputAction.next
            : TextInputAction.done,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onSubmitted: (_) {
          if (index < widget.focusNodes.length - 1) {
            FocusScope.of(context).requestFocus(widget.focusNodes[index + 1]);
          } else {
            FocusScope.of(context).unfocus();
          }
        },
        onChanged: (_) => _scheduleChanged(),
      ),
    );
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
