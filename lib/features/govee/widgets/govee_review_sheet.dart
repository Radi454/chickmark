import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

class GoveeReviewSheet extends StatefulWidget {
  final List<String> initialLabels;
  final Future<void> Function(List<String> labels) onSave;

  const GoveeReviewSheet({
    super.key,
    required this.initialLabels,
    required this.onSave,
  });

  @override
  State<GoveeReviewSheet> createState() => _GoveeReviewSheetState();
}

class _GoveeReviewSheetState extends State<GoveeReviewSheet> {
  late final List<TextEditingController> _controllers;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      final label = index < widget.initialLabels.length
          ? widget.initialLabels[index]
          : 'Spot ${index + 1}';
      return TextEditingController(text: label);
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Review spots',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < _controllers.length; index += 1) ...[
            TextField(
              key: ValueKey('govee-spot-label-${index + 1}'),
              controller: _controllers[index],
              decoration: InputDecoration(
                labelText: 'Spot ${index + 1}',
                border: const OutlineInputBorder(),
              ),
            ),
            if (index != _controllers.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isSaving
                ? null
                : () async {
                    setState(() => _isSaving = true);
                    await widget.onSave(
                      _controllers
                          .map((controller) => controller.text)
                          .toList(),
                    );
                    if (mounted) {
                      setState(() => _isSaving = false);
                    }
                  },
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save place'),
          ),
        ],
      ),
    );
  }
}
