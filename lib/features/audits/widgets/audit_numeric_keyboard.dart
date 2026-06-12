import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audit_numeric_platform.dart';

enum AuditNumericInputMode { adaptive, customKeyboard, systemKeyboard }

final RegExp _numericTextPattern = RegExp(r'^-?\d*\.?\d*$');

bool _defaultPlatformUsesCustomKeyboard() {
  if (kIsWeb && auditNumericWebPrefersSystemKeyboard()) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}

bool auditNumericInputModeUsesCustomKeyboard(AuditNumericInputMode inputMode) {
  return switch (inputMode) {
    AuditNumericInputMode.customKeyboard => true,
    AuditNumericInputMode.systemKeyboard => false,
    AuditNumericInputMode.adaptive => _defaultPlatformUsesCustomKeyboard(),
  };
}

bool _isAllowedNumericText(
  String text, {
  required bool allowDecimal,
  required bool allowNegative,
  required int? maxDecimalPlaces,
}) {
  if (text.isEmpty) return true;
  if (!allowNegative && text.contains('-')) return false;
  if (!allowDecimal && text.contains('.')) return false;
  if (!_numericTextPattern.hasMatch(text)) return false;
  if (text.indexOf('-') > 0) return false;
  if ('.'.allMatches(text).length > 1) return false;
  if ('-'.allMatches(text).length > 1) return false;

  if (maxDecimalPlaces != null && text.contains('.')) {
    final fraction = text.split('.').last;
    if (fraction.length > maxDecimalPlaces) return false;
  }
  return true;
}

class AuditNumericKeyboardScope extends StatefulWidget {
  final Widget child;
  final AuditNumericInputMode inputMode;

  const AuditNumericKeyboardScope({
    super.key,
    required this.child,
    this.inputMode = AuditNumericInputMode.adaptive,
  });

  static _AuditNumericKeyboardScopeState? _maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AuditNumericKeyboardHost>()
        ?.state;
  }

  @override
  State<AuditNumericKeyboardScope> createState() =>
      _AuditNumericKeyboardScopeState();
}

class _AuditNumericKeyboardScopeState extends State<AuditNumericKeyboardScope> {
  static const double _focusedFieldScrollAlignment = 0.22;

  final List<_AuditNumericFieldRegistration> _fields = [];
  OverlayEntry? _overlayEntry;
  _AuditNumericFieldRegistration? _activeField;

  bool get usesCustomKeyboard {
    return auditNumericInputModeUsesCustomKeyboard(widget.inputMode);
  }

