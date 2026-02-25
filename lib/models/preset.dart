import 'package:flutter/material.dart';

/// One entry in the Mode list.
class AppMode {
  final String id;
  final String name;
  final String icon;
  final String description;
  final List<Color> colors;

  /// Index sent in the BLE command [0x02, bleIndex].
  /// 0–4 = built-in presets, 5 = custom-effects mode.
  final int bleIndex;

  /// When true, tapping this item navigates to the Custom Effects tab
  /// instead of sending a BLE command.
  final bool isCustomEffects;

  const AppMode({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.colors,
    required this.bleIndex,
    this.isCustomEffects = false,
  });
}

/// Arduino STATUS characteristic byte[0] mapping:
///   0 = Classic, 1 = Static, 2 = Party, 3 = Lava, 4 = Dim
///   5 = Custom Effect playing
///   255 = Solid colour (no mode active)
const List<AppMode> kModes = [
  AppMode(
    id: 'classic',
    name: 'Classic',
    icon: '🌟',
    description: 'Sound-reactive animation engine',
    colors: [Color(0xFFFFE4B5), Color(0xFFFFD700), Color(0xFFFFF8DC)],
    bleIndex: 0,
  ),
  AppMode(
    id: 'static',
    name: 'Static',
    icon: '💡',
    description: 'Solid white, full brightness',
    colors: [Color(0xFFFFFFFF), Color(0xFFF0F0FF), Color(0xFFE8E8FF)],
    bleIndex: 1,
  ),
  AppMode(
    id: 'party',
    name: 'Party',
    icon: '🎉',
    description: 'Fast cycling rainbow colors',
    colors: [Color(0xFFFF4444), Color(0xFF44FF44), Color(0xFF4444FF), Color(0xFFFFFF00)],
    bleIndex: 2,
  ),
  AppMode(
    id: 'lava',
    name: 'Lava',
    icon: '🌋',
    description: 'Slow red-orange pulses',
    colors: [Color(0xFFFF2200), Color(0xFFFF6600), Color(0xFFFF4400)],
    bleIndex: 3,
  ),
  AppMode(
    id: 'dim',
    name: 'Dim',
    icon: '🌙',
    description: 'Soft warm dim glow',
    colors: [Color(0xFF8B6914), Color(0xFFA0784A), Color(0xFF7A5C30)],
    bleIndex: 4,
  ),
  AppMode(
    id: 'custom',
    name: 'Custom Effects',
    icon: '✨',
    description: 'Your uploaded animations',
    colors: [Color(0xFF7C6BFF), Color(0xFFFF6B6B), Color(0xFF6BFFC8)],
    bleIndex: 5,
    isCustomEffects: true,
  ),
];

// Backward-compat alias used by screens that haven't been renamed yet.
typedef Preset = AppMode;
const kPresets = kModes;

/// Map a BLE modeIndex (STATUS byte[0]) back to an AppMode.
/// Returns null for 255 (solid colour, no mode).
AppMode? modeFromBleIndex(int bleIndex) {
  if (bleIndex == 255) return null;
  try {
    return kModes.firstWhere((m) => m.bleIndex == bleIndex);
  } catch (_) {
    return null;
  }
}
