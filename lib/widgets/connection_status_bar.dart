import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_provider.dart';
import '../providers/lighting_provider.dart';

class ConnectionStatusBar extends ConsumerWidget {
  const ConnectionStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceProvider);
    final lightingState = ref.watch(lightingProvider);

    final connected = deviceState.connectedDevice;
    final isConnected = connected != null;

    final effectLabel = lightingState.activeEffect ?? 'Solid color';

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
                deviceName: connected.name,
                effectLabel: effectLabel,
              )
            : const _DisconnectedBar(key: ValueKey('disconnected')),
      ),
    );
  }
}

class _ConnectedBar extends StatelessWidget {
  final String deviceName;
  final String effectLabel;

  const _ConnectedBar({
    super.key,
    required this.deviceName,
    required this.effectLabel,
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
        Text(
          'Connected · $deviceName',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.auto_awesome,
          size: 12,
          color: Colors.white.withOpacity(0.5),
        ),
        const SizedBox(width: 4),
        Text(
          effectLabel,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.6),
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
