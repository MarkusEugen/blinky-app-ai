import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/lighting_provider.dart';
import '../widgets/brightness_preview.dart';

class BrightnessScreen extends ConsumerWidget {
  const BrightnessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lightingProvider);
    final notifier = ref.read(lightingProvider.notifier);

    final percent = (state.brightness * 100).round();
    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Brightness',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Drag the slider to adjust intensity',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 36),

          // Live preview swatch
          BrightnessPreview(
            color: state.color,
            brightness: state.brightness,
          ),

          const SizedBox(height: 40),

          // Percentage readout
          Center(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$percent',
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      color: primary,
                      height: 1,
                    ),
                  ),
                  TextSpan(
                    text: '%',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: primary.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Slider row with icons
          Row(
            children: [
              Icon(
                Icons.brightness_low,
                color: Colors.white.withOpacity(0.4),
                size: 22,
              ),
              Expanded(
                child: Slider(
                  value: state.brightness,
                  min: 0.1,
                  max: 1.0,
                  onChanged: notifier.setBrightness,
                ),
              ),
              Icon(
                Icons.brightness_high,
                color: Colors.white.withOpacity(0.9),
                size: 22,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Quick-set buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final pct in [10, 25, 50, 75, 100])
                _QuickButton(
                  label: '$pct%',
                  isActive: percent == pct,
                  onTap: () => notifier.setBrightness(pct / 100),
                ),
            ],
          ),

          if (state.activeEffect != null) ...[
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Text(
                    state.activeEffect!,
                    style: TextStyle(
                      fontSize: 13,
                      color: primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Effect mode',
                    style: TextStyle(
                      fontSize: 11,
                      color: primary.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        height: 36,
        decoration: BoxDecoration(
          color: isActive ? primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? primary : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}
