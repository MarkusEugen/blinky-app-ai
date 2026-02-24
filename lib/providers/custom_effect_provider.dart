import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_effect.dart';
import '../models/effect_data.dart';
import 'lighting_provider.dart';

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

  static List<CustomEffect> _defaultEffects() => List.generate(
        8,
        (i) => CustomEffect(
          id: 'effect_${i + 1}',
          name: 'myEffect${i + 1}',
          data: EffectData.blank(),
        ),
      );

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

    state = state.copyWith(isUploading: true);
    await Future.delayed(const Duration(milliseconds: 1400));

    ref.read(lightingProvider.notifier).activateEffect('Custom');

    state = state.copyWith(
      isUploading: false,
      uploadedIds: Set<String>.from(state.selectedIds),
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
        }
        return e.copyWith(data: e.data.copyWith(soundModes: modes));
      }).toList(),
    );
    _saveEffects();
  }

  void setLoopMode(String id, LoopMode mode) {
    _updateData(id, (d) => d.copyWith(loopMode: mode));
  }

  // ── Preview ──────────────────────────────────────────────────────────────

  void startPreview() {
    if (state.isPreviewing) return;
    _previewForward = true;
    state = state.copyWith(isPreviewing: true, previewRow: 0);
    _previewTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _advancePreviewRow(),
    );
  }

  void stopPreview() {
    _previewTimer?.cancel();
    _previewTimer = null;
    state = state.copyWith(isPreviewing: false);
  }

  void startListPreview(String id) {
    _previewTimer?.cancel();
    _previewForward = true;
    state = state.copyWith(
      previewingListId: id,
      previewRow: 0,
      isPreviewing: true,
    );
    _previewTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _advancePreviewRow(),
    );
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
