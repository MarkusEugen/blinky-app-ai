import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ble_service.dart';

class LightingState {
  final Color color;
  final double brightness;
  final String? activeEffect;

  const LightingState({
    required this.color,
    required this.brightness,
    this.activeEffect,
  });

  LightingState copyWith({
    Color? color,
    double? brightness,
    Object? activeEffect = _sentinel,
  }) {
    return LightingState(
      color: color ?? this.color,
      brightness: brightness ?? this.brightness,
      activeEffect: activeEffect == _sentinel
          ? this.activeEffect
          : activeEffect as String?,
    );
  }

  /// The color adjusted for current brightness level.
  Color get displayColor {
    final hslColor = HSLColor.fromColor(color);
    final adjusted = hslColor.withLightness(
      hslColor.lightness * brightness,
    );
    return adjusted.toColor();
  }
}

// Sentinel value so copyWith can distinguish "not passed" from null.
const _sentinel = Object();

class LightingNotifier extends Notifier<LightingState> {
  @override
  LightingState build() {
    return const LightingState(
      color: Color(0xFF7C6BFF),
      brightness: 0.05,
      activeEffect: null,
    );
  }

  void setColor(Color color) {
    state = state.copyWith(color: color, activeEffect: null);
  }

  void setBrightness(double value) {
    state = state.copyWith(brightness: value.clamp(0.05, 0.20));
  }

  /// Sync brightness from a BLE STATUS read — UI update only, no BLE write.
  void setBrightnessFromBle(double value) {
    state = state.copyWith(brightness: value.clamp(0.0, 1.0));
  }

  /// Fire-and-forget BLE brightness write — does NOT update UI state.
  Future<void> sendBrightnessToDevice(double value) async {
    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) return;
    try {
      await ble.setBrightness(value);
    } catch (_) {
      // Best-effort; ignore transient BLE errors.
    }
  }

  void activateEffect(String name) {
    state = state.copyWith(activeEffect: name);
  }

  void clearEffect() {
    state = state.copyWith(activeEffect: null);
  }
}

final lightingProvider =
    NotifierProvider<LightingNotifier, LightingState>(LightingNotifier.new);
