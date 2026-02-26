import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ble_device.dart';
import '../services/ble_service.dart';
import 'lighting_provider.dart';
import 'preset_provider.dart';

// ── State (unchanged shape — screen requires no edits) ────────────────────────

class DeviceState {
  final List<BleDevice> knownDevices;
  final List<BleDevice> discoveredDevices;
  final bool isScanning;

  const DeviceState({
    required this.knownDevices,
    required this.discoveredDevices,
    required this.isScanning,
  });

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

const _kDeviceStorageKey = 'known_devices_v1';

// ── Notifier ─────────────────────────────────────────────────────────────────

class DeviceNotifier extends Notifier<DeviceState> {
  /// Maps BleDevice.id → real BluetoothDevice, populated during scan.
  final Map<String, BluetoothDevice> _deviceMap = {};

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;
  StreamSubscription<BleConnectionState>? _connSub;
  StreamSubscription<List<int>>? _statusSub;

  @override
  DeviceState build() {
    final ble = ref.read(bleServiceProvider);

    ref.onDispose(() {
      _scanSub?.cancel();
      _isScanSub?.cancel();
      _connSub?.cancel();
      _statusSub?.cancel();
    });

    // React to unexpected disconnections (device went out of range, etc.)
    _connSub = ble.connectionState.listen((s) {
      if (s == BleConnectionState.disconnected) {
        _statusSub?.cancel();
        _statusSub = null;
        state = state.copyWith(
          knownDevices: state.knownDevices
              .map((d) => d.isConnected ? d.copyWith(isConnected: false) : d)
              .toList(),
        );
      }
    });

    // Mirror flutter_blue_plus scanning state so the UI stays in sync
    // even when the scan timeout fires naturally.
    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && state.isScanning) {
        _scanSub?.cancel();
        _scanSub = null;
        state = state.copyWith(isScanning: false);
      }
    });

    // Async load — replaces empty list once storage is read.
    _loadDevices();

    return const DeviceState(
      knownDevices: [],
      discoveredDevices: [],
      isScanning: false,
    );
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDeviceStorageKey);
    if (raw == null) return;
    try {
      final devices = (jsonDecode(raw) as List)
          .map((e) => BleDevice.fromJson(e as Map<String, dynamic>))
          .toList();

      // Pre-populate _deviceMap so known devices can be connected without
      // requiring a fresh scan.
      for (final d in devices) {
        _deviceMap[d.id] = BluetoothDevice.fromId(d.id);
      }

      state = state.copyWith(knownDevices: devices);
    } catch (_) {
      // Corrupt data — start fresh.
    }
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kDeviceStorageKey,
      jsonEncode(state.knownDevices.map((d) => d.toJson()).toList()),
    );
  }

  // ── Scan ───────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    final ble = ref.read(bleServiceProvider);

    await _scanSub?.cancel();
    _scanSub = null;
    state = state.copyWith(isScanning: true, discoveredDevices: []);

    try {
      await ble.startScan(); // filters by service UUID — only LumiBands appear
    } catch (_) {
      state = state.copyWith(isScanning: false);
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final knownIds = state.knownDevices.map((d) => d.id).toSet();
      final seen = <String>{};
      final discovered = <BleDevice>[];

      for (final r in results) {
        final id = r.device.remoteId.str;
        if (knownIds.contains(id)) continue;
        if (!seen.add(id)) continue; // deduplicate within this emission

        // Prefer the name cached by the OS; fall back to the advertised local name.
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName
                : 'LumiBand-${id.replaceAll(':', '').substring(0, 4)}';

        _deviceMap[id] = r.device;
        discovered.add(BleDevice(id: id, name: name, isConnected: false));
      }

      state = state.copyWith(discoveredDevices: discovered);
    });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await ref.read(bleServiceProvider).stopScan();
    state = state.copyWith(isScanning: false, discoveredDevices: []);
  }

  // ── Connect / disconnect / forget ──────────────────────────────────────────

  Future<void> connect(String id) async {
    final ble = ref.read(bleServiceProvider);
    final btDevice = _deviceMap[id];
    if (btDevice == null) return;

    // Find the source record (discovered or existing known).
    final source = state.discoveredDevices.where((d) => d.id == id).isNotEmpty
        ? state.discoveredDevices.firstWhere((d) => d.id == id)
        : state.knownDevices.where((d) => d.id == id).isNotEmpty
            ? state.knownDevices.firstWhere((d) => d.id == id)
            : BleDevice(id: id, name: btDevice.platformName, isConnected: false);

    // Optimistically update UI before awaiting the actual connection.
    final updatedKnown = state.knownDevices
        .map((d) => d.isConnected ? d.copyWith(isConnected: false) : d)
        .toList();

    final alreadyKnown = updatedKnown.any((d) => d.id == id);
    final connected = source.copyWith(isConnected: true, lastSeen: DateTime.now());

    state = state.copyWith(
      knownDevices: alreadyKnown
          ? updatedKnown.map((d) => d.id == id ? connected : d).toList()
          : [connected, ...updatedKnown],
      discoveredDevices: state.discoveredDevices.where((d) => d.id != id).toList(),
    );
    _saveDevices(); // persist before awaiting connection

    try {
      await ble.connect(btDevice);

      // Sync mode + brightness from the Arduino STATUS characteristic.
      final status = await ble.readStatus();
      if (status != null && status.length >= 2) {
        ref.read(modeProvider.notifier).setActiveFromBle(status[0]);
        ref.read(lightingProvider.notifier).setBrightnessFromBle(status[1] / 255);
      }

      // Subscribe to ongoing STATUS notifications.
      _statusSub?.cancel();
      _statusSub = ble.statusStream.listen((s) {
        if (s.length >= 2) {
          ref.read(modeProvider.notifier).setActiveFromBle(s[0]);
          ref.read(lightingProvider.notifier).setBrightnessFromBle(s[1] / 255);
        }
      });
    } catch (_) {
      // Revert optimistic update on connection failure.
      _statusSub?.cancel();
      _statusSub = null;
      state = state.copyWith(
        knownDevices: state.knownDevices
            .map((d) => d.id == id ? d.copyWith(isConnected: false) : d)
            .toList(),
      );
    }
  }

  Future<void> disconnect(String id) async {
    await ref.read(bleServiceProvider).disconnect();
    state = state.copyWith(
      knownDevices: state.knownDevices
          .map((d) => d.id == id ? d.copyWith(isConnected: false) : d)
          .toList(),
    );
  }

  void forget(String id) {
    if (state.knownDevices.any((d) => d.id == id && d.isConnected)) {
      ref.read(bleServiceProvider).disconnect();
    }
    _deviceMap.remove(id);
    state = state.copyWith(
      knownDevices: state.knownDevices.where((d) => d.id != id).toList(),
    );
    _saveDevices();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final deviceProvider =
    NotifierProvider<DeviceNotifier, DeviceState>(DeviceNotifier.new);
