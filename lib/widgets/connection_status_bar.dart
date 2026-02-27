import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/preset.dart';
import '../providers/device_provider.dart';
import '../providers/preset_provider.dart';

class ConnectionStatusBar extends ConsumerWidget {
  const ConnectionStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceProvider);
    final modeState = ref.watch(modeProvider);

    final connected = deviceState.connectedDevice;
    final isConnected = connected != null;

    // Resolve the active mode name from the mode provider.
    AppMode? activeMode;
    if (modeState.activeId != null) {
      try {
        activeMode =
            kModes.firstWhere((m) => m.id == modeState.activeId!);
      } catch (_) {}
    }
    final modeLabel = activeMode?.name ?? 'Solid color';

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: isConnected
            ? _ConnectedBar(
                key: const ValueKey('connected'),
                modeLabel: modeLabel,
              )
            : const _DisconnectedBar(key: ValueKey('disconnected')),
      ),
    );
  }
}

class _ConnectedBar extends StatelessWidget {
  final String modeLabel;

  const _ConnectedBar({
    super.key,
    required this.modeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF4CAF50),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Connected',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.tune,
          size: 12,
          color: Colors.white.withOpacity(0.5),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            modeLabel,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _DisconnectedBar extends StatelessWidget {
  const _DisconnectedBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Not connected',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
      ],
    );
  }
}
