export 'package:flutter/material.dart'
    hide Text, TextField, TextFormField, DropdownButtonFormField, Tooltip;
export 'l10n/app_localizations.dart';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' as services;

import 'l10n/app_localizations.dart';

class Text extends material.StatelessWidget {
  final String? data;
  final material.InlineSpan? textSpan;
  final material.TextStyle? style;
  final material.StrutStyle? strutStyle;
  final material.TextAlign? textAlign;
  final material.TextDirection? textDirection;
  final material.Locale? locale;
  final bool? softWrap;
  final material.TextOverflow? overflow;
  final double? textScaleFactor;
  final material.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final material.TextWidthBasis? textWidthBasis;
  final material.TextHeightBehavior? textHeightBehavior;
  final material.Color? selectionColor;

  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    material.InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  @override
  material.Widget build(material.BuildContext context) {
    final raw = data;
    if (raw != null) {
      return material.Text(
        context.tr(raw),
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        // ignore: deprecated_member_use
        textScaleFactor: textScaleFactor,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel == null
            ? null
            : context.tr(semanticsLabel!),
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return material.Text.rich(
      _translateInlineSpan(context, textSpan!),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      // ignore: deprecated_member_use
      textScaleFactor: textScaleFactor,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null
          ? null
          : context.tr(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }

  material.InlineSpan _translateInlineSpan(
    material.BuildContext context,
    material.InlineSpan span,
  ) {
    if (span is! material.TextSpan) return span;
    return material.TextSpan(
      text: span.text == null ? null : context.tr(span.text!),
      children: span.children
          ?.map((child) => _translateInlineSpan(context, child))
          .toList(),
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel == null
          ? null
          : context.tr(span.semanticsLabel!),
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}

class Tooltip extends material.StatelessWidget {
  final String message;
  final material.Widget child;

  const Tooltip({super.key, required this.message, required this.child});

  @override
  material.Widget build(material.BuildContext context) {
    return material.Tooltip(message: context.tr(message), child: child);
  }
}

class TextField extends material.StatelessWidget {
  final material.Key? fieldKey;
  final material.TextEditingController? controller;
  final material.FocusNode? focusNode;
  final material.InputDecoration? decoration;
  final material.TextInputType? keyboardType;
  final material.TextInputAction? textInputAction;
  final material.TextStyle? style;
  final material.TextAlign textAlign;
  final bool readOnly;
  final bool? showCursor;
  final int? maxLines;
  final int? minLines;
  final material.ValueChanged<String>? onChanged;
  final material.ValueChanged<String>? onSubmitted;
  final material.VoidCallback? onEditingComplete;
  final material.GestureTapCallback? onTap;
  final List<services.TextInputFormatter>? inputFormatters;
  final bool? enabled;

  const TextField({
    material.Key? key,
    this.controller,
    this.focusNode,
    this.decoration = const material.InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.style,
    this.textAlign = material.TextAlign.start,
    this.readOnly = false,
    this.showCursor,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.inputFormatters,
    this.enabled,
  }) : fieldKey = key,
       super(key: null);

  @override
  material.Widget build(material.BuildContext context) {
    return material.TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      decoration: decoration?.localized(context),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: style,
      textAlign: textAlign,
      readOnly: readOnly,
      showCursor: showCursor,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      onTap: onTap,
      inputFormatters: inputFormatters,
      enabled: enabled,
    );
  }
}

class TextFormField extends material.StatelessWidget {
  final material.Key? fieldKey;
  final material.TextEditingController? controller;
  final String? initialValue;
  final material.FocusNode? focusNode;
  final material.InputDecoration? decoration;
  final material.TextInputType? keyboardType;
  final material.TextInputAction? textInputAction;
  final material.TextStyle? style;
  final material.TextAlign textAlign;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final material.ValueChanged<String>? onChanged;
  final material.ValueChanged<String>? onFieldSubmitted;
  final material.FormFieldValidator<String>? validator;
  final material.VoidCallback? onEditingComplete;
  final material.GestureTapCallback? onTap;
  final List<services.TextInputFormatter>? inputFormatters;
  final bool? enabled;

  const TextFormField({
    material.Key? key,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.decoration = const material.InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.style,
    this.textAlign = material.TextAlign.start,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
    this.onEditingComplete,
    this.onTap,
    this.inputFormatters,
    this.enabled,
  }) : fieldKey = key,
       super(key: null);

  @override
  material.Widget build(material.BuildContext context) {
    return material.TextFormField(
      key: fieldKey,
      controller: controller,
      initialValue: initialValue,
      focusNode: focusNode,
      decoration: decoration?.localized(context),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: style,
      textAlign: textAlign,
      obscureText: obscureText,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator == null
          ? null
          : (value) {
              final error = validator!(value);
              return error == null ? null : context.tr(error);
            },
      onEditingComplete: onEditingComplete,
      onTap: onTap,
      inputFormatters: inputFormatters,
      enabled: enabled,
    );
  }
}

class DropdownButtonFormField<T> extends material.StatelessWidget {
  final material.Key? fieldKey;
  final List<material.DropdownMenuItem<T>>? items;
  final material.DropdownButtonBuilder? selectedItemBuilder;
  final T? value;
  final T? initialValue;
  final material.Widget? hint;
  final material.Widget? disabledHint;
  final material.ValueChanged<T?>? onChanged;
  final material.VoidCallback? onTap;
  final material.TextStyle? style;
  final bool isDense;
  final bool isExpanded;
  final material.InputDecoration? decoration;
  final material.FormFieldValidator<T>? validator;

  const DropdownButtonFormField({
    material.Key? key,
    required this.items,
    this.selectedItemBuilder,
    this.value,
    this.initialValue,
    this.hint,
    this.disabledHint,
    required this.onChanged,
    this.onTap,
    this.style,
    this.isDense = true,
    this.isExpanded = false,
    this.decoration,
    this.validator,
  }) : fieldKey = key,
       super(key: null);

  @override
  material.Widget build(material.BuildContext context) {
    return material.DropdownButtonFormField<T>(
      key: fieldKey,
      items: items,
      selectedItemBuilder: selectedItemBuilder,
      // ignore: deprecated_member_use
      value: value,
      initialValue: initialValue,
      hint: hint,
      disabledHint: disabledHint,
      onChanged: onChanged,
      onTap: onTap,
      style: style,
      isDense: isDense,
      isExpanded: isExpanded,
      decoration: decoration?.localized(context),
      validator: validator == null
          ? null
          : (value) {
              final error = validator!(value);
              return error == null ? null : context.tr(error);
            },
    );
  }
}

extension LocalizedInputDecoration on material.InputDecoration {
  material.InputDecoration localized(material.BuildContext context) {
    String? tr(String? value) => value == null ? null : context.tr(value);
    return copyWith(
      labelText: tr(labelText),
      helperText: tr(helperText),
      hintText: tr(hintText),
      errorText: tr(errorText),
      prefixText: tr(prefixText),
      suffixText: tr(suffixText),
      counterText: tr(counterText),
      semanticCounterText: tr(semanticCounterText),
    );
  }
}
