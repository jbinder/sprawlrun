import 'dart:async';
import 'dart:math';

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
    required this.stamp,
    this.tag,
    this.readout,
    this.intensity = 2,
  });

  factory Unlock.achievement(AchievementDef def) => Unlock(
    kicker: 'ACHIEVEMENT UNLOCKED',
    title: def.title,
    body: def.description,
    // STREET is drawn in dim ink on the wall, where it has to recede behind the
    // rarer tiers. A reveal in grey would read as nothing happening.
    accent: def.tier == AchTier.street ? Cy.green : def.tier.color,
    icon: def.category.icon,
    stamp: 'UNLOCKED',
    tag: def.tier.label,
    // The number *is* the achievement; it gets the biggest type on screen.
    readout: def.format(def.target).toUpperCase(),
    intensity: switch (def.tier) {
      AchTier.street => 1,
      AchTier.chrome => 2,
      AchTier.ice => 3,
      AchTier.legend => 4,
    },
  );

  factory Unlock.codex(CodexEntry entry) => Unlock(
    kicker: 'CODEX ENTRY RECOVERED',
    title: entry.title,
    body: entry.body,
    accent: Cy.cyan,
    icon: Icons.memory_outlined,
    stamp: 'DECRYPTED',
    tag: entry.category,
    intensity: 2,
  );

  factory Unlock.mission(String codename) => Unlock(
    kicker: 'NEW OPERATION',
    title: codename,
    body: 'Briefing available. Your handler is waiting.',
    accent: Cy.magenta,
    icon: Icons.hexagon_outlined,
    stamp: 'OPENED',
    intensity: 3,
  );

  /// Small caps line above everything: what kind of thing this is.
  final String kicker;
  final String title;
  final String body;
  final Color accent;
  final IconData icon;

  /// Slammed across the emblem once it has booted.
  final String stamp;

  /// Tier for achievements, category for codex entries.
  final String? tag;

  /// The headline figure, if there is one — `1000 KM`, `10 H`.
  final String? readout;

  /// How much spectacle: 1 (STREET) to 4 (LEGEND). Drives the halo.
  final int intensity;
}

/// Full-screen unlock sequence: one at a time, each in its own colour, tap or
/// wait to advance. Shown over the debrief before the runner sees the numbers,
/// so the reward lands as a moment rather than as a list item.
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
    this.autoAdvance,
  });

  final List<Unlock> unlocks;
  final VoidCallback onDone;

  /// Called as each card appears — the sting lives with whoever owns audio.
  final ValueChanged<Unlock>? onShow;

  /// How long a card holds before moving on by itself. Null — the default —
  /// gives each card [holdFor] its text; zero disables auto-advance.
  final Duration? autoAdvance;

  /// A hold long enough to actually read the card: a fixed allowance for the
  /// boot animation, title and readout, plus reading time for the body at a
  /// relaxed pace. A codex entry can run to 400 characters; an achievement is
  /// one line, and should not sit there for half a minute.
  static Duration holdFor(Unlock unlock) {
    final ms = 8000 + unlock.body.length * 60;
    return Duration(milliseconds: ms.clamp(12000, 40000));
  }

  @override
  State<UnlockReveal> createState() => _UnlockRevealState();
}

class _UnlockRevealState extends State<UnlockReveal> with TickerProviderStateMixin {
  /// The card coming online: emblem ring drawing itself, content rising in,
  /// the stamp landing at the end.
  late final AnimationController _boot;

  /// Never stops: the halo breathing outward and the scanline crawling, so the
  /// screen is alive for as long as the runner looks at it.
  late final AnimationController _ambient;

  Timer? _hold;
  int _index = 0;

  Unlock get _current => widget.unlocks[_index];
  bool get _last => _index == widget.unlocks.length - 1;

  @override
  void initState() {
    super.initState();
    _boot = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _show();
  }

