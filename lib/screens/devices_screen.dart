import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ble_device.dart';
import '../providers/device_provider.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deviceProvider);
    final notifier = ref.read(deviceProvider.notifier);

    return CustomScrollView(
      slivers: [
        // ── Title ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage and connect LumiBand devices',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // ── Known Devices header ────────────────────────────────
        SliverToBoxAdapter(
          child: _SectionHeader(
            label: 'KNOWN DEVICES',
            count: state.knownDevices.length,
          ),
        ),

        // ── Known Devices list ──────────────────────────────────
        if (state.knownDevices.isEmpty)
          const SliverToBoxAdapter(child: _EmptyKnownDevices())
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final device = state.knownDevices[i];
                return _KnownDeviceRow(
                  device: device,
                  onTap: () => device.isConnected
                      ? notifier.disconnect(device.id)
                      : notifier.connect(device.id),
                  onForget: () => notifier.forget(device.id),
                );
              },
              childCount: state.knownDevices.length,
            ),
          ),

        // ── Nearby Devices header ───────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _SectionHeader(
              label: 'NEARBY DEVICES',
              trailing: state.isScanning
                  ? _ScanningIndicator()
                  : null,
            ),
          ),
        ),

        // ── Discovered list ─────────────────────────────────────
        if (state.isScanning && state.discoveredDevices.isEmpty)
          const SliverToBoxAdapter(child: _SearchingRow())
        else if (state.discoveredDevices.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final device = state.discoveredDevices[i];
                return _DiscoveredDeviceRow(
                  device: device,
                  onAdd: () => notifier.connect(device.id),
                );
              },
              childCount: state.discoveredDevices.length,
            ),
          )
        else if (!state.isScanning)
          const SliverToBoxAdapter(child: _NearbyHint()),

        // ── Scan button (disabled when BT is off) ──────────────
        SliverToBoxAdapter(
          child: StreamBuilder<BluetoothAdapterState>(
            stream: FlutterBluePlus.adapterState,
            initialData: BluetoothAdapterState.unknown,
            builder: (context, snapshot) {
              final btOn = snapshot.data == BluetoothAdapterState.on;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!btOn && !state.isScanning) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.bluetooth_disabled,
                                size: 18,
                                color: Colors.orange.withOpacity(0.8)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Bluetooth is turned off. Enable it in Settings to scan for devices.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.withOpacity(0.9),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    state.isScanning
                        ? _StopScanButton(onTap: notifier.stopScan)
                        : _ScanButton(
                            onTap: btOn ? notifier.startScan : null),
                  ],
                ),
              );
            },
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

// ─── Section header ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int? count;
  final Widget? trailing;

  const _SectionHeader({required this.label, this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.4),
              letterSpacing: 1.2,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.4),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─── Known device row ──────────────────────────────────────────────────────

class _KnownDeviceRow extends StatelessWidget {
  final BleDevice device;
  final VoidCallback onTap;
  final VoidCallback onForget;

  const _KnownDeviceRow({
    required this.device,
    required this.onTap,
    required this.onForget,
  });

  String _lastSeenLabel() {
    if (device.isConnected) return 'Connected';
    final seen = device.lastSeen;
    if (seen == null) return 'Unknown';
    final diff = DateTime.now().difference(seen);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Dismissible(
      key: ValueKey(device.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFFE53935),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
      ),
      onDismissed: (_) => onForget(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              // BT icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: device.isConnected
                      ? primary.withOpacity(0.15)
                      : Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bluetooth,
                  size: 20,
                  color: device.isConnected
                      ? primary
                      : Colors.white.withOpacity(0.35),
                ),
              ),
              const SizedBox(width: 14),
              // Name + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: device.isConnected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: device.isConnected
                            ? Colors.white
                            : Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _lastSeenLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        color: device.isConnected
                            ? const Color(0xFF4CAF50)
                            : Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ],
                ),
              ),
              // Trailing chip or icon
              if (device.isConnected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF4CAF50).withOpacity(0.4)),
                  ),
                  child: const Text(
                    'Connected',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.white.withOpacity(0.2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Discovered device row ─────────────────────────────────────────────────

class _DiscoveredDeviceRow extends StatelessWidget {
  final BleDevice device;
  final VoidCallback onAdd;

  const _DiscoveredDeviceRow({required this.device, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bluetooth_searching, size: 20, color: primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Available',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.35),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: Icon(Icons.add_circle_outline, color: primary),
            tooltip: 'Connect',
          ),
        ],
      ),
    );
  }
}

// ─── Scan / Stop buttons ───────────────────────────────────────────────────

class _ScanButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _ScanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.search, size: 18),
        label: const Text('Scan for Devices'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          disabledBackgroundColor: Colors.white.withOpacity(0.06),
        ),
      ),
    );
  }
}

class _StopScanButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StopScanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          side: BorderSide(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Stop Scanning'),
          ],
        ),
      ),
    );
  }
}

// ─── Empty / hint states ───────────────────────────────────────────────────

class _EmptyKnownDevices extends StatelessWidget {
  const _EmptyKnownDevices();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.bluetooth_disabled,
              size: 36, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 8),
          Text(
            'No saved devices',
            style: TextStyle(
                fontSize: 13, color: Colors.white.withOpacity(0.3)),
          ),
        ],
      ),
    );
  }
}

class _SearchingRow extends StatelessWidget {
  const _SearchingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Searching for devices…',
            style: TextStyle(
                fontSize: 13, color: Colors.white.withOpacity(0.35)),
          ),
        ],
      ),
    );
  }
}

class _NearbyHint extends StatelessWidget {
  const _NearbyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        'Tap "Scan for Devices" to discover nearby LumiBands',
        style:
            TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.25)),
      ),
    );
  }
}

class _ScanningIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Scanning',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
