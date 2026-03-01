import 'package:flutter/gestures.dart';
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
                  isConnected: isConnected,
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
      padding: editing == null
          ? const EdgeInsets.fromLTRB(12, 16, 20, 12)
          : const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editing == null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Select effects to upload to the band',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                  onPressed: notifier.closeEditor,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Back to list',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    editing.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _showRenameDialog(context, editing, notifier),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.edit_outlined,
                        size: 16,
                        color: Colors.white.withOpacity(0.45)),
                  ),
                ),
              ],
            ),
          ],
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

class _EditorBody extends StatefulWidget {
  final CustomEffect effect;
  final CustomEffectState state;
  final CustomEffectNotifier notifier;
  final bool isConnected;

  const _EditorBody({
    required this.effect,
    required this.state,
    required this.notifier,
    required this.isConnected,
  });

  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  Color _brushColor = const Color(0xFFFF0000);
  final List<EffectData> _undoStack = [];
  final List<EffectData> _redoStack = [];
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _pushUndo() {
    _undoStack.add(widget.effect.data);
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
    setState(() {});
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(widget.effect.data);
    final prev = _undoStack.removeLast();
    widget.notifier.restoreData(widget.effect.id, prev);
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(widget.effect.data);
    final next = _redoStack.removeLast();
    widget.notifier.restoreData(widget.effect.id, next);
    setState(() {});
  }

