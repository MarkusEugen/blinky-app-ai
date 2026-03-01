import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_provider.dart';
import '../providers/lighting_provider.dart';
import '../widgets/brightness_preview.dart';

class BrightnessScreen extends ConsumerWidget {
  const BrightnessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lightingProvider);
    final deviceState = ref.watch(deviceProvider);
    final notifier = ref.read(lightingProvider.notifier);

    final isConnected = deviceState.connectedDevice != null;
    final percent = (state.brightness * 100).round();
    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isConnected
                ? 'Drag the slider to adjust intensity'
                : 'Connect to a device to control brightness',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),

          // Live preview swatch
          BrightnessPreview(
            color: state.color,
            brightness: state.brightness,
          ),

          const SizedBox(height: 20),

          // Percentage readout
          Center(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$percent',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: isConnected ? primary : primary.withOpacity(0.4),
                      height: 1,
                    ),
                  ),
                  TextSpan(
                    text: '%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isConnected
                          ? primary.withOpacity(0.7)
                          : primary.withOpacity(0.25),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Slider row with icons — range 5 %–25 %
          Row(
            children: [
              Icon(
                Icons.brightness_low,
                color: Colors.white.withOpacity(isConnected ? 0.4 : 0.15),
                size: 22,
              ),
              Expanded(
                child: Slider(
                  value: state.brightness.clamp(0.05, 0.20),
                  min: 0.05,
                  max: 0.20,
                  // onChanged: UI preview; onChangeEnd: BLE write.
                  onChanged: isConnected ? notifier.setBrightness : null,
                  onChangeEnd: isConnected
                      ? (v) => notifier.sendBrightnessToDevice(v)
                      : null,
                ),
              ),
              Icon(
                Icons.brightness_high,
                color: Colors.white.withOpacity(isConnected ? 0.9 : 0.2),
                size: 22,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Quick-set buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final pct in [5, 10, 15, 20])
                _QuickButton(
                  label: '$pct%',
                  isActive: isConnected && percent == pct,
                  isEnabled: isConnected,
                  onTap: isConnected
                      ? () {
                          final v = pct / 100;
                          notifier.setBrightness(v);
                          notifier.sendBrightnessToDevice(v);
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _QuickButton({
    required this.label,
    required this.isActive,
    required this.isEnabled,
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
            color: isActive
                ? primary
                : Colors.white.withOpacity(isEnabled ? 0.12 : 0.05),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive
                  ? Colors.white
                  : Colors.white.withOpacity(isEnabled ? 0.54 : 0.2),
            ),
          ),
        ),
      ),
    );
  }
}
