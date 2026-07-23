import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

class AuditScopeIdentityField {
  const AuditScopeIdentityField({
    required this.key,
    required this.label,
    this.keyboardType = TextInputType.text,
  });

  final String key;
  final String label;
  final TextInputType keyboardType;
}

typedef AuditScopeIdentityValidator =
    String? Function(Map<String, String> values);

String normalizeAuditScopeIdentity(String value, {String? prefix}) {
  var normalized = value.trim();
  if (prefix != null &&
      normalized.toLowerCase().startsWith(prefix.toLowerCase())) {
    normalized = normalized.substring(prefix.length).trim();
  }
  return normalized.toLowerCase();
}

Future<Map<String, String>?> showAuditScopeIdentityDialog(
  BuildContext context, {
  required String scopeLabel,
  required List<AuditScopeIdentityField> fields,
  AuditScopeIdentityValidator? validator,
}) {
  assert(fields.isNotEmpty);
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _AuditScopeIdentityDialog(
      scopeLabel: scopeLabel,
      fields: fields,
      validator: validator,
    ),
  );
}

class _AuditScopeIdentityDialog extends StatefulWidget {
  const _AuditScopeIdentityDialog({
    required this.scopeLabel,
    required this.fields,
    this.validator,
  });

  final String scopeLabel;
  final List<AuditScopeIdentityField> fields;
  final AuditScopeIdentityValidator? validator;

  @override
  State<_AuditScopeIdentityDialog> createState() =>
      _AuditScopeIdentityDialogState();
}

class _AuditScopeIdentityDialogState extends State<_AuditScopeIdentityDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields) field.key: TextEditingController(),
  };
  String? _validationError;

  Map<String, String> get _values => {
    for (final field in widget.fields)
      field.key: _controllers[field.key]!.text.trim(),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final values = _values;
    final isComplete = values.values.every((value) => value.isNotEmpty);

    return AlertDialog(
      title: Text(context.tr('Add ${widget.scopeLabel} scope')),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < widget.fields.length; index++) ...[
                TextField(
                  key: ValueKey('scope-identity-${widget.fields[index].key}'),
                  controller: _controllers[widget.fields[index].key],
                  keyboardType: widget.fields[index].keyboardType,
                  textInputAction: index == widget.fields.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  autofocus: index == 0,
                  decoration: InputDecoration(
                    labelText: context.tr(widget.fields[index].label),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _validationError = null),
                ),
                if (index < widget.fields.length - 1)
                  const SizedBox(height: 12),
              ],
              if (_validationError != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.tr(_validationError!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('scope-identity-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('scope-identity-add'),
          onPressed: isComplete ? _submit : null,
          child: Text(context.tr('Add')),
        ),
      ],
    );
  }

  void _submit() {
    final values = _values;
    final error = widget.validator?.call(values);
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    Navigator.of(context).pop(values);
  }
}

Future<bool> confirmAuditScopeRemoval(
  BuildContext context, {
  required bool hasEnteredResults,
}) async {
  if (!hasEnteredResults) return true;

  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Remove scope?')),
          content: Text(
            context.tr(
              'This scope contains entered results. Removing it will '
              'permanently discard those results.',
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('scope-removal-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.tr('Cancel')),
            ),
            TextButton(
              key: const ValueKey('scope-removal-confirm'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.tr('Remove')),
            ),
          ],
        ),
      ) ??
      false;
}
