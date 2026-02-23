import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/mock_data.dart';
import '../models/blinky_effect.dart';
import '../providers/lighting_provider.dart';
import '../widgets/effect_card.dart';

class EffectsScreen extends ConsumerStatefulWidget {
  const EffectsScreen({super.key});

  @override
  ConsumerState<EffectsScreen> createState() => _EffectsScreenState();
}

class _EffectsScreenState extends ConsumerState<EffectsScreen> {
  String _selectedCategory = 'All';

  List<BlinkyEffect> get _filtered {
    if (_selectedCategory == 'All') return kMockEffects;
    return kMockEffects
        .where((e) => e.category == _selectedCategory)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lightingProvider);
    final notifier = ref.read(lightingProvider.notifier);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Effects',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${kMockEffects.length} effects available',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                // Category filter chips
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final cat = kCategories[i];
                      final selected = _selectedCategory == cat;
                      return FilterChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = cat),
                        showCheckmark: false,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemCount: _filtered.length,
            itemBuilder: (context, i) {
              final effect = _filtered[i];
              final isActive = state.activeEffect == effect.name;
              return EffectCard(
                name: effect.name,
                icon: effect.icon,
                category: effect.category,
                isActive: isActive,
                onTap: () {
                  if (isActive) {
                    notifier.clearEffect();
                  } else {
                    notifier.activateEffect(effect.name);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
