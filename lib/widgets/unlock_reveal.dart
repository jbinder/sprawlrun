import 'dart:async';

import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../models/mission.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../widgets/backdrop.dart';
import '../widgets/glitch_text.dart';
import '../widgets/panels.dart';

/// One thing a run earned, ready to be shown.
///
/// Everything the reveal needs and nothing else, so the widget does not have to
/// know what an achievement or a codex entry is — only how to present a card.
class Unlock {
  const Unlock({
    required this.kicker,
    required this.title,
    required this.body,
    required this.accent,
    required this.icon,
    this.tag,
  });

  factory Unlock.achievement(AchievementDef def) => Unlock(
    kicker: 'ACHIEVEMENT UNLOCKED',
    title: def.title,
    body: def.description,
    // STREET is drawn in dim ink on the wall, where it has to recede behind the
    // rarer tiers. A reveal in grey would read as nothing happening.
    accent: def.tier == AchTier.street ? Cy.green : def.tier.color,
    icon: def.category.icon,
    tag: def.tier.label,
  );

  factory Unlock.codex(CodexEntry entry) => Unlock(
    kicker: 'CODEX ENTRY RECOVERED',
    title: entry.title,
    body: entry.body,
    accent: Cy.cyan,
    icon: Icons.memory_outlined,
    tag: entry.category,
  );

  factory Unlock.mission(String codename) => Unlock(
    kicker: 'NEW OPERATION',
    title: codename,
    body: 'Briefing available. Your handler is waiting.',
    accent: Cy.magenta,
    icon: Icons.hexagon_outlined,
  );

  /// Small caps line above the card: what kind of thing this is.
  final String kicker;
  final String title;
  final String body;
  final Color accent;
  final IconData icon;

  /// Tier for achievements, category for codex entries.
  final String? tag;
}

/// Full-screen unlock sequence: one card at a time, each in its own colour,
/// tap or wait to advance. Shown over the debrief before the runner sees the
/// numbers, so the reward lands as a moment rather than as a list item.
///
/// The runner has stopped by now, so this can afford to demand the screen —
/// unlike anything during a run, where the voice is the only channel that
/// reliably reaches them.
class UnlockReveal extends StatefulWidget {
  const UnlockReveal({
    super.key,
    required this.unlocks,
    required this.onDone,
    this.onShow,
    this.autoAdvance = const Duration(seconds: 6),
  });

  final List<Unlock> unlocks;
  final VoidCallback onDone;

  /// Called as each card appears — the sting lives with whoever owns audio.
  final ValueChanged<Unlock>? onShow;

  /// How long a card holds before moving on by itself. Zero disables it.
  final Duration autoAdvance;

  @override
  State<UnlockReveal> createState() => _UnlockRevealState();
}

class _UnlockRevealState extends State<UnlockReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _boot;
  Timer? _hold;
  int _index = 0;

  Unlock get _current => widget.unlocks[_index];
  bool get _last => _index == widget.unlocks.length - 1;

  @override
  void initState() {
    super.initState();
    _boot = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _show();
  }

  void _show() {
    _hold?.cancel();
    _boot.forward(from: 0);
    widget.onShow?.call(_current);
    if (widget.autoAdvance > Duration.zero) {
      _hold = Timer(widget.autoAdvance, _advance);
    }
  }

  void _advance() {
    if (!mounted) return;
    if (_last) {
      _hold?.cancel();
      widget.onDone();
      return;
    }
    setState(() => _index++);
    _show();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _boot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlock = _current;
    final accent = unlock.accent;
    final counter =
        '${(_index + 1).toString().padLeft(2, '0')} / ${widget.unlocks.length.toString().padLeft(2, '0')}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _advance,
      child: ColoredBox(
        color: Cy.v0id.withValues(alpha: 0.94),
        child: GridBackdrop(
          accent: accent,
          intensity: 0.7,
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _boot,
              builder: (context, child) {
                // Cards boot in: fade, rise, and settle from slightly small —
                // a screen coming online rather than a dialog appearing.
                final t = Curves.easeOutCubic.transform(_boot.value);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 24 * (1 - t)),
                    child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(unlock.kicker, style: CyType.label(size: 11, color: accent))),
                        Text(counter, style: CyType.mono(size: 11, color: Cy.inkDim, letterSpacing: 1.6)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _BootRule(progress: _boot, accent: accent),
                    const Spacer(),
                    NeonPanel(
                      key: ValueKey(_index),
                      accent: accent,
                      lit: true,
                      cut: 18,
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.10),
                                  border: Border.all(color: accent),
                                  boxShadow: glow(accent, blur: 22, opacity: 0.55),
                                ),
                                child: Icon(unlock.icon, size: 30, color: accent),
                              ),
                              const SizedBox(width: 16),
                              if (unlock.tag != null) CyberTag(unlock.tag!, color: accent, filled: true),
                            ],
                          ),
                          const SizedBox(height: 20),
                          GlitchText(
                            unlock.title.toUpperCase(),
                            style: CyType.display(size: 24, color: Cy.ink, shadows: textGlow(accent, blur: 18)),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 14),
                          TypewriterText(
                            key: ValueKey('body-$_index'),
                            unlock.body,
                            style: CyType.body(size: 15, weight: FontWeight.w500, color: Cy.inkDim, height: 1.4),
                            charactersPerSecond: 110,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (_last)
                      CyberButton(label: 'Continue', icon: Icons.arrow_forward_rounded, onPressed: _advance)
                    else
                      Text('TAP TO CONTINUE', style: CyType.label(size: 10, color: Cy.ghost)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline that draws itself across under the kicker as the card boots.
class _BootRule extends StatelessWidget {
  const _BootRule({required this.progress, required this.accent});

  final Animation<double> progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) => Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: Curves.easeOutQuart.transform(progress.value),
          child: Container(height: 1, color: accent),
        ),
      ),
    );
  }
}
