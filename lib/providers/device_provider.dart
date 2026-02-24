import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ble_device.dart';

class DeviceState {
  final List<BleDevice> knownDevices;
  final List<BleDevice> discoveredDevices;
  final bool isScanning;

  const DeviceState({
    required this.knownDevices,
    required this.discoveredDevices,
    required this.isScanning,
  });

  /// The currently connected device, if any.
  BleDevice? get connectedDevice {
    try {
      return knownDevices.firstWhere((d) => d.isConnected);
    } catch (_) {
      return null;
    }
  }

  DeviceState copyWith({
    List<BleDevice>? knownDevices,
    List<BleDevice>? discoveredDevices,
    bool? isScanning,
  }) {
    return DeviceState(
      knownDevices: knownDevices ?? this.knownDevices,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}

class DeviceNotifier extends Notifier<DeviceState> {
  Timer? _scanTimer;

  @override
  DeviceState build() {
    ref.onDispose(() {
      _scanTimer?.cancel();
      _scanTimer = null;
    });

    final now = DateTime.now();
    return DeviceState(
      knownDevices: [
        BleDevice(
          id: '8A:3F:2C:D1:4E:AA',
          name: 'LumiBand-3A2F',
          isConnected: true,
          lastSeen: now,
        ),
        BleDevice(
          id: 'B2:11:45:7F:CC:03',
          name: 'LumiBand-12B4',
          isConnected: false,
          lastSeen: now.subtract(const Duration(hours: 2)),
        ),
        BleDevice(
          id: 'F0:9A:D2:38:BB:17',
          name: 'LumiBand-FF01',
          isConnected: false,
          lastSeen: now.subtract(const Duration(days: 1)),
        ),
      ],
      discoveredDevices: const [],
      isScanning: false,
    );
  }

  void connect(String id) {
    // Check discovered devices first
    final discovered = state.discoveredDevices.where((d) => d.id == id).toList();
    if (discovered.isNotEmpty) {
      final device = discovered.first.copyWith(
        isConnected: true,
        lastSeen: DateTime.now(),
      );
      // Disconnect any currently connected known device
      final updatedKnown = state.knownDevices
          .map((d) => d.isConnected ? d.copyWith(isConnected: false) : d)
          .toList();
      // Add to known, remove from discovered
      state = state.copyWith(
        knownDevices: [device, ...updatedKnown],
        discoveredDevices:
            state.discoveredDevices.where((d) => d.id != id).toList(),
      );
      return;
    }

    // Connect existing known device
    state = state.copyWith(
      knownDevices: state.knownDevices.map((d) {
        if (d.id == id) return d.copyWith(isConnected: true, lastSeen: DateTime.now());
        if (d.isConnected) return d.copyWith(isConnected: false);
        return d;
      }).toList(),
    );
  }

  void disconnect(String id) {
    state = state.copyWith(
      knownDevices: state.knownDevices
          .map((d) => d.id == id ? d.copyWith(isConnected: false) : d)
          .toList(),
    );
  }

  void forget(String id) {
    state = state.copyWith(
      knownDevices: state.knownDevices.where((d) => d.id != id).toList(),
    );
  }

  void startScan() {
    _scanTimer?.cancel();
    state = state.copyWith(isScanning: true, discoveredDevices: []);

    // Simulate discovery: first device after 1.5s, second after 2.5s
    _scanTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!state.isScanning) return;
      final alreadyKnownIds = state.knownDevices.map((d) => d.id).toSet();
      final newDevice = BleDevice(
        id: 'C3:8E:51:A2:F0:9B',
        name: 'LumiBand-9C11',
        isConnected: false,
      );
      if (!alreadyKnownIds.contains(newDevice.id)) {
        state = state.copyWith(
          discoveredDevices: [...state.discoveredDevices, newDevice],
        );
      }

      Timer(const Duration(milliseconds: 1000), () {
        if (!state.isScanning) return;
        final newDevice2 = BleDevice(
          id: 'D7:4C:09:6B:E1:22',
          name: 'LumiBand-A4D0',
          isConnected: false,
        );
        if (!alreadyKnownIds.contains(newDevice2.id)) {
          state = state.copyWith(
            discoveredDevices: [...state.discoveredDevices, newDevice2],
          );
        }
      });
    });
  }

  void stopScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    state = state.copyWith(isScanning: false, discoveredDevices: []);
  }

}

final deviceProvider =
    NotifierProvider<DeviceNotifier, DeviceState>(DeviceNotifier.new);