  void _pickBrushColor() {
    showDialog<void>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        initial: _brushColor,
        onApply: (c) => setState(() => _brushColor = c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawScrollbar(
      controller: _scrollCtrl,
      thumbVisibility: true,
      thickness: 4,
      radius: const Radius.circular(2),
      thumbColor: Colors.white.withOpacity(0.25),
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Brush color bar + undo/redo ──
            _BrushBar(
              brushColor: _brushColor,
              onPickColor: _pickBrushColor,
              canUndo: _undoStack.isNotEmpty,
              canRedo: _redoStack.isNotEmpty,
              onUndo: _undo,
              onRedo: _redo,
            ),
            const _SectionDivider(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              child: _CanvasMatrix(
                effect: widget.effect,
                notifier: widget.notifier,
                brushColor: _brushColor,
                onBeforePaint: _pushUndo,
              ),
            ),
            const _SectionDivider(),
          _SoundModeSection(
              effect: widget.effect, notifier: widget.notifier),
          const _SectionDivider(),
          _LoopModeSection(
              effect: widget.effect, notifier: widget.notifier),
          const _SectionDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: _PreviewButton(
                      state: widget.state, notifier: widget.notifier),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _UploadEditorButton(
                    isConnected: widget.isConnected,
                    isUploading: widget.state.isUploading,
                    onUpload: widget.notifier.uploadEditorEffect,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

// ─── Brush color bar ────────────────────────────────────────────────────────

class _BrushBar extends StatelessWidget {
  final Color brushColor;
  final VoidCallback onPickColor;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  const _BrushBar({
    required this.brushColor,
    required this.onPickColor,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.undo,
                color: canUndo ? Colors.white : Colors.white24),
            onPressed: canUndo ? onUndo : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Undo',
          ),
          IconButton(
            icon: Icon(Icons.redo,
                color: canRedo ? Colors.white : Colors.white24),
            onPressed: canRedo ? onRedo : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Redo',
          ),
          const Spacer(),
          GestureDetector(
            onTap: onPickColor,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Brush',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6), fontSize: 12)),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: brushColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.4), width: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Eager pan recognizer (wins gesture arena immediately) ──────────────────

class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

// ─── Canvas matrix (drag-to-paint) ──────────────────────────────────────────

class _CanvasMatrix extends StatefulWidget {
  final CustomEffect effect;
  final CustomEffectNotifier notifier;
  final Color brushColor;
  final VoidCallback onBeforePaint;

  const _CanvasMatrix({
    required this.effect,
    required this.notifier,
    required this.brushColor,
    required this.onBeforePaint,
  });

  @override
  State<_CanvasMatrix> createState() => _CanvasMatrixState();
}

class _CanvasMatrixState extends State<_CanvasMatrix> {
  int? _lastPaintedRow;
  int? _lastPaintedCol;

  static const double _cellHeight = 20.0;
  static const double _rowGap = 1.0;
  static const double _rowBtnWidth = 26.0;
  static const double _hPad = 4.0;

  void _onOverlayPanStart(DragStartDetails details) {
    _lastPaintedRow = null;
    _lastPaintedCol = null;
    widget.onBeforePaint();
    _paintFromLocal(details.localPosition);
  }

  void _onOverlayPanUpdate(DragUpdateDetails details) {
    _paintFromLocal(details.localPosition);
  }

  /// Convert a local position within the overlay (which covers only the cell
  /// area) to (row, col) and paint.
  void _paintFromLocal(Offset local) {
    final rowHeight = _cellHeight + _rowGap;
    final row = (local.dy / rowHeight).floor().clamp(0, kEffectRows - 1);
    // col is determined by the overlay context (set in LayoutBuilder)
    final col = (local.dx / _overlayWidth * kMaxLed)
        .floor()
        .clamp(0, kMaxLed - 1);

    if (row == _lastPaintedRow && col == _lastPaintedCol) return;
    _lastPaintedRow = row;
    _lastPaintedCol = col;
    widget.notifier.setCell(widget.effect.id, row, col, widget.brushColor);
  }

  // Cached by LayoutBuilder each build.
  double _overlayWidth = 1;

  void _openFillPicker(int rowIndex) {
    widget.onBeforePaint();
    showDialog<void>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        initial: widget.effect.data.rows[rowIndex].first,
        onApply: (c) =>
            widget.notifier.fillRow(widget.effect.id, rowIndex, c),
      ),
    );
  }

  void _openGradientDialog(int rowIndex) {
    widget.onBeforePaint();
    showDialog<void>(
      context: context,
      builder: (_) => _GradientDialog(
        effectId: widget.effect.id,
        rowIndex: rowIndex,
        notifier: widget.notifier,
      ),
    );
  }

  void _copyRowDown(int rowIndex) {
    widget.onBeforePaint();
    widget.notifier.copyRowDown(widget.effect.id, rowIndex);
  }

  Widget _rowBtn(IconData icon, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _rowBtnWidth,
        height: _cellHeight,
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gridHeight =
        kEffectRows * _cellHeight + (kEffectRows - 1) * _rowGap;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final cellAreaLeft = _hPad + _rowBtnWidth;
        final cellAreaWidth =
            totalWidth - cellAreaLeft - _hPad - _rowBtnWidth * 2;
        _overlayWidth = cellAreaWidth;

        return SizedBox(
          height: gridHeight,
          child: Stack(
            children: [
              // ── Grid layer (visual + side buttons) ──
              Column(
                children: [
                  for (int row = 0; row < kEffectRows; row++) ...[
                    if (row > 0) const SizedBox(height: _rowGap),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: _hPad),
                      child: Row(
                        children: [
                          _rowBtn(
                              Icons.format_color_fill,
                              const Color(0xFFFF9100),
                              () => _openFillPicker(row)),
                          Expanded(
                            child: Row(
                              children: List.generate(kMaxLed, (col) {
                                final c =
                                    widget.effect.data.rows[row][col];
                                final isBlack =
                                    c.value == Colors.black.value;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 0.5),
                                    child: Container(
                                      height: _cellHeight,
                                      decoration: BoxDecoration(
                                        color: c,
                                        borderRadius:
                                            BorderRadius.circular(3),
                                        border: Border.all(
                                          color: isBlack
                                              ? Colors.white
                                                  .withOpacity(0.18)
                                              : Colors.transparent,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                          _rowBtn(Icons.gradient, const Color(0xFF40C4FF),
                              () => _openGradientDialog(row)),
                          _rowBtn(
                            Icons.south,
                            row == kEffectRows - 1
                                ? Colors.white24
                                : Colors.white54,
                            row == kEffectRows - 1
                                ? null
                                : () => _copyRowDown(row),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              // ── Gesture overlay (cells only — blocks scroll) ──
              Positioned(
                left: cellAreaLeft,
                top: 0,
                width: cellAreaWidth,
                height: gridHeight,
                child: RawGestureDetector(
                  gestures: <Type,
                      GestureRecognizerFactory<GestureRecognizer>>{
                    _EagerPanRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            _EagerPanRecognizer>(
                      _EagerPanRecognizer.new,
                      (recognizer) {
                        recognizer
                          ..onStart = _onOverlayPanStart
                          ..onUpdate = _onOverlayPanUpdate;
                      },
                    ),
                  },
                  behavior: HitTestBehavior.opaque,
                ),
              ),
            ],
          ),
        );
      },
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
      content: ClipRect(
        child: SizedBox(
          width: 300,
          height: 280,
          child: ColorPicker(
            key: ValueKey(_pickerKey),
            pickerColor: _current,
            onColorChanged: (c) => _current = c,
            portraitOnly: true,
            enableAlpha: false,
            hexInputBar: false,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.65,
          ),
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
    final rowMs = effect.data.rowMs;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          // Loop / Bounce row
          Row(
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
          const SizedBox(height: 2),
          // Row advance interval slider (timer-based mode only)
          Row(
            children: [
              const SizedBox(
                width: 46,
                child: Text('Step',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14),
                  ),
                  child: Slider(
                    value: rowMs.toDouble(),
                    min: 20,
                    max: 1000,
                    divisions: 98, // 10 ms steps
                    activeColor: primary,
                    inactiveColor: primary.withOpacity(0.2),
                    onChanged: (v) =>
                        notifier.setRowMs(effect.id, v.round()),
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '${rowMs}ms',
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Upload editor button ─────────────────────────────────────────────────────

class _UploadEditorButton extends StatelessWidget {
  final bool isConnected;
  final bool isUploading;
  final Future<void> Function() onUpload;

  const _UploadEditorButton({
    required this.isConnected,
    required this.isUploading,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final canUpload = isConnected && !isUploading;
    return SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: canUpload ? onUpload : null,
        style: FilledButton.styleFrom(
          backgroundColor:
              canUpload ? const Color(0xFF00695C) : null,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.upload_rounded,
                    size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              isUploading ? 'Uploading…' : 'Upload',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
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

    return SizedBox(
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
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              isPreviewing ? 'Stop' : 'Preview',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
