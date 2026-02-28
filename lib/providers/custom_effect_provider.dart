import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/custom_effect.dart';
import '../models/effect_data.dart';
import '../services/ble_service.dart';
import 'device_provider.dart';
import 'preset_provider.dart';

// Sentinel for nullable copyWith fields.
const _sentinel = Object();

const _kStorageKey = 'custom_effects_v2';
const _kUploadedKeyPrefix = 'uploaded_effect_ids_v1_'; // + device BLE ID

class CustomEffectState {
  final List<CustomEffect> effects;
  final Set<String> selectedIds;
  final Set<String> uploadedIds;
  final bool isUploading;
  final String? editingId;         // null = list view
  final String? previewingListId;  // effect being previewed from the list
  final int previewRow;            // 0..kEffectRows-1
  final bool isPreviewing;

  const CustomEffectState({
    required this.effects,
    required this.selectedIds,
    required this.uploadedIds,
    required this.isUploading,
    this.editingId,
    this.previewingListId,
    this.previewRow = 0,
    this.isPreviewing = false,
  });

  CustomEffectState copyWith({
    List<CustomEffect>? effects,
    Set<String>? selectedIds,
    Set<String>? uploadedIds,
    bool? isUploading,
    Object? editingId = _sentinel,
    Object? previewingListId = _sentinel,
    int? previewRow,
    bool? isPreviewing,
  }) {
    return CustomEffectState(
      effects: effects ?? this.effects,
      selectedIds: selectedIds ?? this.selectedIds,
      uploadedIds: uploadedIds ?? this.uploadedIds,
      isUploading: isUploading ?? this.isUploading,
      editingId: editingId == _sentinel ? this.editingId : editingId as String?,
      previewingListId: previewingListId == _sentinel
          ? this.previewingListId
          : previewingListId as String?,
      previewRow: previewRow ?? this.previewRow,
      isPreviewing: isPreviewing ?? this.isPreviewing,
    );
  }

  /// The effect currently open in the editor, or null.
  CustomEffect? get editingEffect =>
      editingId == null ? null : effects.firstWhere((e) => e.id == editingId!);

  /// The effect being previewed from the list, or null.
  CustomEffect? get listPreviewEffect => previewingListId == null
      ? null
      : effects.firstWhere((e) => e.id == previewingListId!);
}

class CustomEffectNotifier extends Notifier<CustomEffectState> {
  Timer? _previewTimer;
  bool _previewForward = true;

  /// Returns the BLE ID of the currently connected device, or null.
  String? get _connectedDeviceId =>
      ref.read(deviceProvider).connectedDevice?.id;

  @override
  CustomEffectState build() {
    ref.onDispose(() {
      _previewTimer?.cancel();
      _previewTimer = null;
    });

    // Re-evaluate when the connected device changes so uploadedIds
    // are loaded for the correct Arduino.
    ref.watch(deviceProvider.select((s) => s.connectedDevice?.id));

    // Async load — replaces defaults once storage is read.
    _loadEffects();

    return CustomEffectState(
      effects: _defaultEffects(),
      selectedIds: const {},
      uploadedIds: const {},
      isUploading: false,
    );
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  static List<CustomEffect> _defaultEffects() => [
        CustomEffect(id: 'effect_1', name: 'Rainbow',  data: _rainbowEffect()),
        CustomEffect(id: 'effect_2', name: 'Fire',     data: _fireEffect()),
        CustomEffect(id: 'effect_3', name: 'Ocean',    data: _oceanEffect()),
        CustomEffect(id: 'effect_4', name: 'Candy',    data: _candyEffect()),
        CustomEffect(id: 'effect_5', name: 'Sunset',   data: _sunsetEffect()),
        CustomEffect(id: 'effect_6', name: 'Forest',   data: _forestEffect()),
        CustomEffect(id: 'effect_7', name: 'Cosmic',   data: _cosmicEffect()),
        CustomEffect(id: 'effect_8', name: 'Ice',      data: _iceEffect()),
      ];

  // ── Colour helpers ────────────────────────────────────────────────────────

  static Color _hsv(double h, double s, double v) =>
      HSVColor.fromAHSV(1.0, h % 360, s, v).toColor();

  // ── Default effect patterns ────────────────────────────────────────────────
  // Each generator produces a true 2D 15×15 matrix where every pixel's colour
  // depends on both its row and column position.

  /// Rainbow: diagonal hue sweep — hue shifts across both row and column.
  static EffectData _rainbowEffect() {
    final rows = List.generate(kEffectRows, (r) => List.generate(
      kMaxLed,
      (i) => _hsv(r * 24.0 + i * 20.0, 1.0, 1.0),
    ));
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.loop, rowMs: 100);
  }

