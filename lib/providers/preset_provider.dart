import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/preset.dart';
import 'lighting_provider.dart';

class PresetState {
  final String? selectedId;
  final String? loadedId;
  final bool isUploading;

  const PresetState({
    this.selectedId,
    this.loadedId,
    this.isUploading = false,
  });

  PresetState copyWith({
    Object? selectedId = _sentinel,
    Object? loadedId = _sentinel,
    bool? isUploading,
  }) {
    return PresetState(
      selectedId:
          selectedId == _sentinel ? this.selectedId : selectedId as String?,
      loadedId: loadedId == _sentinel ? this.loadedId : loadedId as String?,
      isUploading: isUploading ?? this.isUploading,
    );
  }
}

const _sentinel = Object();

class PresetNotifier extends Notifier<PresetState> {
  @override
  PresetState build() => const PresetState();

  void select(String id) {
    if (state.isUploading) return;
    state = state.copyWith(selectedId: id);
  }

  Future<void> upload() async {
    final id = state.selectedId;
    if (id == null || state.isUploading) return;

    final preset = kPresets.firstWhere((p) => p.id == id);

    state = state.copyWith(isUploading: true);

    // Simulate upload delay
    await Future.delayed(const Duration(milliseconds: 1400));

    // Push the preset name into the lighting state so the status bar reflects it
    ref.read(lightingProvider.notifier).activateEffect(preset.name);

    state = state.copyWith(
      isUploading: false,
      loadedId: id,
    );
  }
}

final presetProvider =
    NotifierProvider<PresetNotifier, PresetState>(PresetNotifier.new);
