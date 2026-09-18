import 'package:flutter/material.dart';

import '../models/mission.dart';
import '../models/run_record.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';

/// A run's story, read back in order: every transmission with its lines, every
/// pursuit and how it went, every recovery, the moment the target fell.
///
/// The log stores references; the words come from [mission]. Without it — the
/// pack was removed — the moments still show, just not what was said.
class StoryLog extends StatelessWidget {
  const StoryLog({super.key, required this.story, required this.mission, required this.codexTitle});

  final List<StoryEvent> story;
  final Mission? mission;

  /// Resolves a codex id to its title, across every pack.
  final String? Function(String id) codexTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < story.length; i++)
          _Moment(event: story[i], mission: mission, codexTitle: codexTitle, last: i == story.length - 1),
      ],
    );
  }
}

class _Moment extends StatelessWidget {
  const _Moment({required this.event, required this.mission, required this.codexTitle, required this.last});

  final StoryEvent event;
  final Mission? mission;
  final String? Function(String id) codexTitle;
  final bool last;

  StoryBeat? get _beat {
    final ref = event.ref;
    if (ref == null || mission == null) return null;
    for (final beat in mission!.beats) {
      if (beat.id == ref) return beat;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final (accent, label) = switch (event.kind) {
      StoryEventKind.beat => (Cy.cyan, _beat?.headline?.toUpperCase() ?? 'TRANSMISSION'),
      StoryEventKind.chaseStarted => (Cy.magenta, 'PURSUIT — ${event.ref ?? 'UNKNOWN'}'),
      StoryEventKind.chaseEnded => (
        event.escaped == true ? Cy.green : Cy.amber,
        '${event.escaped == true ? 'EVADED' : 'CAUGHT'} — ${event.ref ?? 'UNKNOWN'}',
      ),
      StoryEventKind.codex => (Cy.cyan, 'CODEX RECOVERED — ${codexTitle(event.ref ?? '') ?? event.ref ?? ''}'),
      StoryEventKind.goal => (Cy.green, 'TARGET REACHED'),
    };
    final beat = _beat;
    final lines = event.kind == StoryEventKind.beat ? (beat?.lines ?? const <StoryLine>[]) : const <StoryLine>[];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(Fmt.clock(event.atSeconds), style: CyType.mono(size: 11, color: Cy.inkDim)),
            ),
          ),
          // The spine: a dot at this moment, a hairline down to the next.
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: glow(accent, blur: 8)),
                ),
                if (!last) Expanded(child: Container(width: 1, color: Cy.rule)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: CyType.label(size: 10, color: accent)),
                  if (event.kind == StoryEventKind.beat && beat == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Lines unavailable — the mission pack is no longer installed.',
                      style: CyType.body(size: 13, color: Cy.ghost, style: FontStyle.italic),
                    ),
                  ],
                  for (final line in lines) ...[
                    const SizedBox(height: 8),
                    Text(line.speaker.toUpperCase(), style: CyType.mono(size: 10, color: Cy.inkDim, letterSpacing: 1.4)),
                    const SizedBox(height: 2),
                    Text(line.text, style: CyType.body(size: 15, weight: FontWeight.w500, color: Cy.ink, height: 1.4)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
