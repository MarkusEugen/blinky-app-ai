import 'package:flutter/material.dart';

class Preset {
  final String id;
  final String name;
  final String icon;
  final String description;
  final List<Color> colors; // representative color swatches

  const Preset({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.colors,
  });
}

const List<Preset> kPresets = [
  Preset(
    id: 'classic',
    name: 'Classic',
    icon: '🌟',
    description: 'Warm white breathing cycle',
    colors: [Color(0xFFFFE4B5), Color(0xFFFFD700), Color(0xFFFFF8DC)],
  ),
  Preset(
    id: 'static',
    name: 'Static',
    icon: '💡',
    description: 'Solid white, full brightness',
    colors: [Color(0xFFFFFFFF), Color(0xFFF0F0FF), Color(0xFFE8E8FF)],
  ),
  Preset(
    id: 'party',
    name: 'Party',
    icon: '🎉',
    description: 'Fast cycling rainbow colors',
    colors: [Color(0xFFFF4444), Color(0xFF44FF44), Color(0xFF4444FF), Color(0xFFFFFF00)],
  ),
  Preset(
    id: 'lava',
    name: 'Lava',
    icon: '🌋',
    description: 'Slow red-orange pulses',
    colors: [Color(0xFFFF2200), Color(0xFFFF6600), Color(0xFFFF4400)],
  ),
  Preset(
    id: 'dim',
    name: 'Dim',
    icon: '🌙',
    description: 'Soft warm dim glow',
    colors: [Color(0xFF8B6914), Color(0xFFA0784A), Color(0xFF7A5C30)],
  ),
];
