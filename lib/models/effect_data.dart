import 'package:flutter/material.dart';

import '../core/constants.dart';

const int kEffectRows = 8;

enum SoundMode { orgel, flashOnBeat, nextOnBeat, pegel }

enum LoopMode { loop, bounce }

class EffectData {
  final List<List<Color>> rows; // kEffectRows × kMaxLed
  final Set<SoundMode> soundModes;
  final LoopMode loopMode;
  /// Row-advance interval in milliseconds (20–1000).  Only used by the
  /// timer-based advance path (i.e. when neither Pegel nor Next-on-Beat is set).
  final int rowMs;

  const EffectData({
    required this.rows,
    required this.soundModes,
    required this.loopMode,
    this.rowMs = 500,
  });

  factory EffectData.blank() => EffectData(
        rows: List.generate(kEffectRows, (_) => List.filled(kMaxLed, Colors.black)),
        soundModes: const {},
        loopMode: LoopMode.loop,
        rowMs: 500,
      );

  EffectData copyWith({
    List<List<Color>>? rows,
    Set<SoundMode>? soundModes,
    LoopMode? loopMode,
    int? rowMs,
  }) =>
      EffectData(
        rows: rows ?? this.rows,
        soundModes: soundModes ?? this.soundModes,
        loopMode: loopMode ?? this.loopMode,
        rowMs: rowMs ?? this.rowMs,
      );

  // ── Immutable mutation helpers ─────────────────────────────────────────

  EffectData withCell(int row, int col, Color c) => copyWith(
        rows: List.generate(
          kEffectRows,
          (r) => r == row
              ? (List<Color>.from(rows[r])..[col] = c)
              : List<Color>.from(rows[r]),
        ),
      );

  EffectData withFilledRow(int row, Color c) => copyWith(
        rows: List.generate(
          kEffectRows,
          (r) => r == row ? List.filled(kMaxLed, c) : List<Color>.from(rows[r]),
        ),
      );

  EffectData withGradient(int row, Color from, Color to) => copyWith(
        rows: List.generate(
          kEffectRows,
          (r) => r == row
              ? List.generate(
                  kMaxLed,
                  (i) => Color.lerp(from, to, i / (kMaxLed - 1))!,
                )
              : List<Color>.from(rows[r]),
        ),
      );

  // ── Serialisation ──────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'rows': rows
            .map((row) => row.map((c) => c.value).toList())
            .toList(),
        'soundModes': soundModes.map((m) => m.name).toList(),
        'loopMode': loopMode.name,
        'rowMs': rowMs,
      };

  factory EffectData.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List;
    final rows = rawRows
        .map((row) => (row as List).map((v) => Color(v as int)).toList())
        .toList();

    final soundModes = ((json['soundModes'] as List?) ?? [])
        .map((s) => SoundMode.values.firstWhere(
              (m) => m.name == s,
              orElse: () => SoundMode.orgel,
            ))
        .toSet();

    final loopMode = LoopMode.values.firstWhere(
      (m) => m.name == json['loopMode'],
      orElse: () => LoopMode.loop,
    );

    final rowMs = ((json['rowMs'] as int?) ?? 500).clamp(20, 1000);

    return EffectData(rows: rows, soundModes: soundModes, loopMode: loopMode, rowMs: rowMs);
  }

  // ── Immutable mutation helpers — continued ─────────────────────────────

  EffectData withRowCopiedDown(int row) {
    if (row >= kEffectRows - 1) return this;
    return copyWith(
      rows: List.generate(
        kEffectRows,
        (r) => r == row + 1
            ? List<Color>.from(rows[row])
            : List<Color>.from(rows[r]),
      ),
    );
  }
}
