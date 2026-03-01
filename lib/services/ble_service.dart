import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/effect_data.dart';

// ── UUIDs — must match the Arduino sketch exactly ───────────────────────────
const _kServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const _kColorUuid   = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
const _kBrightUuid  = 'beb5483f-36e1-4688-b7f5-ea07361b26a8';
const _kCmdUuid     = 'beb54840-36e1-4688-b7f5-ea07361b26a8';
const _kFxUuid      = 'beb54841-36e1-4688-b7f5-ea07361b26a8';
const _kStatusUuid  = 'beb54842-36e1-4688-b7f5-ea07361b26a8';

// ── Connection state ─────────────────────────────────────────────────────────

enum BleConnectionState { disconnected, connecting, connected }

// ── BleService ───────────────────────────────────────────────────────────────

class BleService {
  BluetoothDevice? _device;

  BluetoothCharacteristic? _colorChar;
  BluetoothCharacteristic? _brightChar;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _fxChar;
  BluetoothCharacteristic? _statusChar;

  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _statusSub;

  final _stateCtrl =
      StreamController<BleConnectionState>.broadcast();
  final _statusCtrl = StreamController<List<int>>.broadcast();

  /// Emits whenever the connection state changes.
  Stream<BleConnectionState> get connectionState => _stateCtrl.stream;

  /// Emits 2-byte STATUS updates from the Arduino [modeIndex, bright].
  Stream<List<int>> get statusStream => _statusCtrl.stream;

  bool get isConnected => _device != null;

  // ── Scanning ─────────────────────────────────────────────────────────────

  /// Live scan results — filter by the LumiBand service UUID.
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  bool get isScanning => FlutterBluePlus.isScanningNow;

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    return FlutterBluePlus.startScan(
      withServices: [Guid(_kServiceUuid)],
      timeout: timeout,
    );
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  // ── Connect / disconnect ──────────────────────────────────────────────────

