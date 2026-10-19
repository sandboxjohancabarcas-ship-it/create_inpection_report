import 'package:flutter/material.dart';

/// Free-text + Dropdown combobox widget for UI properties like
/// Zulassungsnummer, Herstellernummer, and DoP-Nummer.
class EditableDropdownField extends StatefulWidget {
  final String label;
  final String currentValue;
  final List<String> options;
  final ValueChanged<String> onChanged;

  final VoidCallback? onTakePhoto;

  const EditableDropdownField({
    super.key,
    required this.label,
    required this.currentValue,
    required this.options,
    required this.onChanged,
    this.onTakePhoto,
  });

  @override
  State<EditableDropdownField> createState() => _EditableDropdownFieldState();
}

class _EditableDropdownFieldState extends State<EditableDropdownField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant EditableDropdownField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentValue != _controller.text) {
      _controller.text = widget.currentValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Unique list of options, ensuring '?' is included first, followed by 'Foto' if photo feature is available
    final bool hasFoto = widget.onTakePhoto != null || widget.options.contains('Foto');
    final List<String> allOptions = [
      '?',
      if (hasFoto) 'Foto',
      ...widget.options.where((o) => o != '?' && o != 'Foto'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: RawAutocomplete<String>(
        textEditingController: _controller,
        focusNode: _focusNode,
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return allOptions;
          }
          return allOptions.where((String option) {
            return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
          });
        },
        onSelected: (String selection) {
          _controller.text = selection;
          widget.onChanged(selection);
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          Widget? suffix;
          final dropdownButton = PopupMenuButton<String>(
            icon: const Icon(Icons.arrow_drop_down),
            onSelected: (String value) {
              controller.text = value;
              widget.onChanged(value);
            },
            itemBuilder: (context) {
              return allOptions.map((opt) {
                return PopupMenuItem<String>(
                  value: opt,
                  child: Text(opt),
                );
              }).toList();
            },
          );

          if (widget.onTakePhoto != null) {
            suffix = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Foto für ${widget.label} aufnehmen',
                  onPressed: widget.onTakePhoto,
                ),
                dropdownButton,
              ],
            );
          } else {
            suffix = dropdownButton;
          }

          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixIcon: suffix,
            ),
            onChanged: widget.onChanged,
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 300,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(option),
                      onTap: () {
                        onSelected(option);
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
