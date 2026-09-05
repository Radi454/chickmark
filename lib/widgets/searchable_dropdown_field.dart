import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/localized_material.dart';

/// One selectable option in a [SearchableDropdownField].
class SearchableDropdownOption<T> {
  const SearchableDropdownOption({required this.value, required this.label});

  final T? value;
  final String label;
}

/// A dropdown that doubles as a search box: tapping it focuses a text field and
/// typing filters the options by a case-insensitive substring match.
///
/// Behaves like [DropdownButtonFormField] otherwise — same label/decoration
/// style, same [onChanged] contract, and the field text is restored to the
/// selected option when the menu closes without a selection.
class SearchableDropdownField<T> extends StatefulWidget {
  const SearchableDropdownField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hintText,
  });

  final String label;
  final List<SearchableDropdownOption<T>> options;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? hintText;

  @override
  State<SearchableDropdownField<T>> createState() =>
      _SearchableDropdownFieldState<T>();
}

class _SearchableDropdownFieldState<T>
    extends State<SearchableDropdownField<T>> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Focusing clears the field so the whole list is offered and typing starts
  /// on an empty query — the selected name never has to be deleted first.
  /// Abandoning the menu must not leave that empty (or partial) query behind,
  /// so blurring restores the selected option's label.
  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (_controller.text.isNotEmpty) _controller.clear();
      return;
    }
    final label = _labelFor(widget.value);
    if (label != null && _controller.text != label) {
      _controller.text = label;
    }
  }

  String? _labelFor(T? value) {
    for (final option in widget.options) {
      if (option.value == value) return option.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<T?>(
      controller: _controller,
      focusNode: _focusNode,
      initialSelection: widget.value,
      enabled: widget.onChanged != null,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      menuHeight: 320,
      label: Text(widget.label),
      hintText: widget.hintText == null ? null : context.tr(widget.hintText!),
      textStyle: Theme.of(context).textTheme.bodyMedium,
      inputDecorationTheme: const InputDecorationThemeData(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSizes.spaceSm,
          vertical: AppSizes.spaceSm,
        ),
      ),
      onSelected: widget.onChanged,
      dropdownMenuEntries: [
        for (final option in widget.options)
          DropdownMenuEntry<T?>(value: option.value, label: option.label),
      ],
    );
  }
}