  void _show() {
    _hold?.cancel();
    _boot.forward(from: 0);
    widget.onShow?.call(_current);
    final hold = widget.autoAdvance ?? UnlockReveal.holdFor(_current);
    if (hold > Duration.zero) {
      _hold = Timer(hold, _advance);
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
    _ambient.dispose();
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
        color: Cy.v0id.withValues(alpha: 0.96),
        child: GridBackdrop(
          accent: accent,
          intensity: 0.55,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The halo and scanline live behind everything and never stop.
              AnimatedBuilder(
                animation: Listenable.merge([_boot, _ambient]),
                builder: (context, _) => CustomPaint(
                  painter: _HaloPainter(
                    ambient: _ambient.value,
                    boot: _boot.value,
                    accent: accent,
                    rings: 2 + unlock.intensity,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
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
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _boot,
                          builder: (context, child) {
                            // Content rises in behind the emblem, which draws
                            // itself; the two arrive as one thing switching on.
                            final t = Curves.easeOutCubic.transform((_boot.value / 0.7).clamp(0.0, 1.0));
                            return Opacity(
                              opacity: t,
                              child: Transform.translate(offset: Offset(0, 28 * (1 - t)), child: child),
                            );
                          },
                          child: Column(
                            key: ValueKey(_index),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _Emblem(unlock: unlock, boot: _boot, ambient: _ambient),
                              const SizedBox(height: 26),
                              if (unlock.tag != null) CyberTag(unlock.tag!, color: accent, filled: true),
                              const SizedBox(height: 14),
                              GlitchText(
                                unlock.title.toUpperCase(),
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                style: CyType.display(size: 27, color: Cy.ink, shadows: textGlow(accent, blur: 22)),
                              ),
                              if (unlock.readout != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  unlock.readout!,
                                  style: CyType.readout(38, accent).copyWith(shadows: textGlow(accent, blur: 26)),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: TypewriterText(
                                  key: ValueKey('body-$_index'),
                                  unlock.body,
                                  charactersPerSecond: 110,
                                  style: CyType.body(
                                    size: 15,
                                    weight: FontWeight.w500,
                                    color: Cy.inkDim,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _Progress(count: widget.unlocks.length, index: _index, accent: accent),
                      const SizedBox(height: 14),
                      if (_last)
                        CyberButton(label: 'Continue', icon: Icons.arrow_forward_rounded, onPressed: _advance)
                      else
                        Text('TAP TO CONTINUE', style: CyType.label(size: 10, color: Cy.ghost)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hexagonal containment emblem: a ring that draws itself around the icon
/// as the card boots, breathes once it is there, and takes the stamp.
class _Emblem extends StatelessWidget {
  const _Emblem({required this.unlock, required this.boot, required this.ambient});

  final Unlock unlock;
  final Animation<double> boot;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    final accent = unlock.accent;
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: Listenable.merge([boot, ambient]),
        builder: (context, _) {
          final ring = Curves.easeInOutCubic.transform((boot.value / 0.6).clamp(0.0, 1.0));
          final breathe = 0.5 + 0.5 * sin(ambient.value * 2 * pi);
          // The stamp lands late and hard: elastic from oversize to fit.
          final st = ((boot.value - 0.55) / 0.45).clamp(0.0, 1.0);
          final stampScale = 1.0 + (1.0 - Curves.elasticOut.transform(st)) * 0.9;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: const Size(200, 200),
                painter: _EmblemPainter(accent: accent, sweep: ring, breathe: breathe),
              ),
              Icon(unlock.icon, size: 68, color: accent, shadows: textGlow(accent, blur: 18 + 10 * breathe)),
              Positioned(
                top: 8,
                right: -14,
                child: Opacity(
                  opacity: (st * 3).clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: -0.22,
                    child: Transform.scale(
                      scale: stampScale,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Cy.v0id.withValues(alpha: 0.85),
                          border: Border.all(color: accent, width: 2),
                          boxShadow: glow(accent, blur: 14, opacity: 0.5),
                        ),
                        child: Text(
                          unlock.stamp,
                          style: CyType.display(size: 13, weight: 800, color: accent, letterSpacing: 4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Path _hexagon(Offset centre, double radius) {
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final a = pi / 3 * i;
    final p = centre + Offset(cos(a), sin(a)) * radius;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter({required this.accent, required this.sweep, required this.breathe});

  final Color accent;

  /// 0..1: how much of the outer ring has been drawn.
  final double sweep;
  final double breathe;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final outer = _hexagon(centre, 92);
    final inner = _hexagon(centre, 62);

    // Fill and inner hex settle in with the sweep.
    canvas.drawPath(outer, Paint()..color = accent.withValues(alpha: 0.06 * sweep));
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.35 * sweep),
    );

    // The outer ring draws itself, with a glow that breathes once complete.
    final metric = outer.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * sweep);
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = accent.withValues(alpha: 0.25 + 0.25 * breathe * sweep)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
    // A bright head on the line while it is still drawing.
    if (sweep > 0 && sweep < 1) {
      final head = metric.getTangentForOffset(metric.length * sweep)?.position;
      if (head != null) {
        canvas.drawCircle(head, 4, Paint()..color = Cy.ink);
      }
    }
  }

  @override
  bool shouldRepaint(_EmblemPainter old) => old.sweep != sweep || old.breathe != breathe || old.accent != accent;
}

/// Concentric hexagons drifting outward from the emblem for as long as the
/// screen is up, a burst on boot, and a scanline crawling down the screen.
class _HaloPainter extends CustomPainter {
  const _HaloPainter({required this.ambient, required this.boot, required this.accent, required this.rings});

  final double ambient;
  final double boot;
  final Color accent;
  final int rings;

  @override
  void paint(Canvas canvas, Size size) {
    // The emblem sits a little above centre once the text is under it.
    final centre = Offset(size.width / 2, size.height * 0.42);
    final reach = size.longestSide * 0.75;

    for (var i = 0; i < rings; i++) {
      final phase = (ambient + i / rings) % 1.0;
      final radius = 100 + (reach - 100) * Curves.easeOut.transform(phase);
      canvas.drawPath(
        _hexagon(centre, radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent.withValues(alpha: 0.22 * (1 - phase)),
      );
    }

    // The boot burst: one hard ring thrown outward as the card switches on.
    if (boot < 1) {
      final t = Curves.easeOutCubic.transform(boot);
      canvas.drawPath(
        _hexagon(centre, 90 + reach * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - t) + 0.5
          ..color = accent.withValues(alpha: 0.7 * (1 - t)),
      );
    }

    // Scanline.
    final y = size.height * ((ambient * 1.7) % 1.0);
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, 2),
      Paint()..color = accent.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.ambient != ambient || old.boot != boot || old.accent != accent || old.rings != rings;
}

/// One square per unlock, lit up to and including the current one.
class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.index, required this.accent});

  final int count;
  final int index;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox(height: 8);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: i == index ? 22 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i <= index ? accent : Cy.rule,
              boxShadow: i == index ? glow(accent, blur: 8, opacity: 0.6) : null,
            ),
          ),
      ],
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
