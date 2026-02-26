import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/custom_effect.dart';
import '../models/effect_data.dart';
import '../services/ble_service.dart';
import 'preset_provider.dart';

// Sentinel for nullable copyWith fields.
const _sentinel = Object();

const _kStorageKey = 'custom_effects_v1';

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

  @override
  CustomEffectState build() {
    ref.onDispose(() {
      _previewTimer?.cancel();
      _previewTimer = null;
    });

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

  static List<Color> _grad(Color a, Color b) =>
      List.generate(kMaxLed, (i) => Color.lerp(a, b, i / (kMaxLed - 1))!);

  static List<Color> _solid(Color c) => List.filled(kMaxLed, c);

  // ── Default effect patterns ────────────────────────────────────────────────

  /// Full hue rainbow rotating 45° per row → spinning rainbow ring animation.
  static EffectData _rainbowEffect() {
    final rows = List.generate(kEffectRows, (r) => List.generate(
      kMaxLed,
      (i) => _hsv(r * 45.0 + i * (300.0 / (kMaxLed - 1)), 1.0, 1.0),
    ));
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.loop, rowMs: 100);
  }

  /// Fire palette: deep red → orange → yellow, bouncing.
  static EffectData _fireEffect() {
    final cols = [
      [_hsv(0, 1.0, 0.8),  _hsv(15, 1.0, 1.0)],
      [_hsv(15, 1.0, 1.0), _hsv(30, 1.0, 1.0)],
      [_hsv(30, 1.0, 1.0), _hsv(50, 1.0, 1.0)],
      [_hsv(50, 1.0, 1.0), _hsv(30, 1.0, 0.9)],
      [_hsv(30, 1.0, 0.9), _hsv(10, 1.0, 1.0)],
      [_hsv(10, 1.0, 1.0), _hsv(0,  1.0, 0.7)],
      [_hsv(5,  1.0, 0.9), _hsv(40, 1.0, 1.0)],
      [_hsv(40, 1.0, 1.0), _hsv(5,  1.0, 0.8)],
    ];
    final rows = cols.map((c) => _grad(c[0], c[1])).toList();
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.bounce, rowMs: 80);
  }

  /// Ocean: alternating blue↔cyan gradient sweeps.
  static EffectData _oceanEffect() {
    final pairs = [
      [_hsv(200, 1.0, 0.9), _hsv(175, 0.8, 1.0)],
      [_hsv(175, 0.8, 1.0), _hsv(210, 1.0, 0.6)],
      [_hsv(195, 0.9, 1.0), _hsv(165, 0.7, 0.9)],
      [_hsv(165, 0.7, 0.9), _hsv(215, 1.0, 1.0)],
      [_hsv(215, 1.0, 1.0), _hsv(185, 0.9, 1.0)],
      [_hsv(185, 0.9, 1.0), _hsv(200, 1.0, 0.7)],
      [_hsv(200, 0.7, 0.7), _hsv(175, 1.0, 1.0)],
      [_hsv(175, 1.0, 1.0), _hsv(200, 1.0, 0.9)],
    ];
    final rows = pairs.map((p) => _grad(p[0], p[1])).toList();
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.loop, rowMs: 180);
  }

  /// Candy: solid bright stripes cycling through vivid hues.
  static EffectData _candyEffect() {
    final palette = [
      _hsv(330, 1.0, 1.0), // hot pink
      _hsv(180, 1.0, 1.0), // cyan
      _hsv(300, 1.0, 1.0), // magenta
      _hsv(90,  1.0, 1.0), // lime
      _hsv(15,  1.0, 1.0), // orange
      _hsv(270, 1.0, 1.0), // violet
      _hsv(55,  1.0, 1.0), // yellow
      _hsv(210, 1.0, 1.0), // sky blue
    ];
    final rows = palette.map(_solid).toList();
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.loop, rowMs: 150);
  }

  /// Sunset: warm hues shifting from scarlet through orange to violet.
  static EffectData _sunsetEffect() {
    final pairs = [
      [_hsv(0,   1.0, 1.0), _hsv(20,  1.0, 1.0)],
      [_hsv(20,  1.0, 1.0), _hsv(40,  1.0, 0.9)],
      [_hsv(40,  1.0, 0.9), _hsv(20,  0.9, 1.0)],
      [_hsv(15,  1.0, 1.0), _hsv(300, 0.8, 0.8)],
      [_hsv(300, 0.8, 0.8), _hsv(270, 1.0, 0.7)],
      [_hsv(270, 1.0, 0.7), _hsv(10,  1.0, 0.9)],
      [_hsv(10,  1.0, 0.9), _hsv(35,  1.0, 1.0)],
      [_hsv(35,  1.0, 1.0), _hsv(0,   1.0, 1.0)],
    ];
    final rows = pairs.map((p) => _grad(p[0], p[1])).toList();
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.bounce, rowMs: 220);
  }

  /// Forest: deep greens to bright lime with golden accents.
  static EffectData _forestEffect() {
    final pairs = [
      [_hsv(130, 1.0, 0.5), _hsv(100, 0.9, 1.0)],
      [_hsv(100, 0.9, 1.0), _hsv(140, 1.0, 0.4)],
      [_hsv(140, 1.0, 0.4), _hsv(80,  1.0, 0.9)],
      [_hsv(80,  1.0, 0.9), _hsv(120, 0.8, 0.7)],
      [_hsv(120, 0.8, 0.7), _hsv(90,  1.0, 1.0)],
      [_hsv(90,  1.0, 1.0), _hsv(55,  1.0, 0.9)],
      [_hsv(55,  1.0, 0.9), _hsv(120, 1.0, 0.5)],
      [_hsv(120, 1.0, 0.5), _hsv(100, 0.9, 1.0)],
    ];
    final rows = pairs.map((p) => _grad(p[0], p[1])).toList();
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.loop, rowMs: 200);
  }

  /// Cosmic: deep violet through indigo and pink with bright flashes.
  static EffectData _cosmicEffect() {
    final pairs = [
      [_hsv(270, 1.0, 0.9), _hsv(300, 0.8, 1.0)],
      [_hsv(300, 0.8, 1.0), _hsv(240, 1.0, 0.6)],
      [_hsv(240, 1.0, 0.6), _hsv(280, 0.6, 1.0)],
      [_hsv(280, 0.6, 1.0), _hsv(320, 1.0, 0.9)],
      [_hsv(320, 1.0, 0.9), _hsv(260, 1.0, 0.7)],
      [_hsv(260, 1.0, 0.7), _hsv(290, 0.5, 1.0)],
      [_hsv(290, 0.5, 1.0), _hsv(250, 1.0, 0.9)],
      [_hsv(250, 1.0, 0.9), _hsv(310, 0.9, 1.0)],
    ];
    final rows = pairs.map((p) => _grad(p[0], p[1])).toList();
    return EffectData(rows: rows, soundModes: const {}, loopMode: LoopMode.bounce, rowMs: 160);
  }

  /// Ice: arctic whites fading into deep arctic blue.
  static EffectData _iceEffect() {
    final pairs = [
      [const Color(0xFFFFFFFF), _hsv(195, 0.4, 1.0)],
      [_hsv(195, 0.4, 1.0),    _hsv(200, 0.8, 0.9)],
      [_hsv(200, 0.8, 0.9),    _hsv(210, 1.0, 0.7)],
      [_hsv(210, 1.0, 0.7),    const Color(0xFFFFFFFF)],
      [const Color(0xFFFFFFFF), _hsv(200, 0.5, 1.0)],
      [_hsv(200, 0.5, 1.0),    _hsv(205, 0.9, 0.8)],
      [_hsv(205, 0.9, 0.8),    _hsv(195, 0.3, 1.0)],
      [_hsv(195, 0.3, 1.0),    const Color(0xFFFFFFFF)],
    ];
    final rows = pairs.map((p) => _grad(p[0], p[1])).toList();
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
      state = state.copyWith(effects: list);
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
