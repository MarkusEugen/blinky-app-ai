import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/preset.dart';
import '../services/ble_service.dart';

const _sentinel = Object();

// ── State ─────────────────────────────────────────────────────────────────────

class ModeState {
  /// ID of the AppMode currently active on the Arduino.
  /// null = solid colour / unknown (no mode command sent yet).
  final String? activeId;

  const ModeState({this.activeId});

  ModeState copyWith({Object? activeId = _sentinel}) => ModeState(
        activeId: activeId == _sentinel ? this.activeId : activeId as String?,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ModeNotifier extends Notifier<ModeState> {
  @override
  ModeState build() => const ModeState();

  /// Called after BLE connect (or STATUS notify) to sync the active mode.
  void setActiveFromBle(int bleIndex) {
    final mode = modeFromBleIndex(bleIndex);
    state = state.copyWith(activeId: mode?.id);
  }

  /// Tapping a mode row: send [0x02, bleIndex] to Arduino immediately.
  /// No-op if not connected or if the mode is Custom Effects
  /// (those are activated via the upload flow).
  Future<void> activate(AppMode mode) async {
    if (mode.isCustomEffects) return;
    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) return;
    await ble.activatePreset(mode.bleIndex);
    state = state.copyWith(activeId: mode.id);
  }

  /// Mark Custom Effects as active (called after a successful upload).
  void setCustomEffectsActive() {
    state = state.copyWith(activeId: 'custom');
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final modeProvider =
    NotifierProvider<ModeNotifier, ModeState>(ModeNotifier.new);

// Backward-compat alias so any file still using presetProvider keeps compiling.
final presetProvider = modeProvider;
