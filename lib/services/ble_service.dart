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

// ── Connection state ─────────────────────────────────────────────────────────

enum BleConnectionState { disconnected, connecting, connected }

// ── BleService ───────────────────────────────────────────────────────────────

class BleService {
  BluetoothDevice? _device;

  BluetoothCharacteristic? _colorChar;
  BluetoothCharacteristic? _brightChar;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _fxChar;

  StreamSubscription<BluetoothConnectionState>? _connSub;

  final _stateCtrl =
      StreamController<BleConnectionState>.broadcast();

  /// Emits whenever the connection state changes.
  Stream<BleConnectionState> get connectionState => _stateCtrl.stream;

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

    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        _stateCtrl.add(BleConnectionState.connected);
      } else if (state == BluetoothConnectionState.disconnected) {
        _device = null;
        _colorChar = _brightChar = _cmdChar = _fxChar = null;
        _stateCtrl.add(BleConnectionState.disconnected);
      }
    });

    await device.connect(autoConnect: false);

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
    await _device?.disconnect();
    _device = null;
    _colorChar = _brightChar = _cmdChar = _fxChar = null;
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

  /// Tell the device to play a previously uploaded effect slot (0–7).
  Future<void> activateEffect(int slot) async {
    await _cmdChar?.write([0x01, slot], withoutResponse: false);
  }

  /// Activate a built-in preset by index.
  Future<void> activatePreset(int index) async {
    await _cmdChar?.write([0x02, index], withoutResponse: false);
  }

  /// Return to solid-colour display.
  Future<void> setSolidMode() async {
    await _cmdChar?.write([0x03, 0x00], withoutResponse: false);
  }

  // ── Effect upload ─────────────────────────────────────────────────────────
  //
  // Protocol (single FX characteristic, 20-byte packets):
  //   [0x00, slot]           — begin upload for slot 0-7, resets buffer
  //   [0x01, d0..d18]        — append up to 19 bytes of effect data
  //   [0x02, slot]           — commit (Arduino parses and stores)
  //
  // Total effect payload: 8 rows × 15 LEDs × 4 bytes ARGB + 1 settings = 481 bytes
  // → ceil(481 / 19) = 26 data packets

  Future<void> uploadEffect(int slot, EffectData data) async {
    if (_fxChar == null) return;

    final payload = _serializeEffect(data); // 481 bytes

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

  /// Serialise EffectData → 481 bytes.
  ///
  /// Layout: 8 rows × 15 × 4 bytes big-endian ARGB (Color.value), then 1
  /// settings byte (bits 0-3: SoundMode bitmask, bit 4: LoopMode).
  Uint8List _serializeEffect(EffectData data) {
    final bd = ByteData(481);
    int offset = 0;

    for (final row in data.rows) {
      for (final color in row) {
        bd.setUint32(offset, color.value, Endian.big);
        offset += 4;
      }
    }

    int settings = 0;
    for (final m in data.soundModes) {
      settings |= 1 << m.index; // bits 0-3
    }
    if (data.loopMode == LoopMode.bounce) settings |= 0x10; // bit 4
    bd.setUint8(480, settings);

    return bd.buffer.asUint8List();
  }

  void dispose() {
    disconnect();
    _stateCtrl.close();
  }
}

// ── Riverpod provider ────────────────────────────────────────────────────────

final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleService();
  ref.onDispose(svc.dispose);
  return svc;
});
