import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/lighting_provider.dart';
import '../widgets/hex_input_field.dart';

class ColorScreen extends ConsumerWidget {
  const ColorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lightingProvider);
    final notifier = ref.read(lightingProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Color',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the wheel or enter a hex value',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          // Color Wheel — capped at 360px wide to prevent internal Row overflow on desktop
          Center(
            child: Container(
              width: 360,
              height: 420,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              padding: const EdgeInsets.all(16),
              child: ColorPicker(
                pickerColor: state.color,
                onColorChanged: notifier.setColor,
                colorPickerWidth: 328,
                pickerAreaHeightPercent: 0.78,
                enableAlpha: false,
                displayThumbColor: true,
                portraitOnly: true,
                paletteType: PaletteType.hsvWithHue,
                hexInputBar: false,
                labelTypes: const [],
                pickerAreaBorderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Hex Input
          HexInputField(
            color: state.color,
            onColorChanged: notifier.setColor,
          ),

          const SizedBox(height: 20),

          // Active effect badge
          if (state.activeEffect != null)
            _ActiveEffectBadge(
              effectName: state.activeEffect!,
              onClear: notifier.clearEffect,
            ),
        ],
      ),
    );
  }
}

class _ActiveEffectBadge extends StatelessWidget {
  final String effectName;
  final VoidCallback onClear;

  const _ActiveEffectBadge({
    required this.effectName,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: secondary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: secondary.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Effect active: $effectName',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: secondary.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}
