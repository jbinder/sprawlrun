import 'package:flutter/material.dart';

import '../models/mission.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import 'panels.dart';

/// Pieces the briefing and the debriefing share, so the two read as the same
/// place seen before and after.

class OpsBar extends StatelessWidget {
  const OpsBar({super.key, required this.mission, required this.label});

  final Mission? mission;

  /// What this screen is: BRIEFING, DEBRIEFING.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Cy.inkDim),
          ),
          const Spacer(),
          Text(
            mission == null
                ? 'UNLOGGED RUN'
                : 'OPERATION ${mission!.order.toString().padLeft(2, '0')} · $label',
            style: CyType.label(size: 10),
          ),
        ],
      ),
    );
  }
}

class InfoCell extends StatelessWidget {
  const InfoCell({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      cut: 8,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Cy.inkDim),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: CyType.readout(16, Cy.ink)),
          ),
          const SizedBox(height: 3),
          Text(label.toUpperCase(), style: CyType.label(size: 8)),
        ],
      ),
    );
  }
}

/// What this mission has to tell you, and how much of it you have heard.
///
/// Recovered entries show by name. The rest show only as encrypted — a count
/// of what is left is motivation; a title would be a spoiler.
class IntelSection extends StatelessWidget {
  const IntelSection({
    super.key,
    required this.mission,
    required this.recovered,
  });

  final Mission mission;
  final Set<String> recovered;

  @override
  Widget build(BuildContext context) {
    final have = mission.codex.where((e) => recovered.contains(e.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'INTEL  $have / ${mission.codex.length}',
          accent: Cy.cyan,
        ),
        for (final entry in mission.codex)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: recovered.contains(entry.id)
                ? NeonPanel(
                    accent: Cy.cyan,
                    cut: 8,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.memory_outlined,
                          size: 16,
                          color: Cy.cyan,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.title,
                            style: CyType.body(
                              size: 14,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        CyberTag(entry.category, color: Cy.cyan),
                      ],
                    ),
                  )
                : NeonPanel(
                    accent: Cy.rule,
                    cut: 8,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: Cy.ghost,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '▮▮▮▮▮▮  ENCRYPTED',
                          style: CyType.mono(
                            size: 12,
                            color: Cy.ghost,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }
}
