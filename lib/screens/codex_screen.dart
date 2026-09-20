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
///
/// One section per pack, the active campaign open and first, the others folded
/// to a header — each pack is its own world with its own categories, and intel
/// from a finished campaign stays readable after moving on.
class CodexScreen extends StatefulWidget {
  const CodexScreen({super.key});

  @override
  State<CodexScreen> createState() => _CodexScreenState();
}

class _CodexScreenState extends State<CodexScreen> {
  /// Packs whose entries are shown. Seeded with the active pack on first
  /// build, then the runner's own choice.
  Set<String>? _open;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activePack;
    _open ??= {if (active != null) active.id};

    if (state.unlockedCodex.isEmpty) {
      return const EmptyState(
        title: 'Nothing recovered yet',
        body: 'Intel gets logged here as your handlers mention it. Run an operation and start listening.',
        icon: Icons.menu_book_outlined,
      );
    }

    // Active campaign first; the rest in load order.
    final packs = [
      ?active,
      for (final pack in state.packs)
        if (pack.id != active?.id) pack,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: [
        for (final pack in packs) ...[
          _PackSection(
            pack: pack,
            unlocked: state.profile.unlockedCodex,
            selected: pack.id == active?.id,
            open: _open!.contains(pack.id),
            onToggle: () => setState(() {
              if (!_open!.remove(pack.id)) _open!.add(pack.id);
            }),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// A pack's recovered intel under a header that always shows the count; the
/// entries themselves only when open.
class _PackSection extends StatelessWidget {
  const _PackSection({
    required this.pack,
    required this.unlocked,
    required this.selected,
    required this.open,
    required this.onToggle,
  });

  final MissionPack pack;
  final Set<String> unlocked;
  final bool selected;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final all = [for (final m in pack.missions) ...m.codex];
    final entries = all.where((e) => unlocked.contains(e.id)).toList();

    final byCategory = <String, List<CodexEntry>>{};
    for (final entry in entries) {
      byCategory.putIfAbsent(entry.category, () => []).add(entry);
    }
    final categories = byCategory.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeonPanel(
          accent: open ? Cy.cyanDim : Cy.rule,
          onTap: onToggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pack.title,
                      overflow: TextOverflow.ellipsis,
                      style: CyType.display(size: 14, color: open ? Cy.ink : Cy.inkDim),
                    ),
                  ),
                  if (selected) ...[
                    const CyberTag('ACTIVE', color: Cy.cyan),
                    const SizedBox(width: 8),
                  ],
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: Cy.ghost),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${entries.length}', style: CyType.readout(26, Cy.cyan)),
                  Text(' / ${all.length}', style: CyType.mono(size: 14, color: Cy.inkDim)),
                  const Spacer(),
                  Text('ENTRIES RECOVERED', style: CyType.label(size: 10)),
                ],
              ),
              const SizedBox(height: 10),
              ThinBar(progress: all.isEmpty ? 0 : entries.length / all.length, color: Cy.cyan, height: 4),
            ],
          ),
        ),
        if (open) ...[
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                'Nothing recovered from this campaign yet.',
                style: CyType.body(size: 14, color: Cy.ghost),
              ),
            ),
          for (final category in categories) ...[
            SectionHeader(category),
            for (final entry in byCategory[category]!) ...[
              _CodexCard(entry: entry),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
          ],
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
