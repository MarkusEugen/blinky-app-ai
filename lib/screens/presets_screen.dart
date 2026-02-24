import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/preset.dart';
import '../providers/preset_provider.dart';

class PresetsScreen extends ConsumerWidget {
  const PresetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(presetProvider);
    final notifier = ref.read(presetProvider.notifier);

    final canUpload =
        state.selectedId != null &&
        state.selectedId != state.loadedId &&
        !state.isUploading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Presets',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Select a preset and upload it to the band',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),

        // ── Preset list ─────────────────────────────────────────
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: kPresets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final preset = kPresets[i];
              final isSelected = state.selectedId == preset.id;
              final isLoaded = state.loadedId == preset.id;
              return _PresetCard(
                preset: preset,
                isSelected: isSelected,
                isLoaded: isLoaded,
                onTap: () => notifier.select(preset.id),
              );
            },
          ),
        ),

        // ── Upload button ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: _UploadButton(
            canUpload: canUpload,
            isUploading: state.isUploading,
            onUpload: notifier.upload,
          ),
        ),
      ],
    );
  }
}

// ─── Preset card ──────────────────────────────────────────────────────────

class _PresetCard extends StatelessWidget {
  final Preset preset;
  final bool isSelected;
  final bool isLoaded;
  final VoidCallback onTap;

  const _PresetCard({
    required this.preset,
    required this.isSelected,
    required this.isLoaded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;

    Color borderColor;
    Color bgColor;
    if (isSelected) {
      borderColor = primary;
      bgColor = primary.withOpacity(0.12);
    } else if (isLoaded) {
      borderColor = const Color(0xFF4CAF50).withOpacity(0.5);
      bgColor = const Color(0xFF4CAF50).withOpacity(0.06);
    } else {
      borderColor = Colors.white.withOpacity(0.08);
      bgColor = surface;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: primary.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Text(preset.icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 16),

              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected || isLoaded
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : isLoaded
                                ? Colors.white
                                : Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.45),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Color swatches
                    _ColorSwatches(colors: preset.colors),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Right badge
              if (isLoaded && !isSelected)
                _LoadedBadge()
              else if (isSelected)
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check,
                      size: 16, color: Colors.white),
                )
              else
                const SizedBox(width: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  final List<Color> colors;
  const _ColorSwatches({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: colors.map((c) {
        return Container(
          width: 18,
          height: 10,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }).toList(),
    );
  }
}

class _LoadedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF4CAF50).withOpacity(0.4)),
      ),
      child: const Text(
        'Loaded',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4CAF50),
        ),
      ),
    );
  }
}

// ─── Upload button ─────────────────────────────────────────────────────────

class _UploadButton extends StatelessWidget {
  final bool canUpload;
  final bool isUploading;
  final VoidCallback onUpload;

  const _UploadButton({
    required this.canUpload,
    required this.isUploading,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: canUpload ? onUpload : null,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          disabledBackgroundColor: Colors.white.withOpacity(0.06),
        ),
        child: isUploading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: primary),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Uploading…',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.upload_rounded,
                    size: 18,
                    color: canUpload
                        ? Colors.white
                        : Colors.white.withOpacity(0.25),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Upload to Band',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: canUpload
                          ? Colors.white
                          : Colors.white.withOpacity(0.25),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