  @override
  void didUpdateWidget(AuditNumericKeyboardScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!usesCustomKeyboard) {
      _hideKeyboard();
    }
  }

  void register(_AuditNumericFieldRegistration field) {
    if (_fields.contains(field)) return;
    _fields.add(field);
  }

  void unregister(_AuditNumericFieldRegistration field) {
    _fields.remove(field);
    if (_activeField == field) {
      _hideKeyboard();
    }
  }

  void activateField(_AuditNumericFieldRegistration field) {
    if (!field.enabled) return;
    if (!usesCustomKeyboard) {
      field.focusNode.requestFocus();
      return;
    }
    _activeField = field;
    field.focusNode.requestFocus();
    _showKeyboard();
    _ensureVisible(field);
  }

  void deactivateField(_AuditNumericFieldRegistration field) {
    if (_activeField == field) {
      _hideKeyboard();
    }
  }

  void _showKeyboard() {
    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(
        builder: (context) {
          final activeField = _activeField;
          if (activeField == null || !activeField.enabled) {
            return const SizedBox.shrink();
          }

          return Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              key: const ValueKey('audit_numeric_keyboard_safe_area'),
              color: AuditNumericKeyboard.keyboardBackground,
              child: SafeArea(
                top: false,
                child: AuditNumericKeyboard(
                  allowDecimal: activeField.allowDecimal,
                  allowNegative: activeField.allowNegative,
                  hasNext: _nextField(activeField) != null,
                  hasMoveDown: _moveDownTarget(activeField) != null,
                  onDigit: _insertText,
                  onDecimal: () => _insertText('.'),
                  onNegative: _toggleNegative,
                  onBackspace: _backspace,
                  onNext: _moveNext,
                  onMoveDown: _moveDown,
                  onHide: _hideKeyboard,
                ),
              ),
            ),
          );
        },
      );
      Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _hideKeyboard() {
    final activeField = _activeField;
    _activeField = null;
    activeField?.focusNode.unfocus();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _insertText(String value) {
    final field = _activeField;
    if (field == null || !field.enabled) return;
    if (value == '.' && !field.allowDecimal) return;

    final controller = field.controller;
    final text = controller.text;
    final selection = _selectionFor(controller);
    final nextText = text.replaceRange(selection.start, selection.end, value);
    final nextOffset = selection.start + value.length;

    _setText(field, nextText, nextOffset);
  }

  void _toggleNegative() {
    final field = _activeField;
    if (field == null || !field.enabled || !field.allowNegative) return;

    final controller = field.controller;
    final text = controller.text;
    final selection = _selectionFor(controller);
    final nextText = text.startsWith('-') ? text.substring(1) : '-$text';
    final nextOffset = text.startsWith('-')
        ? (selection.baseOffset - 1).clamp(0, nextText.length)
        : (selection.baseOffset + 1).clamp(0, nextText.length);

    _setText(field, nextText, nextOffset);
  }

  void _backspace() {
    final field = _activeField;
    if (field == null || !field.enabled) return;

    final controller = field.controller;
    final text = controller.text;
    final selection = _selectionFor(controller);
    if (!selection.isCollapsed) {
      _setText(
        field,
        text.replaceRange(selection.start, selection.end, ''),
        selection.start,
      );
      return;
    }
    if (selection.start == 0) return;

    final nextOffset = selection.start - 1;
    final nextText = text.replaceRange(nextOffset, selection.start, '');
    _setText(field, nextText, nextOffset);
  }

  void _moveNext() {
    final field = _activeField;
    if (field == null) return;

    final next = _nextField(field);
    if (next == null) return;
    _focusField(next);
  }

  void _moveDown() {
    final field = _activeField;
    if (field == null) return;

    final next = _moveDownTarget(field);
    if (next == null) return;
    _focusField(next);
  }

  void _focusField(_AuditNumericFieldRegistration field) {
    _activeField = field;
    field.focusNode.requestFocus();
    _overlayEntry?.markNeedsBuild();
    _ensureVisible(field);
  }

  void _ensureVisible(_AuditNumericFieldRegistration field) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = field.fieldKey.currentContext;
      if (targetContext == null || !field.enabled) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: _focusedFieldScrollAlignment,
      );
    });
  }

  _AuditNumericFieldRegistration? _nextField(
    _AuditNumericFieldRegistration field,
  ) {
    final startIndex = _fields.indexOf(field);
    if (startIndex == -1) return null;
    for (var i = startIndex + 1; i < _fields.length; i++) {
      if (_fields[i].enabled) return _fields[i];
    }
    return null;
  }

  _AuditNumericFieldRegistration? _moveDownTarget(
    _AuditNumericFieldRegistration field,
  ) {
    if (!_hasGridNavigation(field)) {
      return _nextField(field);
    }
    return _fieldBelow(field);
  }

  bool _hasGridNavigation(_AuditNumericFieldRegistration field) {
    return field.navigationGroup != null &&
        field.navigationRow != null &&
        field.navigationColumn != null;
  }

  _AuditNumericFieldRegistration? _fieldBelow(
    _AuditNumericFieldRegistration field,
  ) {
    final group = field.navigationGroup;
    final row = field.navigationRow;
    final column = field.navigationColumn;
    if (group == null || row == null || column == null) return null;

    _AuditNumericFieldRegistration? best;
    for (final candidate in _fields) {
      if (!candidate.enabled ||
          candidate == field ||
          candidate.navigationGroup != group ||
          candidate.navigationColumn != column) {
        continue;
      }
      final candidateRow = candidate.navigationRow;
      if (candidateRow == null || candidateRow <= row) continue;
      if (best == null || candidateRow < best.navigationRow!) {
        best = candidate;
      }
    }
    return best;
  }

  TextSelection _selectionFor(TextEditingController controller) {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: text.length);
    }
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  void _setText(
    _AuditNumericFieldRegistration field,
    String nextText,
    int nextOffset,
  ) {
    if (!_isAllowedNumericText(
      nextText,
      allowDecimal: field.allowDecimal,
      allowNegative: field.allowNegative,
      maxDecimalPlaces: field.maxDecimalPlaces,
    )) {
      return;
    }

    final offset = nextOffset.clamp(0, nextText.length);
    field.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: offset),
    );
    field.onChanged?.call(nextText);
    _overlayEntry?.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return _AuditNumericKeyboardHost(
      state: this,
      inputMode: widget.inputMode,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }
}

