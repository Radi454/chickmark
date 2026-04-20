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
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: List.generate(100, (index) {
        return _buildWeightCell(index);
      }),
    );
  }

  Widget _buildWeightCell(int index) {
    final cellNumber = index + 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Cell number label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Text(
              '$cellNumber',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          // Weight input field
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: widget.enabled ? Colors.black : Colors.grey[600],
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
              ],
              textInputAction: index < 99
                  ? TextInputAction.next
                  : TextInputAction.done,
              onSubmitted: (_) {
                if (index < 99) {
                  FocusScope.of(
                    context,
                  ).requestFocus(widget.focusNodes[index + 1]);
                }
              },
              onChanged: (_) {
                widget.onChanged?.call();
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Don't dispose controllers and focusNodes here as they're managed by the parent
    super.dispose();
  }
}
