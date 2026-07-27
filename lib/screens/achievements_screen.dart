import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/achievement.dart';
import '../models/stats.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/panels.dart';
import '../widgets/progress.dart';

/// The wall. Earned first, then whatever is closest to falling.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  AchCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wall = state.achievementWall;
    final shown = _filter == null ? wall : wall.where((v) => v.def.category == _filter).toList();
    final earned = wall.where((v) => v.earned).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        _WallHeader(earned: earned, total: wall.length),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'ALL',
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              for (final category in AchCategory.values) ...[
                const SizedBox(width: 8),
                _FilterChip(
                  label: category.label,
                  icon: category.icon,
                  selected: _filter == category,
                  onTap: () => setState(() => _filter = category),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final view in shown) ...[
          _AchievementCard(view: view, stats: state.lifetime),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _WallHeader extends StatelessWidget {
  const _WallHeader({required this.earned, required this.total});

  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      accent: earned == total ? Cy.amber : Cy.rule,
      lit: earned == total,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$earned', style: CyType.readout(36, Cy.amber)),
              Text(' / $total', style: CyType.mono(size: 16, color: Cy.inkDim)),
              const Spacer(),
              Text('UNLOCKED', style: CyType.label(size: 10)),
            ],
          ),
          const SizedBox(height: 12),
          ThinBar(progress: total == 0 ? 0 : earned / total, color: Cy.amber, height: 4),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Cy.cyan : Cy.panel,
          border: Border.all(color: selected ? Cy.cyan : Cy.rule),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? Cy.v0id : Cy.inkDim),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: CyType.mono(size: 10, color: selected ? Cy.v0id : Cy.inkDim, letterSpacing: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.view, required this.stats});

  final AchievementView view;
  final LifetimeStats stats;

  @override
  Widget build(BuildContext context) {
    final def = view.def;
    final tier = def.tier.color;
    final accent = view.earned ? tier : Cy.rule;

    return NeonPanel(
      accent: accent,
      cut: 10,
      fill: view.earned ? Cy.panel : Cy.v0id,
      lit: view.earned && def.tier == AchTier.legend,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: view.earned ? tier.withValues(alpha: 0.14) : Colors.transparent,
              border: Border.all(color: view.earned ? tier : Cy.rule),
            ),
            child: Icon(def.category.icon, size: 18, color: view.earned ? tier : Cy.ghost),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        def.title,
                        style: CyType.body(
                          size: 15,
                          weight: FontWeight.w700,
                          color: view.earned ? Cy.ink : Cy.inkDim,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CyberTag(def.tier.label, color: view.earned ? tier : Cy.ghost),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  def.description,
                  style: CyType.body(size: 13, color: view.earned ? Cy.inkDim : Cy.ghost, height: 1.3),
                ),
                const SizedBox(height: 9),
                if (view.earned)
                  Row(
                    children: [
                      const Icon(Icons.check, size: 12, color: Cy.green),
                      const SizedBox(width: 6),
                      Text(
                        view.earnedAt == null
                            ? 'UNLOCKED'
                            : 'UNLOCKED ${Fmt.date(view.earnedAt!)}',
                        style: CyType.mono(size: 10, color: Cy.green),
                      ),
                    ],
                  )
                else ...[
                  ThinBar(progress: view.progress, color: tier.withValues(alpha: 0.8)),
                  const SizedBox(height: 5),
                  Text(def.progressLabel(stats), style: CyType.mono(size: 10, color: Cy.ghost)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
