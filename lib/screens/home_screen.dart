import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/lighting_provider.dart';
import 'brightness_screen.dart';
import 'color_screen.dart';
import 'effects_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  static const _screens = [
    ColorScreen(),
    EffectsScreen(),
    BrightnessScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lightingProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('BlinkyApp'),
            const SizedBox(width: 12),
            // LED dot showing current color at current brightness
            _LedDot(color: state.displayColor),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.palette_outlined),
            selectedIcon: Icon(Icons.palette),
            label: 'Color',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Effects',
          ),
          NavigationDestination(
            icon: Icon(Icons.brightness_6_outlined),
            selectedIcon: Icon(Icons.brightness_6),
            label: 'Brightness',
          ),
        ],
      ),
    );
  }
}

class _LedDot extends StatelessWidget {
  final Color color;

  const _LedDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.7),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
