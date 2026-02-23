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

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 120,
          decoration: BoxDecoration(
            color: display,
            borderRadius: BorderRadius.circular(20),
            boxShadow: brightness > 0.05
                ? [
                    BoxShadow(
                      color: display.withOpacity(0.6 * brightness),
                      blurRadius: 40 * brightness,
                      spreadRadius: 4 * brightness,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          brightness < 0.05
              ? 'Off'
              : '${(brightness * 100).round()}% brightness',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.55),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
