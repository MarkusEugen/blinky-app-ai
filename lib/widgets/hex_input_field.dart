import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HexInputField extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const HexInputField({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  @override
  State<HexInputField> createState() => _HexInputFieldState();
}

class _HexInputFieldState extends State<HexInputField> {
  late final TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _colorToHex(widget.color));
  }

  @override
  void didUpdateWidget(HexInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update text when external color changes and field is not focused.
    if (!_isEditing && oldWidget.color != widget.color) {
      _controller.text = _colorToHex(widget.color);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) {
    return '#${c.red.toRadixString(16).padLeft(2, '0')}'
            '${c.green.toRadixString(16).padLeft(2, '0')}'
            '${c.blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  Color? _parseHex(String text) {
    final clean = text.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final value = int.tryParse('FF$clean', radix: 16);
      if (value != null) return Color(value);
    }
    return null;
  }

  void _onSubmit(String value) {
    final parsed = _parseHex(value);
    if (parsed != null) {
      widget.onColorChanged(parsed);
    } else {
      // Revert to current valid color on bad input
      _controller.text = _colorToHex(widget.color);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Color swatch preview
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Focus(
            onFocusChange: (focused) => setState(() => _isEditing = focused),
            child: TextField(
              controller: _controller,
              inputFormatters: [
                // Allow # plus up to 6 hex chars
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final text = newValue.text;
                  if (text.isEmpty) return newValue;
                  final cleaned = text.startsWith('#') ? text : '#$text';
                  if (RegExp(r'^#[0-9A-Fa-f]{0,6}$').hasMatch(cleaned)) {
                    return newValue.copyWith(
                      text: cleaned.toUpperCase(),
                      selection: TextSelection.collapsed(
                          offset: cleaned.length),
                    );
                  }
                  return oldValue;
                }),
              ],
              onSubmitted: _onSubmit,
              onEditingComplete: () => _onSubmit(_controller.text),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 15,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
              decoration: const InputDecoration(
                labelText: 'Hex color',
                prefixIcon: Icon(Icons.tag, size: 18, color: Colors.white38),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ),
        ),
      ],
    );
  }
}