  Future<void> connect(BluetoothDevice device) async {
    await disconnect(); // clean up any previous connection

    _stateCtrl.add(BleConnectionState.connecting);
    _device = device;

    // Guard against the spurious 'disconnected' event that iOS CoreBluetooth
    // emits immediately when subscribing to connectionState on a fresh
    // BluetoothDevice.fromId() object (i.e. a device loaded from storage on
    // app restart rather than discovered via a live scan).  We only forward a
    // 'disconnected' event once the device has actually been seen as connected.
    bool didConnect = false;

    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        didConnect = true;
        _stateCtrl.add(BleConnectionState.connected);
      } else if (state == BluetoothConnectionState.disconnected) {
        if (!didConnect) return; // ignore spurious initial state
        didConnect = false;
        _device = null;
        _statusSub?.cancel();
        _statusSub = null;
        _colorChar = _brightChar = _cmdChar = _fxChar = _statusChar = null;
        _stateCtrl.add(BleConnectionState.disconnected);
      }
    });

    await device.connect(autoConnect: false, timeout: const Duration(seconds: 5));

    // Request a larger MTU so effect chunks can be bigger.
    // nRF52840 (Nano 33 BLE) supports up to 512.
    try {
      await device.requestMtu(512);
    } catch (_) {
      // MTU negotiation is best-effort; proceed with default.
    }

    await _discoverCharacteristics(device);
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connSub = null;
    await _statusSub?.cancel();
    _statusSub = null;
    await _device?.disconnect();
    _device = null;
    _colorChar = _brightChar = _cmdChar = _fxChar = _statusChar = null;
  }

  Future<void> _discoverCharacteristics(BluetoothDevice device) async {
    final services = await device.discoverServices();

    final svc = services.firstWhere(
      (s) => s.serviceUuid == Guid(_kServiceUuid),
      orElse: () => throw StateError('LumiBand service not found'),
    );

    for (final c in svc.characteristics) {
      final uuid = c.characteristicUuid.toString().toLowerCase();
      if (uuid == _kColorUuid)  _colorChar  = c;
      if (uuid == _kBrightUuid) _brightChar = c;
      if (uuid == _kCmdUuid)    _cmdChar    = c;
      if (uuid == _kFxUuid)     _fxChar     = c;
      if (uuid == _kStatusUuid) {
        _statusChar = c;
        try {
          await c.setNotifyValue(true);
          _statusSub = c.onValueReceived.listen(_statusCtrl.add);
        } catch (_) {
          // Notifications not supported — read-only fallback still available.
        }
      }
    }
  }

  /// Read the current STATUS value — 2 bytes: [modeIndex, bright].
  /// Returns null if not connected or characteristic not found.
  Future<List<int>?> readStatus() async {
    if (_statusChar == null) return null;
    try {
      return await _statusChar!.read();
    } catch (_) {
      return null;
    }
  }

  // ── Commands ──────────────────────────────────────────────────────────────

  /// Send a solid RGB colour to the strip.
  Future<void> setColor(Color color) async {
    await _colorChar?.write(
      [color.red, color.green, color.blue],
      withoutResponse: false,
    );
  }

  /// value: 0.0 (off) – 1.0 (full brightness).
  Future<void> setBrightness(double value) async {
    final v = (value * 255).round().clamp(0, 255);
    await _brightChar?.write([v], withoutResponse: false);
  }

  /// Activate a built-in mode by index (0 = Classic … 4 = Dim).
  Future<void> activatePreset(int index) async {
    await _cmdChar?.write([0x02, index], withoutResponse: false);
  }

  /// Activate Custom mode and tell the Arduino how many uploaded
  /// effect slots to cycle through.
  Future<void> activateCustomMode(int count) async {
    await _cmdChar?.write([0x02, 5, count], withoutResponse: false);
  }

  // ── Effect upload ─────────────────────────────────────────────────────────
  //
  // Protocol (single FX characteristic, 20-byte packets):
  //   [0x00, slot]           — begin upload for slot 0-7, resets buffer
  //   [0x01, d0..d18]        — append up to 19 bytes of effect data
  //   [0x02, slot]           — commit (Arduino parses and stores)
  //
  // Total effect payload: 15 rows × 15 LEDs × 2 bytes RGB565 + 1 settings + 2 rowMs = 453 bytes
  // → ceil(453 / 19) = 24 data packets

  Future<void> uploadEffect(int slot, EffectData data) async {
    if (_fxChar == null) return;

    final payload = _serializeEffect(data); // 453 bytes

    // 1. Begin
    await _fxChar!.write([0x00, slot], withoutResponse: false);

    // 2. Data chunks
    const chunkSize = 19;
    for (int i = 0; i < payload.length; i += chunkSize) {
      final end = min(i + chunkSize, payload.length);
      final chunk = <int>[0x01, ...payload.sublist(i, end)];
      await _fxChar!.write(chunk, withoutResponse: false);
    }

    // 3. Commit
    await _fxChar!.write([0x02, slot], withoutResponse: false);
  }

  /// Serialise EffectData → 453 bytes (RGB565).
  ///
  /// Layout:
  ///   bytes   0–449  15 rows × 15 LEDs × 2 bytes big-endian RGB565
  ///   byte  450      settings (bits 0-3: SoundMode bitmask, bit 4: LoopMode)
  ///   bytes 451–452  rowMs big-endian uint16 (row advance interval, 20–1000 ms)
  Uint8List _serializeEffect(EffectData data) {
    final bd = ByteData(453);
    int offset = 0;

    for (final row in data.rows) {
      for (final color in row) {
        final r5 = (color.red   >> 3) & 0x1F;
        final g5 = (color.green >> 3) & 0x1F;
        final b5 = (color.blue  >> 3) & 0x1F;
        bd.setUint16(offset, (r5 << 11) | (g5 << 5) | b5, Endian.big);
        offset += 2;
      }
    }

    int settings = 0;
    for (final m in data.soundModes) {
      settings |= 1 << m.index; // bits 0-3
    }
    if (data.loopMode == LoopMode.bounce) settings |= 0x10; // bit 4
    bd.setUint8(450, settings);

    bd.setUint16(451, data.rowMs.clamp(20, 1000), Endian.big);

    return bd.buffer.asUint8List();
  }

  void dispose() {
    disconnect();
    _stateCtrl.close();
    _statusCtrl.close();
  }
}

// ── Riverpod provider ────────────────────────────────────────────────────────

final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleService();
  ref.onDispose(svc.dispose);
  return svc;
});