  /// Fire: 2D flame field — hue 0–50, brightness varies with sine waves.
  static EffectData _fireEffect() {
    final rows = List.generate(kEffectRows, (r) {
      final rn = r / (kEffectRows - 1);  // 0..1
      return List.generate(kMaxLed, (i) {
        final cn = i / (kMaxLed - 1);    // 0..1
        final hue = 50.0 * rn * (0.5 + 0.5 * sin(cn * pi * 3));
        final val = 0.6 + 0.4 * sin(rn * pi * 2 + cn * pi);
        final sat = 0.85 + 0.15 * cos(cn * pi * 2 + rn * pi);
        return _hsv(hue, sat.clamp(0.0, 1.0), val.clamp(0.0, 1.0));
      });
    });
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.bounce, rowMs: 80);
  }

  /// Ocean: 2D wave — hue oscillates between 165–215 with sine ripples.
  static EffectData _oceanEffect() {
    final rows = List.generate(kEffectRows, (r) {
      final rn = r / (kEffectRows - 1);
      return List.generate(kMaxLed, (i) {
        final cn = i / (kMaxLed - 1);
        final wave = sin(rn * pi * 3 + cn * pi * 2);
        final hue = 190.0 + 25.0 * wave;
        final sat = 0.7 + 0.3 * cos(cn * pi * 2 - rn * pi);
        final val = 0.6 + 0.4 * sin(rn * pi + cn * pi * 3);
        return _hsv(hue, sat.clamp(0.0, 1.0), val.clamp(0.0, 1.0));
      });
    });
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.loop, rowMs: 180);
  }

  /// Candy: 2D diagonal stripes of vivid hues with per-pixel variation.
  static EffectData _candyEffect() {
    const hues = [330.0, 180.0, 300.0, 90.0, 15.0, 270.0, 55.0, 210.0,
                  0.0, 150.0, 45.0, 240.0, 350.0, 120.0, 195.0];
    final rows = List.generate(kEffectRows, (r) => List.generate(
      kMaxLed,
      (i) {
        final idx = (r + i) % hues.length;
        final sat = 0.85 + 0.15 * sin(i * pi / (kMaxLed - 1));
        return _hsv(hues[idx], sat, 1.0);
      },
    ));
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.loop, rowMs: 150);
  }

  /// Sunset: 2D warm colour field — scarlet through orange fading to violet.
  static EffectData _sunsetEffect() {
    final rows = List.generate(kEffectRows, (r) {
      final rn = r / (kEffectRows - 1);
      return List.generate(kMaxLed, (i) {
        final cn = i / (kMaxLed - 1);
        // Hue sweeps 0–40 across columns, dips into purple at high rows
        final hue = (40.0 * cn + 320.0 * rn * rn) % 360;
        final sat = 0.8 + 0.2 * sin(cn * pi + rn * pi);
        final val = 0.7 + 0.3 * cos(rn * pi * 0.5 + cn * pi * 2);
        return _hsv(hue, sat.clamp(0.0, 1.0), val.clamp(0.0, 1.0));
      });
    });
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.bounce, rowMs: 220);
  }

  /// Forest: 2D canopy — green hues with dappled light brightness.
  static EffectData _forestEffect() {
    final rows = List.generate(kEffectRows, (r) {
      final rn = r / (kEffectRows - 1);
      return List.generate(kMaxLed, (i) {
        final cn = i / (kMaxLed - 1);
        final hue = 80.0 + 60.0 * sin(rn * pi * 2 + cn * pi);
        final sat = 0.7 + 0.3 * cos(cn * pi * 3 + rn * pi * 1.5);
        final val = 0.4 + 0.6 * (0.5 + 0.5 * sin(rn * pi * 3 + cn * pi * 4));
        return _hsv(hue, sat.clamp(0.0, 1.0), val.clamp(0.0, 1.0));
      });
    });
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.loop, rowMs: 200);
  }

  /// Cosmic: 2D nebula — violet/indigo/pink with swirling brightness.
  static EffectData _cosmicEffect() {
    final rows = List.generate(kEffectRows, (r) {
      final rn = r / (kEffectRows - 1);
      return List.generate(kMaxLed, (i) {
        final cn = i / (kMaxLed - 1);
        final hue = 250.0 + 70.0 * sin(rn * pi * 2 + cn * pi * 1.5);
        final sat = 0.5 + 0.5 * cos(cn * pi * 2 + rn * pi * 3);
        final val = 0.6 + 0.4 * sin(rn * pi * 1.5 + cn * pi * 2.5);
        return _hsv(hue, sat.clamp(0.0, 1.0), val.clamp(0.0, 1.0));
      });
    });
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.bounce, rowMs: 160);
  }

  /// Ice: 2D crystalline — white to arctic blue with shimmer.
  static EffectData _iceEffect() {
    final rows = List.generate(kEffectRows, (r) {
      final rn = r / (kEffectRows - 1);
      return List.generate(kMaxLed, (i) {
        final cn = i / (kMaxLed - 1);
        final hue = 195.0 + 15.0 * sin(rn * pi * 2 + cn * pi);
        final sat = 0.6 * (0.5 + 0.5 * sin(rn * pi * 3 + cn * pi * 2));
        final val = 0.7 + 0.3 * cos(cn * pi * 2 + rn * pi * 1.5);
        return _hsv(hue, sat.clamp(0.0, 1.0), val.clamp(0.0, 1.0));
      });
    });
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.bounce, rowMs: 250);
  }

  Future<void> _loadEffects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStorageKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => CustomEffect.fromJson(e as Map<String, dynamic>))
          .toList();

      // Restore which effects were last uploaded to THIS specific band.
      final deviceId = _connectedDeviceId;
      Set<String> uploaded = const {};
      if (deviceId != null) {
        final uploadedRaw = prefs.getStringList('$_kUploadedKeyPrefix$deviceId');
        if (uploadedRaw != null) uploaded = Set<String>.from(uploadedRaw);
      }

      state = state.copyWith(effects: list, uploadedIds: uploaded);
    } catch (_) {
      // Corrupt / outdated data — keep defaults.
    }
  }

  Future<void> _saveEffects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kStorageKey,
      jsonEncode(state.effects.map((e) => e.toJson()).toList()),
    );
    // Persist uploadedIds scoped to the connected device.
    final deviceId = _connectedDeviceId;
    if (deviceId != null) {
      await prefs.setStringList(
        '$_kUploadedKeyPrefix$deviceId',
        state.uploadedIds.toList(),
      );
    }
  }

  // ── List view ────────────────────────────────────────────────────────────

  void toggleSelect(String id) {
    if (state.isUploading) return;
    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    state = state.copyWith(selectedIds: updated);
  }

  void rename(String id, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      effects: state.effects.map((e) {
        return e.id == id ? e.copyWith(name: trimmed) : e;
      }).toList(),
    );
    _saveEffects();
  }

  Future<void> upload() async {
    if (state.selectedIds.isEmpty || state.isUploading) return;
    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) return;

    state = state.copyWith(isUploading: true);

    // Build the ordered list of selected effects (preserving list order).
    final selected = state.effects
        .where((e) => state.selectedIds.contains(e.id))
        .toList();

    try {
      for (int i = 0; i < selected.length; i++) {
        await ble.uploadEffect(i, selected[i].data);
      }
      // Tell the Arduino to enter Custom mode and cycle through the uploaded slots.
      await ble.activateCustomMode(selected.length);
      ref.read(modeProvider.notifier).setCustomEffectsActive();
    } catch (_) {
      state = state.copyWith(isUploading: false);
      return;
    }

    state = state.copyWith(
      isUploading: false,
      uploadedIds: Set<String>.from(state.selectedIds),
      selectedIds: const {},
    );
    _saveEffects();
  }

  // ── Editor upload (quick test) ───────────────────────────────────────────

  /// Uploads the currently-edited effect to slot 0 on the Arduino and
  /// activates Custom mode with a single slot.  The band will play only this
  /// one effect, which is the expected behaviour for in-editor testing.
  Future<void> uploadEditorEffect() async {
    final effect = state.editingEffect;
    if (effect == null || state.isUploading) return;
    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) return;

    stopPreview();
    state = state.copyWith(isUploading: true);
    try {
      await ble.uploadEffect(0, effect.data);
      await ble.activateCustomMode(1);
      ref.read(modeProvider.notifier).setCustomEffectsActive();
    } catch (_) {
      state = state.copyWith(isUploading: false);
      return;
    }
    state = state.copyWith(
      isUploading: false,
      uploadedIds: {effect.id},
      selectedIds: const {},
    );
    _saveEffects();
  }

  // ── Editor navigation ────────────────────────────────────────────────────

  void openEditor(String id) {
    stopPreview();
    stopListPreview();
    state = state.copyWith(editingId: id, previewRow: 0);
  }

  void closeEditor() {
    stopPreview();
    state = state.copyWith(editingId: null);
  }

  // ── Matrix mutations ─────────────────────────────────────────────────────

  void setCell(String id, int row, int col, Color c) {
    _updateData(id, (d) => d.withCell(row, col, c));
  }

  void fillRow(String id, int row, Color c) {
    _updateData(id, (d) => d.withFilledRow(row, c));
  }

  void setGradient(String id, int row, Color from, Color to) {
    _updateData(id, (d) => d.withGradient(row, from, to));
  }

  void copyRowDown(String id, int row) {
    _updateData(id, (d) => d.withRowCopiedDown(row));
  }

  void _updateData(String id, EffectData Function(EffectData) fn) {
    state = state.copyWith(
      effects: state.effects.map((e) {
        return e.id == id ? e.copyWith(data: fn(e.data)) : e;
      }).toList(),
    );
    _saveEffects();
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  void toggleSoundMode(String id, SoundMode mode) {
    state = state.copyWith(
      effects: state.effects.map((e) {
        if (e.id != id) return e;
        final modes = Set<SoundMode>.from(e.data.soundModes);
        if (modes.contains(mode)) {
          modes.remove(mode);
        } else {
          modes.add(mode);
          // Pegel and Next on Beat are mutually exclusive — selecting one
          // deselects the other.
          if (mode == SoundMode.pegel) modes.remove(SoundMode.nextOnBeat);
          if (mode == SoundMode.nextOnBeat) modes.remove(SoundMode.pegel);
        }
        return e.copyWith(data: e.data.copyWith(soundModes: modes));
      }).toList(),
    );
    _saveEffects();
  }

  void setLoopMode(String id, LoopMode mode) {
    _updateData(id, (d) => d.copyWith(loopMode: mode));
  }

  void setRowMs(String id, int ms) {
    _updateData(id, (d) => d.copyWith(rowMs: ms.clamp(20, 1000)));
    // If this effect is currently being previewed, restart the timer so the
    // new interval takes effect immediately without stopping the preview.
    if (state.isPreviewing &&
        (state.editingId == id || state.previewingListId == id)) {
      _restartPreviewTimer(ms.clamp(20, 1000));
    }
  }

  // ── Preview ──────────────────────────────────────────────────────────────

  void _restartPreviewTimer(int ms) {
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(
      Duration(milliseconds: ms),
      (_) => _advancePreviewRow(),
    );
  }

  void startPreview() {
    if (state.isPreviewing) return;
    _previewForward = true;
    state = state.copyWith(isPreviewing: true, previewRow: 0);
    _restartPreviewTimer(state.editingEffect?.data.rowMs ?? 500);
  }

  void stopPreview() {
    _previewTimer?.cancel();
    _previewTimer = null;
    state = state.copyWith(isPreviewing: false);
  }

  void startListPreview(String id) {
    _previewForward = true;
    final ms = state.effects.firstWhere((e) => e.id == id).data.rowMs;
    state = state.copyWith(
      previewingListId: id,
      previewRow: 0,
      isPreviewing: true,
    );
    _restartPreviewTimer(ms);
  }

  void stopListPreview() {
    _previewTimer?.cancel();
    _previewTimer = null;
    state = state.copyWith(previewingListId: null, isPreviewing: false);
  }

  void _advancePreviewRow() {
    // Works for both editor preview and list preview.
    final effect = state.editingEffect ?? state.listPreviewEffect;
    if (effect == null) {
      stopPreview();
      stopListPreview();
      return;
    }

    const lastRow = kEffectRows - 1;
    final current = state.previewRow;
    final int next;

    if (effect.data.loopMode == LoopMode.loop) {
      next = (current + 1) % kEffectRows;
    } else {
      // Bounce
      if (_previewForward) {
        if (current >= lastRow) {
          _previewForward = false;
          next = lastRow - 1;
        } else {
          next = current + 1;
        }
      } else {
        if (current <= 0) {
          _previewForward = true;
          next = 1;
        } else {
          next = current - 1;
        }
      }
    }
    state = state.copyWith(previewRow: next);
  }
}

final customEffectProvider =
    NotifierProvider<CustomEffectNotifier, CustomEffectState>(
        CustomEffectNotifier.new);
