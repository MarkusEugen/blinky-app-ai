import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/custom_effect.dart';
import '../models/effect_data.dart';
import '../providers/custom_effect_provider.dart';
import '../providers/device_provider.dart';
import '../providers/lighting_provider.dart';

class CustomEffectsScreen extends ConsumerWidget {
  const CustomEffectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customEffectProvider);
    final notifier = ref.read(customEffectProvider.notifier);
    final isConnected = ref.watch(deviceProvider).connectedDevice != null;

    final canUpload =
        isConnected && state.selectedIds.isNotEmpty && !state.isUploading;
    final editing = state.editingEffect;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header + LED strip (always visible) ──────────────────────────
        _TopSection(),

        // ── Body: list OR editor ──────────────────────────────────────────
        Expanded(
          child: editing == null
              ? _ListBody(state: state, notifier: notifier)
              : _EditorBody(
                  effect: editing,
                  state: state,
                  notifier: notifier,
                ),
        ),

        // ── Upload button (list mode only) ────────────────────────────────
        if (editing == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: _UploadButton(
              canUpload: canUpload,
              isUploading: state.isUploading,
              selectedCount: state.selectedIds.length,
              onUpload: notifier.upload,
            ),
          ),
      ],
    );
  }
}

void _showRenameDialog(
  BuildContext context,
  CustomEffect effect,
  CustomEffectNotifier notifier,
) {
  final controller = TextEditingController(text: effect.name);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Rename effect',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Effect name',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        ),
        onSubmitted: (v) {
          notifier.rename(effect.id, v);
          Navigator.of(ctx).pop();
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        TextButton(
          onPressed: () {
            notifier.rename(effect.id, controller.text);
            Navigator.of(ctx).pop();
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

// ─── Top section (adaptive) ────────────────────────────────────────────────

class _TopSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customEffectProvider);
    final notifier = ref.read(customEffectProvider.notifier);
    final displayColor = ref.watch(
      lightingProvider.select((s) => s.displayColor),
    );

    final editing = state.editingEffect;
    final listPreview = state.listPreviewEffect;

    final List<Color> ledColors;
    if (editing != null) {
      ledColors = editing.data.rows[state.previewRow];
    } else if (listPreview != null) {
      ledColors = listPreview.data.rows[state.previewRow];
    } else {
      ledColors = List.filled(kMaxLed, displayColor);
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editing == null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('Custom Effects',
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Select effects to upload to the band',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ] else ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: notifier.closeEditor,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: 'Back to list',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    editing.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _showRenameDialog(context, editing, notifier),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.edit_outlined,
                        size: 18,
                        color: Colors.white.withOpacity(0.45)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _LedStrip(colors: ledColors),
        ],
      ),
    );
  }
}

// ─── LED strip ─────────────────────────────────────────────────────────────