class _AuditNumericKeyboardHost extends InheritedWidget {
  final _AuditNumericKeyboardScopeState state;
  final AuditNumericInputMode inputMode;

  const _AuditNumericKeyboardHost({
    required this.state,
    required this.inputMode,
    required super.child,
  });

  @override
  bool updateShouldNotify(_AuditNumericKeyboardHost oldWidget) =>
      state != oldWidget.state || inputMode != oldWidget.inputMode;
}

class _AuditNumericTextInputFormatter extends TextInputFormatter {
  final bool allowDecimal;
  final bool allowNegative;
  final int? maxDecimalPlaces;

  const _AuditNumericTextInputFormatter({
    required this.allowDecimal,
    required this.allowNegative,
    required this.maxDecimalPlaces,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_isAllowedNumericText(
      newValue.text,
      allowDecimal: allowDecimal,
      allowNegative: allowNegative,
      maxDecimalPlaces: maxDecimalPlaces,
    )) {
      return newValue;
    }
    return oldValue;
  }
}

class AuditNumericField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool allowDecimal;
  final bool allowNegative;
  final int? maxDecimalPlaces;
  final String? navigationGroup;
  final int? navigationRow;
  final int? navigationColumn;
  final TextAlign textAlign;
  final TextStyle? style;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const AuditNumericField({
    super.key,
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.allowDecimal = false,
    this.allowNegative = false,
    this.maxDecimalPlaces,
    this.navigationGroup,
    this.navigationRow,
    this.navigationColumn,
    this.textAlign = TextAlign.start,
    this.style,
    this.decoration,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<AuditNumericField> createState() => _AuditNumericFieldState();
}

class AuditNumericFormField extends StatefulWidget {
  final String? initialValue;
  final bool enabled;
  final bool allowDecimal;
  final bool allowNegative;
  final int? maxDecimalPlaces;
  final String? navigationGroup;
  final int? navigationRow;
  final int? navigationColumn;
  final TextAlign textAlign;
  final TextStyle? style;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;

  const AuditNumericFormField({
    super.key,
    this.initialValue,
    this.enabled = true,
    this.allowDecimal = false,
    this.allowNegative = false,
    this.maxDecimalPlaces,
    this.navigationGroup,
    this.navigationRow,
    this.navigationColumn,
    this.textAlign = TextAlign.start,
    this.style,
    this.decoration,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
  });

  @override
  State<AuditNumericFormField> createState() => _AuditNumericFormFieldState();
}

class _AuditNumericFormFieldState extends State<AuditNumericFormField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(AuditNumericFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: widget.initialValue ?? '',
      enabled: widget.enabled,
      validator: widget.validator,
      builder: (field) {
        final decoration = (widget.decoration ?? const InputDecoration())
            .copyWith(errorText: field.errorText);
        return AuditNumericField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          allowDecimal: widget.allowDecimal,
          allowNegative: widget.allowNegative,
          maxDecimalPlaces: widget.maxDecimalPlaces,
          navigationGroup: widget.navigationGroup,
          navigationRow: widget.navigationRow,
          navigationColumn: widget.navigationColumn,
          textAlign: widget.textAlign,
          style: widget.style,
          decoration: decoration,
          onChanged: (value) {
            field.didChange(value);
            widget.onChanged?.call(value);
          },
          onSubmitted: (value) {
            field.didChange(value);
            widget.onFieldSubmitted?.call(value);
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

class _AuditNumericFieldState extends State<AuditNumericField> {
  late final FocusNode _ownedFocusNode;
  final GlobalKey _fieldKey = GlobalKey();
  _AuditNumericKeyboardScopeState? _scope;
  late final _AuditNumericFieldRegistration _registration;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;
  bool get _usesCustomKeyboard =>
      _scope?.usesCustomKeyboard ?? _defaultPlatformUsesCustomKeyboard();

  @override
  void initState() {
    super.initState();
    _ownedFocusNode = FocusNode();
    _registration = _AuditNumericFieldRegistration(
      controller: widget.controller,
      focusNode: _focusNode,
      fieldKey: _fieldKey,
      enabled: widget.enabled,
      allowDecimal: widget.allowDecimal,
      allowNegative: widget.allowNegative,
      maxDecimalPlaces: widget.maxDecimalPlaces,
      navigationGroup: widget.navigationGroup,
      navigationRow: widget.navigationRow,
      navigationColumn: widget.navigationColumn,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScope = AuditNumericKeyboardScope._maybeOf(context);
    if (_scope == nextScope) return;
    _scope?.unregister(_registration);
    _scope = nextScope;
    _scope?.register(_registration);
  }

  @override
  void didUpdateWidget(AuditNumericField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode).removeListener(
        _handleFocusChange,
      );
      _focusNode.addListener(_handleFocusChange);
      _registration.focusNode = _focusNode;
    }
    _registration
      ..controller = widget.controller
      ..enabled = widget.enabled
      ..allowDecimal = widget.allowDecimal
      ..allowNegative = widget.allowNegative
      ..maxDecimalPlaces = widget.maxDecimalPlaces
      ..navigationGroup = widget.navigationGroup
      ..navigationRow = widget.navigationRow
      ..navigationColumn = widget.navigationColumn
      ..onChanged = widget.onChanged
      ..onSubmitted = widget.onSubmitted;
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _scope?.deactivateField(_registration);
    }
  }

  void _activate() {
    if (!widget.enabled) return;
    _scope?.activateField(_registration);
  }

  @override
  Widget build(BuildContext context) {
    final usesCustomKeyboard = _usesCustomKeyboard;
    return KeyedSubtree(
      key: _fieldKey,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        readOnly: usesCustomKeyboard,
        showCursor: widget.enabled,
        keyboardType: usesCustomKeyboard
            ? TextInputType.none
            : TextInputType.numberWithOptions(
                decimal: widget.allowDecimal,
                signed: widget.allowNegative,
              ),
        inputFormatters: usesCustomKeyboard
            ? null
            : [
                _AuditNumericTextInputFormatter(
                  allowDecimal: widget.allowDecimal,
                  allowNegative: widget.allowNegative,
                  maxDecimalPlaces: widget.maxDecimalPlaces,
                ),
              ],
        textAlign: widget.textAlign,
        style: widget.style,
        decoration: widget.decoration,
        onTap: usesCustomKeyboard ? _activate : null,
        onChanged: usesCustomKeyboard ? null : widget.onChanged,
        onSubmitted: usesCustomKeyboard ? null : widget.onSubmitted,
      ),
    );
  }

  @override
  void dispose() {
    _scope?.unregister(_registration);
    _focusNode.removeListener(_handleFocusChange);
    _ownedFocusNode.dispose();
    super.dispose();
  }
}

class _AuditNumericFieldRegistration {
  TextEditingController controller;
  FocusNode focusNode;
  GlobalKey fieldKey;
  bool enabled;
  bool allowDecimal;
  bool allowNegative;
  int? maxDecimalPlaces;
  String? navigationGroup;
  int? navigationRow;
  int? navigationColumn;
  ValueChanged<String>? onChanged;
  ValueChanged<String>? onSubmitted;

  _AuditNumericFieldRegistration({
    required this.controller,
    required this.focusNode,
    required this.fieldKey,
    required this.enabled,
    required this.allowDecimal,
    required this.allowNegative,
    required this.maxDecimalPlaces,
    required this.navigationGroup,
    required this.navigationRow,
    required this.navigationColumn,
    required this.onChanged,
    required this.onSubmitted,
  });
}

class AuditNumericKeyboard extends StatelessWidget {
  static const double _outerHorizontalPadding = 12;
  static const double _outerTopPadding = 12;
  static const double _outerBottomPadding = 10;
  static const double _keyGap = 12;
  static const double _keyAspectRatio = 1.22;
  static const Color keyboardBackground = Color(0xFFCDD2DC);
  static const Color _actionKeyColor = Color(0xFFB4BBC8);

  final bool allowDecimal;
  final bool allowNegative;
  final bool hasNext;
  final bool hasMoveDown;
  final ValueChanged<String> onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onNegative;
  final VoidCallback onBackspace;
  final VoidCallback onNext;
  final VoidCallback onMoveDown;
  final VoidCallback onHide;

  const AuditNumericKeyboard({
    super.key,
    required this.allowDecimal,
    required this.allowNegative,
    required this.hasNext,
    required this.hasMoveDown,
    required this.onDigit,
    required this.onDecimal,
    required this.onNegative,
    required this.onBackspace,
    required this.onNext,
    required this.onMoveDown,
    required this.onHide,
  });

  static double estimatedHeightForWidth(
    double width, {
    double safeAreaBottom = 0,
  }) {
    final availableWidth = width.isFinite && width > 0
        ? width - (_outerHorizontalPadding * 2)
        : 0;
    final keyWidth = (availableWidth - (_keyGap * 3)) / 4;
    final keyHeight = keyWidth > 0 ? keyWidth / _keyAspectRatio : 0;
    final keypadHeight = (keyHeight * 4) + (_keyGap * 3);
    return _outerTopPadding +
        keypadHeight +
        _outerBottomPadding +
        safeAreaBottom;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: keyboardBackground,
      padding: const EdgeInsets.fromLTRB(
        _outerHorizontalPadding,
        _outerTopPadding,
        _outerHorizontalPadding,
        _outerBottomPadding,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width -
                    (_outerHorizontalPadding * 2);
          final keyWidth = (availableWidth - (_keyGap * 3)) / 4;
          var keyHeight = keyWidth / _keyAspectRatio;
          if (constraints.maxHeight.isFinite) {
            final availableHeight = constraints.maxHeight - (_keyGap * 3);
            final maxKeyHeight = availableHeight > 0
                ? availableHeight / 4
                : keyHeight;
            if (keyHeight > maxKeyHeight) {
              keyHeight = maxKeyHeight;
            }
          }
          final keypadHeight = (keyHeight * 4) + (_keyGap * 3);

          Widget row(List<Widget> keys) {
            return SizedBox(
              height: keyHeight,
              child: Row(
                children: [
                  SizedBox(width: keyWidth, child: keys[0]),
                  const SizedBox(width: _keyGap),
                  SizedBox(width: keyWidth, child: keys[1]),
                  const SizedBox(width: _keyGap),
                  SizedBox(width: keyWidth, child: keys[2]),
                ],
              ),
            );
          }

          return SizedBox(
            height: keypadHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: (keyWidth * 3) + (_keyGap * 2),
                  child: Column(
                    children: [
                      row([
                        _NumberKey(label: '7', onTap: () => onDigit('7')),
                        _NumberKey(label: '8', onTap: () => onDigit('8')),
                        _NumberKey(label: '9', onTap: () => onDigit('9')),
                      ]),
                      const SizedBox(height: _keyGap),
                      row([
                        _NumberKey(label: '4', onTap: () => onDigit('4')),
                        _NumberKey(label: '5', onTap: () => onDigit('5')),
                        _NumberKey(label: '6', onTap: () => onDigit('6')),
                      ]),
                      const SizedBox(height: _keyGap),
                      row([
                        _NumberKey(label: '1', onTap: () => onDigit('1')),
                        _NumberKey(label: '2', onTap: () => onDigit('2')),
                        _NumberKey(label: '3', onTap: () => onDigit('3')),
                      ]),
                      const SizedBox(height: _keyGap),
                      row([
                        allowNegative
                            ? _NumberKey(label: '-', onTap: onNegative)
                            : _IconKey(
                                icon: Icons.keyboard_hide,
                                onTap: onHide,
                              ),
                        _NumberKey(label: '0', onTap: () => onDigit('0')),
                        _NumberKey(
                          label: '.',
                          enabled: allowDecimal,
                          onTap: onDecimal,
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: _keyGap),
                SizedBox(
                  width: keyWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: keyHeight,
                        child: _IconKey(
                          icon: Icons.backspace_outlined,
                          onTap: onBackspace,
                        ),
                      ),
                      const SizedBox(height: _keyGap),
                      SizedBox(
                        height: keyHeight,
                        child: _IconKey(
                          icon: Icons.arrow_forward,
                          onTap: hasNext ? onNext : null,
                        ),
                      ),
                      const SizedBox(height: _keyGap),
                      SizedBox(
                        height: (keyHeight * 2) + _keyGap,
                        child: _IconKey(
                          icon: Icons.keyboard_return,
                          onTap: hasMoveDown ? onMoveDown : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NumberKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _NumberKey({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return _KeySurface(
      color: Colors.white,
      onTap: enabled ? onTap : null,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 36,
          height: 1,
          color: enabled ? Colors.black : const Color(0xFF8F98A8),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _IconKey extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _IconKey({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return _KeySurface(
      color: enabled
          ? AuditNumericKeyboard._actionKeyColor
          : AuditNumericKeyboard._actionKeyColor.withAlpha(140),
      onTap: onTap,
      child: Icon(
        icon,
        size: 38,
        color: enabled ? Colors.black : Colors.black45,
      ),
    );
  }
}

class _KeySurface extends StatelessWidget {
  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  const _KeySurface({
    required this.color,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}
