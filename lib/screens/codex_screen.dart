import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mission.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../widgets/panels.dart';
import '../widgets/progress.dart';

/// World-building recovered by playing. Entries only appear once the beat that
/// mentions them has actually been heard, so the codex is a record of what the
/// runner has been told rather than a wiki.
class CodexScreen extends StatelessWidget {
  const CodexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.unlockedCodex;
    final total = state.codexTotal;

    if (entries.isEmpty) {
      return const EmptyState(
        title: 'Nothing recovered yet',
        body: 'Intel gets logged here as your handlers mention it. Run an operation and start listening.',
        icon: Icons.menu_book_outlined,
      );
    }

    final byCategory = <String, List<CodexEntry>>{};
    for (final entry in entries) {
      byCategory.putIfAbsent(entry.category, () => []).add(entry);
    }
    final categories = byCategory.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        NeonPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${entries.length}', style: CyType.readout(30, Cy.cyan)),
                  Text(' / $total', style: CyType.mono(size: 15, color: Cy.inkDim)),
                  const Spacer(),
                  Text('ENTRIES RECOVERED', style: CyType.label(size: 10)),
                ],
              ),
              const SizedBox(height: 12),
              ThinBar(progress: total == 0 ? 0 : entries.length / total, color: Cy.cyan, height: 4),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final category in categories) ...[
          SectionHeader(category),
          for (final entry in byCategory[category]!) ...[
            _CodexCard(entry: entry),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CodexCard extends StatefulWidget {
  const _CodexCard({required this.entry});

  final CodexEntry entry;

  @override
  State<_CodexCard> createState() => _CodexCardState();
}

class _CodexCardState extends State<_CodexCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      cut: 10,
      accent: _open ? Cy.cyanDim : Cy.rule,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_open ? Icons.folder_open_outlined : Icons.folder_outlined, size: 16, color: Cy.cyanDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.entry.title, style: CyType.body(size: 15, weight: FontWeight.w700)),
              ),
              Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: Cy.ghost),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                widget.entry.body,
                style: CyType.body(size: 15, color: Cy.inkDim, height: 1.5),
              ),
            ),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}
