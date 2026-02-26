import 'package:flutter/material.dart';

class BrightnessPreview extends StatelessWidget {
  final Color color;
  final double brightness;

  const BrightnessPreview({
    super.key,
    required this.color,
    required this.brightness,
  });

  Color get _displayColor {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness * brightness).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final display = _displayColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      height: 60,
      decoration: BoxDecoration(
        color: display,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: display.withOpacity(0.6 * brightness),
            blurRadius: 40 * brightness,
            spreadRadius: 4 * brightness,
          ),
        ],
      ),
    );
  }
}
