import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mission_repository.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../widgets/backdrop.dart';
import '../widgets/glitch_text.dart';
import '../widgets/panels.dart';
import 'mission_brief_screen.dart';
import 'mission_debrief_screen.dart';
import '../l10n/l10n.dart';

/// Every mission pack, grouped by whether there is anything left to run in it.
///
/// Tapping a pack makes it the one the ops screen shows and opens its mission
/// list; tapping a playable mission goes straight to its briefing or debrief.
/// Packs that are fully cleared sink to a DONE section so the list stays
/// about what is next, however many packs accumulate.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  /// The pack whose missions are unfolded. Starts on the selected one.
  String? _open;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final packs = state.packProgress;
    _open ??= state.activePack?.id;

    final active = packs.where((p) => !p.isDone).toList();
    final done = packs.where((p) => p.isDone).toList();

    return Scaffold(
      body: GridBackdrop(
        accent: Cy.magenta,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back, color: Cy.inkDim),
                    ),
                    const Spacer(),
                    Text(
                      L.of(context).missionPacksCount(packs.length),
                      style: CyType.label(size: 10),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  children: [
                    if (packs.isEmpty)
                      EmptyState(
                        title: L.of(context).noPacksTitle,
                        body: L.of(context).noPacksBody,
                        icon: Icons.sync_problem_outlined,
                      ),
                    if (active.isNotEmpty) ...[
                      SectionHeader(L.of(context).activeTag, accent: Cy.magenta),
                      for (final p in active) _pack(state, p),
                      const SizedBox(height: 10),
                    ],
                    if (done.isNotEmpty) ...[
                      SectionHeader(L.of(context).tagDone, accent: Cy.green),
                      for (final p in done) _pack(state, p),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pack(AppState state, PackProgress progress) => _PackCard(
    progress: progress,
    open: _open == progress.pack.id,
    onTap: () {
      setState(
        () => _open = _open == progress.pack.id ? null : progress.pack.id,
      );
      state.selectPack(progress.pack.id);
    },
  );
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.progress,
    required this.open,
    required this.onTap,
  });

  final PackProgress progress;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pack = progress.pack;
    final accent = switch (progress.state) {
      PackState.done => Cy.green,
      PackState.active => Cy.magenta,
      PackState.fresh => Cy.cyan,
    };
    final stateLabel = switch (progress.state) {
      PackState.done => L.of(context).tagDone,
      PackState.active => L.of(context).tagInProgress,
      PackState.fresh => L.of(context).tagNew,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NeonPanel(
        accent: progress.selected ? accent : Cy.rule,
        lit: progress.selected,
        cut: 12,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and tags share a line while they fit; once a translation
            // makes the tags too wide, they drop below rather than squeezing
            // the title to a letter per line.
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowSpacing: 8,
              children: [
                GlitchText(
                  pack.title,
                  style: CyType.display(
                    size: 18,
                    color: Cy.ink,
                    shadows: textGlow(accent, blur: 12),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (progress.selected) ...[
                      CyberTag(L.of(context).tagSelected, color: Cy.amber, filled: true),
                      const SizedBox(width: 6),
                    ],
                    CyberTag(stateLabel, color: accent),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              pack.tagline,
              style: CyType.body(size: 14, color: Cy.inkDim, height: 1.3),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRect(
                    child: Container(
                      height: 4,
                      color: Cy.rule,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress.total == 0
                            ? 0
                            : progress.completed / progress.total,
                        child: Container(color: accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${progress.completed} / ${progress.total}',
                  style: CyType.mono(
                    size: 11,
                    color: Cy.inkDim,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Cy.ghost,
                ),
              ],
            ),
            if (open) ...[
              const SizedBox(height: 14),
              for (final m in progress.chain) _MissionLine(progress: m),
            ],
          ],
        ),
      ),
    );
  }
}

class _MissionLine extends StatelessWidget {
  const _MissionLine({required this.progress});

  final MissionProgress progress;

  @override
  Widget build(BuildContext context) {
    final mission = progress.mission;
    final locked = progress.state == MissionState.locked;
    final (accent, label) = switch (progress.status) {
      MissionStatus.finished => (Cy.green, L.of(context).tagDone),
      MissionStatus.started => (Cy.amber, L.of(context).tagStarted),
      MissionStatus.fresh => (
        locked ? Cy.ghost : Cy.cyan,
        locked ? L.of(context).tagLocked : L.of(context).tagNew,
      ),
    };

    return InkWell(
      onTap: locked
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => progress.state == MissionState.completed
                    ? MissionDebriefScreen(mission: mission)
                    : MissionBriefScreen(mission: mission),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                mission.order.toString().padLeft(2, '0'),
                style: CyType.mono(
                  size: 11,
                  color: locked ? Cy.ghost : Cy.inkDim,
                ),
              ),
            ),
            Expanded(
              child: Text(
                locked ? '█████████' : mission.codename,
                style: CyType.body(
                  size: 14,
                  weight: FontWeight.w700,
                  color: locked ? Cy.ghost : Cy.ink,
                ),
              ),
            ),
            if (progress.attempts > 1 && !locked)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '×${progress.attempts}',
                  style: CyType.mono(size: 10, color: Cy.inkDim),
                ),
              ),
            CyberTag(label, color: accent),
          ],
        ),
      ),
    );
  }
}
