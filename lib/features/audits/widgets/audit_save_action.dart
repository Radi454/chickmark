import 'package:flutter/material.dart';

class AuditSaveAction extends StatelessWidget {
  final bool isEnabled;
  final bool isSaving;
  final VoidCallback onPressed;

  const AuditSaveAction({
    super.key,
    required this.isEnabled,
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = isEnabled && !isSaving;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: isSaving ? 'Saving' : 'Save',
        child: TextButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.save_outlined, size: 20),
          label: Text(isSaving ? 'Saving' : 'Save'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white60,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: enabled ? Colors.white70 : Colors.white24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