class _LedStrip extends StatelessWidget {
  final List<Color> colors; // length == kMaxLed
  const _LedStrip({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(kMaxLed, (i) {
          final c = colors[i];
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.withOpacity(0.55),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── List body ─────────────────────────────────────────────────────────────

class _ListBody extends StatelessWidget {
  final CustomEffectState state;
  final CustomEffectNotifier notifier;

  const _ListBody({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.effects.length,
      itemBuilder: (context, i) {
        final effect = state.effects[i];
        final isPreviewing = state.previewingListId == effect.id;
        return _EffectRow(
          effect: effect,
          isSelected: state.selectedIds.contains(effect.id),
          isUploaded: state.uploadedIds.contains(effect.id),
          isUploading: state.isUploading,
          isPreviewing: isPreviewing,
          onToggle: () => notifier.toggleSelect(effect.id),
          onRename: (name) => notifier.rename(effect.id, name),
          onEdit: () => notifier.openEditor(effect.id),
          onPreviewToggle: () => isPreviewing
              ? notifier.stopListPreview()
              : notifier.startListPreview(effect.id),
        );
      },
    );
  }
}

// ─── Effect row ────────────────────────────────────────────────────────────

class _EffectRow extends StatelessWidget {
  final CustomEffect effect;
  final bool isSelected;
  final bool isUploaded;
  final bool isUploading;
  final bool isPreviewing;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onEdit;
  final VoidCallback onPreviewToggle;

  const _EffectRow({
    required this.effect,
    required this.isSelected,
    required this.isUploaded,
    required this.isUploading,
    required this.isPreviewing,
    required this.onToggle,
    required this.onRename,
    required this.onEdit,
    required this.onPreviewToggle,
  });

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: effect.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Rename effect',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Effect name',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          ),
          onSubmitted: (v) {
            onRename(v);
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () {
              onRename(controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: isUploading ? null : onToggle,
      onLongPress: isUploading ? null : () => _showRenameDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            Checkbox(
              value: isSelected,
              onChanged: isUploading ? null : (_) => onToggle(),
              activeColor: primary,
              side: BorderSide(color: Colors.white.withOpacity(0.3)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),

            // Effect name
            Expanded(
              child: Text(
                effect.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
            ),

            // Uploaded indicator
            if (isUploaded)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: Color(0xFF4CAF50),
                ),
              ),

            // Play/stop preview button
            IconButton(
              icon: Icon(
                isPreviewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 18,
                color: isPreviewing
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withOpacity(0.45),
              ),
              onPressed: isUploading ? null : onPreviewToggle,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: isPreviewing ? 'Stop preview' : 'Preview effect',
            ),

            // Edit button → opens editor
            IconButton(
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: Colors.white.withOpacity(0.35),
              ),
              onPressed: isUploading ? null : onEdit,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Edit effect',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Upload button ─────────────────────────────────────────────────────────

class _UploadButton extends StatelessWidget {
  final bool canUpload;
  final bool isUploading;
  final int selectedCount;
  final Future<void> Function() onUpload;

  const _UploadButton({
    required this.canUpload,
    required this.isUploading,
    required this.selectedCount,
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
                  const Text('Uploading…',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
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
                    selectedCount > 0
                        ? 'Upload Selected ($selectedCount)'
                        : 'Upload Selected',
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

// ═══════════════════════════════════════════════════════════════════════════
// EDITOR
// ═══════════════════════════════════════════════════════════════════════════

class _EditorBody extends StatelessWidget {
  final CustomEffect effect;
  final CustomEffectState state;
  final CustomEffectNotifier notifier;

  const _EditorBody({
    required this.effect,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MatrixGrid(effect: effect, notifier: notifier),
          const _SectionDivider(),
          _SoundModeSection(effect: effect, notifier: notifier),
          const _SectionDivider(),
          _LoopModeSection(effect: effect, notifier: notifier),
          const _SectionDivider(),
          _PreviewButton(state: state, notifier: notifier),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      color: Colors.white.withOpacity(0.08),
      height: 1,
      thickness: 1,
    );
  }
}

// ─── Matrix grid ────────────────────────────────────────────────────────────

class _MatrixGrid extends StatelessWidget {
  final CustomEffect effect;
  final CustomEffectNotifier notifier;

  const _MatrixGrid({required this.effect, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int row = 0; row < kEffectRows; row++) ...[
          if (row > 0) const SizedBox(height: 1),
          _MatrixRow(
            effectId: effect.id,
            rowIndex: row,
            cells: effect.data.rows[row],
            notifier: notifier,
          ),
        ],
      ],
    );
  }
}

// ─── Matrix row ─────────────────────────────────────────────────────────────

class _MatrixRow extends StatelessWidget {
  final String effectId;
  final int rowIndex;
  final List<Color> cells;
  final CustomEffectNotifier notifier;

  const _MatrixRow({
    required this.effectId,
    required this.rowIndex,
    required this.cells,
    required this.notifier,
  });

  Future<void> _showColorPicker(
    BuildContext context,
    Color initial,
    ValueChanged<Color> onPicked,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        initial: initial,
        onApply: onPicked,
      ),
    );
  }

  void _openFillPicker(BuildContext context) {
    _showColorPicker(
      context,
      cells.first,
      (c) => notifier.fillRow(effectId, rowIndex, c),
    );
  }

  void _openGradientDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _GradientDialog(
        effectId: effectId,
        rowIndex: rowIndex,
        notifier: notifier,
      ),
    );
  }

  void _openCellPicker(BuildContext context, int col) {
    _showColorPicker(
      context,
      cells[col],
      (c) => notifier.setCell(effectId, rowIndex, col, c),
    );
  }

  Widget _rowBtn(IconData icon, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 26,
        height: 20,
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastRow = rowIndex == kEffectRows - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Fill row button
          _rowBtn(Icons.format_color_fill, const Color(0xFFFF9100),
              () => _openFillPicker(context)),

          // 15 cell squares — each takes an equal Expanded share
          Expanded(
            child: Row(
              children: List.generate(kMaxLed, (col) {
                final c = cells[col];
                final isBlack = c.value == Colors.black.value;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: GestureDetector(
                      onTap: () => _openCellPicker(context, col),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        height: 20,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: isBlack
                                ? Colors.white.withOpacity(0.18)
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Gradient button
          _rowBtn(Icons.gradient, const Color(0xFF40C4FF),
              () => _openGradientDialog(context)),

          // Copy row down button
          _rowBtn(
            Icons.south,
            isLastRow ? Colors.white24 : Colors.white54,
            isLastRow ? null : () => notifier.copyRowDown(effectId, rowIndex),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable color picker dialog (with Invert) ─────────────────────────────

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color>? onApply;

  const _ColorPickerDialog({required this.initial, this.onApply});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _current;
  int _pickerKey = 0; // incremented on invert to force ColorPicker reinit

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  void _invert() {
    setState(() {
      _current = Color(0xFF000000 | (~_current.value & 0x00FFFFFF));
      _pickerKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 320,
        child: ColorPicker(
          key: ValueKey(_pickerKey),
          pickerColor: _current,
          onColorChanged: (c) => _current = c,
          portraitOnly: true,
          enableAlpha: false,
          hexInputBar: false,
          labelTypes: const [],
          pickerAreaHeightPercent: 0.7,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _invert,
          child: const Text('Invert'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        TextButton(
          onPressed: () {
            widget.onApply?.call(_current);
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ─── Gradient dialog ────────────────────────────────────────────────────────

class _GradientDialog extends StatefulWidget {
  final String effectId;
  final int rowIndex;
  final CustomEffectNotifier notifier;

  const _GradientDialog({
    required this.effectId,
    required this.rowIndex,
    required this.notifier,
  });

  @override
  State<_GradientDialog> createState() => _GradientDialogState();
}

class _GradientDialogState extends State<_GradientDialog> {
  Color _colorA = Colors.red;
  Color _colorB = Colors.blue;

  Future<void> _pickColor(bool isA) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        initial: isA ? _colorA : _colorB,
        onApply: (c) => setState(() {
          if (isA) {
            _colorA = c;
          } else {
            _colorB = c;
          }
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text(
        'Gradient Fill',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ColorSwatch(
            label: 'Color A',
            color: _colorA,
            onTap: () => _pickColor(true),
          ),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white54),
          _ColorSwatch(
            label: 'Color B',
            color: _colorB,
            onTap: () => _pickColor(false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        TextButton(
          onPressed: () {
            widget.notifier
                .setGradient(widget.effectId, widget.rowIndex, _colorA, _colorB);
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Sound mode section ──────────────────────────────────────────────────────

class _SoundModeSection extends StatelessWidget {
  final CustomEffect effect;
  final CustomEffectNotifier notifier;

  const _SoundModeSection({required this.effect, required this.notifier});

  static const _labels = {
    SoundMode.orgel: 'Orgel',
    SoundMode.flashOnBeat: 'Flash ♩',
    SoundMode.nextOnBeat: 'Next ♩',
    SoundMode.pegel: 'Pegel',
  };

  @override
  Widget build(BuildContext context) {
    final selected = effect.data.soundModes;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 46,
            child: Text('Sound',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
          ),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 4,
              children: SoundMode.values.map((mode) {
                return FilterChip(
                  label: Text(_labels[mode]!,
                      style: const TextStyle(fontSize: 11)),
                  selected: selected.contains(mode),
                  onSelected: (_) =>
                      notifier.toggleSoundMode(effect.id, mode),
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 0),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loop mode section ───────────────────────────────────────────────────────

class _LoopModeSection extends StatelessWidget {
  final CustomEffect effect;
  final CustomEffectNotifier notifier;

  const _LoopModeSection({required this.effect, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final loopMode = effect.data.loopMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 46,
            child: Text('Loop',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
          ),
          ChoiceChip(
            label: const Text('Loop', style: TextStyle(fontSize: 11)),
            selected: loopMode == LoopMode.loop,
            onSelected: (_) =>
                notifier.setLoopMode(effect.id, LoopMode.loop),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Bounce', style: TextStyle(fontSize: 11)),
            selected: loopMode == LoopMode.bounce,
            onSelected: (_) =>
                notifier.setLoopMode(effect.id, LoopMode.bounce),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          ),
        ],
      ),
    );
  }
}

// ─── Preview button ──────────────────────────────────────────────────────────

class _PreviewButton extends StatelessWidget {
  final CustomEffectState state;
  final CustomEffectNotifier notifier;

  const _PreviewButton({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isPreviewing = state.isPreviewing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: SizedBox(
        height: 44,
        child: FilledButton(
          onPressed:
              isPreviewing ? notifier.stopPreview : notifier.startPreview,
          style: FilledButton.styleFrom(
            backgroundColor:
                isPreviewing ? const Color(0xFFB71C1C) : primary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPreviewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 22,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                isPreviewing ? 'Stop Preview' : 'Start Preview',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
