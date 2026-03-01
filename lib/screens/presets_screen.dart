import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/preset.dart';
import '../providers/custom_effect_provider.dart';
import '../providers/device_provider.dart';
import '../providers/preset_provider.dart';
import '../services/ble_service.dart';

class PresetsScreen extends ConsumerWidget {
  /// Called when the user taps Custom Effects and no effects have been uploaded.
  final VoidCallback onShowEffects;

  const PresetsScreen({super.key, required this.onShowEffects});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeState = ref.watch(modeProvider);
    final deviceState = ref.watch(deviceProvider);
    final customState = ref.watch(customEffectProvider);
    final notifier = ref.read(modeProvider.notifier);

    final isConnected = deviceState.connectedDevice != null;
    final hasUploaded = customState.uploadedIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isConnected
                    ? 'Tap a mode to activate it on your band'
                    : 'Connect to a device to control the mode',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),

        // ── Mode list ───────────────────────────────────────────
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: kModes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final mode = kModes[i];
              // Custom Effects row is always enabled so the user can always
              // create/edit effects even without a BLE connection.
              final rowEnabled = isConnected || mode.isCustomEffects;
              return _ModeCard(
                mode: mode,
                isActive: modeState.activeId == mode.id,
                isEnabled: rowEnabled,
                onTap: rowEnabled
                    ? (mode.isCustomEffects
                        ? () => _handleCustomEffects(ref, isConnected, hasUploaded)
                        : () => notifier.activate(mode))
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleCustomEffects(WidgetRef ref, bool isConnected, bool hasUploaded) {
    if (isConnected && hasUploaded) {
      // Re-activate custom mode on the band with the previously uploaded effects.
      final uploadedCount = ref.read(customEffectProvider).uploadedIds.length;
      ref.read(bleServiceProvider).activateCustomMode(uploadedCount);
      ref.read(modeProvider.notifier).setCustomEffectsActive();
    } else {
      // No effects uploaded yet — navigate to the Effects tab.
      onShowEffects();
    }
  }
}

// ─── Mode card ────────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final AppMode mode;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _ModeCard({
    required this.mode,
    required this.isActive,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;

    final borderColor = isActive
        ? primary
        : Colors.white.withOpacity(0.08);
    final bgColor = isActive
        ? primary.withOpacity(0.12)
        : surface;

    return AnimatedOpacity(
      opacity: isEnabled ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isActive ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: primary.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Icon
                Text(mode.icon, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 16),

                // Name + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mode.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.45),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _ColorSwatches(colors: mode.colors),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Right badge
                if (isActive)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        size: 16, color: Colors.white),
                  )
                else if (mode.isCustomEffects)
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(0.3),
                    size: 20,
                  )
                else
                  const SizedBox(width: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  final List<Color> colors;
  const _ColorSwatches({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: colors.map((c) {
        return Container(
          width: 16,
          height: 8,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }).toList(),
    );
  }
}
