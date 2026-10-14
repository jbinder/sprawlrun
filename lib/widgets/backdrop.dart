import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/cyber_palette.dart';
import '../theme/season.dart';

/// The city under everything: a slow perspective grid, a horizon glow, and a
/// scanline wash.
///
/// One animation drives all three layers and runs at a deliberately low
/// frequency — this sits behind every screen, including a 40-minute run HUD, so
/// it is built to be cheap and to never demand a repaint of its children.
///
/// A season dresses the street: under SAMHAIN PROTOCOL a moon hangs over the
/// vanishing point, a graveyard skyline sits on the horizon, fog drifts across
/// the grid, and every couple of minutes someone who is no longer running
/// runs past. All of it is gradients and paths — no blur filters, which would
/// cost a full-screen pass every frame of a long run.
class GridBackdrop extends StatefulWidget {
  const GridBackdrop({super.key, required this.child, this.accent, this.intensity = 1.0});

  final Widget child;
  final Color? accent;

  /// Scales every layer's opacity. The run HUD dims it so telemetry stays
  /// readable in daylight.
  final double intensity;

  @override
  State<GridBackdrop> createState() => _GridBackdropState();
}

class _GridBackdropState extends State<GridBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  /// Completed sweeps of [_controller], so something can happen every few of
  /// them rather than every 24 seconds.
  int _cycle = 0;
  double _lastPhase = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.value < _lastPhase) _cycle++;
      _lastPhase = _controller.value;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _GridPainter(
                  phase: _controller.value,
                  accent: widget.accent ?? Cy.cyan,
                  intensity: widget.intensity,
                  season: Season.active,
                  cycle: _cycle,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ScanlinePainter(intensity: widget.intensity)),
          ),
        ),
        widget.child,
        // The one layer drawn over the content: things that lurk at the edges.
        // Faint, never in the way of a tap, and kept off the dimmed screens —
        // the run HUD and the unlock reveal — where reading comes first.
        if (Season.active == Season.samhain && widget.intensity >= 0.9)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _LurkerPainter(phase: _controller.value, cycle: _cycle),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A sheet-ghost, [size] tall, centred on [at]: round head, a hem that
/// ripples with [wave], two hollow eyes and a small round mouth. [look] shifts
/// the eyes sideways, -1 to 1.
void _ghost(Canvas canvas, Offset at, double size, double alpha, {double wave = 0, double look = 0}) {
  final w = size * 0.72;
  final top = at.dy - size / 2;
  final left = at.dx - w / 2;
  final hem = at.dy + size / 2;
  final body = Path()
    ..moveTo(left, top + w / 2)
    ..arcToPoint(Offset(left + w, top + w / 2), radius: Radius.circular(w / 2))
    ..lineTo(left + w, hem);
  // Three scallops along the hem, rippling.
  for (var i = 3; i > 0; i--) {
    final x0 = left + w * i / 3;
    final x1 = left + w * (i - 1) / 3;
    final dip = size * 0.1 * (1 + 0.5 * sin(2 * pi * wave + i * 2.1));
    body.quadraticBezierTo((x0 + x1) / 2, hem - dip * (i.isEven ? 1 : -0.4), x1, hem);
  }
  body.close();
  // A pale glow first, so it reads as lit from within rather than as a shadow.
  final halo = Rect.fromCircle(center: at, radius: size);
  canvas
    ..drawCircle(
      at,
      size,
      Paint()
        ..shader = RadialGradient(
          colors: [Cy.green.withValues(alpha: 0.12 * alpha), Cy.green.withValues(alpha: 0)],
        ).createShader(halo),
    )
    ..drawPath(body, Paint()..color = Cy.ink.withValues(alpha: 0.42 * alpha))
    ..drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Cy.green.withValues(alpha: 0.35 * alpha),
    );
  final eye = Paint()..color = Cy.v0id.withValues(alpha: 0.85 * alpha);
  final eyeY = top + w * 0.5;
  final dx = look * w * 0.08;
  canvas
    ..drawOval(Rect.fromCenter(center: Offset(at.dx - w * 0.17 + dx, eyeY), width: w * 0.14, height: w * 0.2), eye)
    ..drawOval(Rect.fromCenter(center: Offset(at.dx + w * 0.17 + dx, eyeY), width: w * 0.14, height: w * 0.2), eye)
    ..drawOval(Rect.fromCenter(center: Offset(at.dx + dx, eyeY + w * 0.26), width: w * 0.1, height: w * 0.14), eye);
}

/// A jack-o'-lantern, [size] wide, sitting on [base]: lobed, stalked, with a
/// carved face lit from inside. [flicker] 0..1 is the candle.
void paintPumpkin(Canvas canvas, Offset base, double size, double alpha, double flicker) {
  final h = size * 0.78;
  final centre = base - Offset(0, h / 2);
  final skin = Paint()..color = Color.lerp(Cy.cyan, Cy.v0id, 0.35)!.withValues(alpha: alpha);
  final rib = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = Cy.v0id.withValues(alpha: 0.6 * alpha);
  for (final (dx, w) in [(-0.22, 0.6), (0.22, 0.6), (0.0, 0.62)]) {
    final lobe = Rect.fromCenter(center: centre + Offset(dx * size, 0), width: w * size, height: h);
    canvas
      ..drawOval(lobe, skin)
      ..drawOval(lobe, rib);
  }
  canvas.drawRect(
    Rect.fromLTWH(centre.dx - size * 0.04, centre.dy - h / 2 - size * 0.12, size * 0.08, size * 0.14),
    Paint()..color = Cy.green.withValues(alpha: 0.8 * alpha),
  );
  // The face, lit: two triangle eyes and a jagged grin.
  final light = Paint()..color = Cy.amber.withValues(alpha: (0.65 + 0.35 * flicker) * alpha);
  final s = size;
  Path tri(double cx, double cy) => Path()
    ..moveTo(cx, cy - s * 0.09)
    ..lineTo(cx + s * 0.08, cy + s * 0.05)
    ..lineTo(cx - s * 0.08, cy + s * 0.05)
    ..close();
  final grin = Path()..moveTo(centre.dx - s * 0.24, centre.dy + h * 0.08);
  for (var i = 0; i <= 6; i++) {
    grin.lineTo(centre.dx - s * 0.24 + s * 0.08 * i, centre.dy + h * (i.isEven ? 0.2 : 0.12));
  }
  grin
    ..lineTo(centre.dx + s * 0.24, centre.dy + h * 0.08)
    ..quadraticBezierTo(centre.dx, centre.dy + h * 0.3, centre.dx - s * 0.24, centre.dy + h * 0.08)
    ..close();
  canvas
    ..drawCircle(centre, size * 0.7, Paint()..color = Cy.amber.withValues(alpha: 0.06 * flicker * alpha))
    ..drawPath(tri(centre.dx - s * 0.14, centre.dy - h * 0.08), light)
    ..drawPath(tri(centre.dx + s * 0.14, centre.dy - h * 0.08), light)
    ..drawPath(grin, light);
}

/// A jack-o'-lantern sitting on whatever [child]'s top edge is — a card's
/// border, the nav bar's rule — while SAMHAIN PROTOCOL is in force, and
/// nothing at all otherwise.
///
/// It sits above the edge, in the gap, so it never covers what the card says.
/// Placed by hand on a few things rather than on every panel: a decoration,
/// not wallpaper.
class PumpkinPerch extends StatelessWidget {
  const PumpkinPerch({super.key, required this.child, this.left, this.right, this.size = 22});

  final Widget child;
  final double? left;
  final double? right;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (Season.active != Season.samhain) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: left,
          right: right,
          // The pumpkin's base on the edge, a pixel into the border.
          top: -_PerchedPumpkin.heightFor(size) + 1,
          child: IgnorePointer(child: _PerchedPumpkin(size: size)),
        ),
      ],
    );
  }
}

class _PerchedPumpkin extends StatefulWidget {
  const _PerchedPumpkin({required this.size});

  final double size;

  /// Body plus stalk.
  static double heightFor(double size) => size * 0.78 + size * 0.12;

  @override
  State<_PerchedPumpkin> createState() => _PerchedPumpkinState();
}

class _PerchedPumpkinState extends State<_PerchedPumpkin> with SingleTickerProviderStateMixin {
  // Its own candle, so two pumpkins never flicker in step.
  late final AnimationController _candle = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 2600 + widget.size.round() * 37),
  )..repeat();

  @override
  void dispose() {
    _candle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _candle,
        builder: (context, _) {
          final t = _candle.value;
          final flicker = 0.5 + 0.5 * sin(2 * pi * t * 3) * sin(2 * pi * t * 7 + 1.3);
          return CustomPaint(
            size: Size(size * 1.1, _PerchedPumpkin.heightFor(size)),
            painter: _PumpkinPainter(size: size, flicker: flicker),
          );
        },
      ),
    );
  }
}

class _PumpkinPainter extends CustomPainter {
  _PumpkinPainter({required this.size, required this.flicker});

  final double size;
  final double flicker;

  @override
  void paint(Canvas canvas, Size box) =>
      paintPumpkin(canvas, Offset(box.width / 2, box.height), size, 1, flicker);

  @override
  bool shouldRepaint(_PumpkinPainter old) => old.flicker != flicker || old.size != size;
}

/// What lurks over the content: on one sweep in three a ghost peeks in from
/// a screen edge and thinks better of it; on another, one drifts up the whole
/// screen, swaying. Long stretches of nothing in between, so it stays a
/// surprise rather than a screensaver.
class _LurkerPainter extends CustomPainter {
  _LurkerPainter({required this.phase, required this.cycle});

  final double phase;
  final int cycle;

  @override
  void paint(Canvas canvas, Size size) {
    switch (cycle % 3) {
      case 0:
        _peek(canvas, size);
      case 1:
        _drift(canvas, size);
    }
  }

  void _peek(Canvas canvas, Size size) {
    const start = 0.25, end = 0.6;
    if (phase < start || phase > end) return;
    final t = (phase - start) / (end - start);
    // In, a long look, and away: out faster than in.
    final reveal = t < 0.3 ? Curves.easeOut.transform(t / 0.3) : (t < 0.75 ? 1.0 : 1 - Curves.easeIn.transform((t - 0.75) / 0.25));
    final fromRight = cycle % 6 == 0;
    const ghost = 64.0;
    final x = fromRight ? size.width + ghost * 0.4 - ghost * 0.75 * reveal : -ghost * 0.4 + ghost * 0.75 * reveal;
    final y = size.height * (fromRight ? 0.58 : 0.4);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate((fromRight ? -1 : 1) * 0.25 * reveal);
    _ghost(canvas, Offset.zero, ghost, reveal, wave: phase * 6, look: fromRight ? -1 : 1);
    canvas.restore();
  }

  void _drift(Canvas canvas, Size size) {
    final fade = sin(pi * phase);
    final y = size.height * (1.05 - 1.2 * phase);
    final x = size.width * (cycle % 2 == 0 ? 0.25 : 0.7) + sin(2 * pi * phase * 2) * 30;
    _ghost(canvas, Offset(x, y), 46, 0.75 * fade, wave: phase * 10, look: sin(2 * pi * phase * 3));
  }

  @override
  bool shouldRepaint(_LurkerPainter old) => old.phase != phase || old.cycle != cycle;
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.phase,
    required this.accent,
    required this.intensity,
    this.season,
    this.cycle = 0,
  });

  final double phase;
  final Color accent;
  final double intensity;
  final Season? season;
  final int cycle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Horizon: a bruise of colour low in the frame, like light pollution.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Cy.v0id,
            Cy.v0id,
            Color.lerp(Cy.v0id, accent, 0.06 * intensity)!,
            Color.lerp(Cy.v0id, Cy.magenta, 0.05 * intensity)!,
          ],
          stops: const [0.0, 0.55, 0.86, 1.0],
        ).createShader(rect),
    );

    final horizon = size.height * 0.62;
    if (season == Season.samhain) _paintMoon(canvas, size, horizon);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.07 * intensity);

    // Verticals converge on a vanishing point; the scene reads as a street.
    final vanish = Offset(size.width / 2, horizon);
    for (var i = -8; i <= 8; i++) {
      final x = size.width / 2 + i * size.width / 7;
      canvas.drawLine(Offset(x, size.height), vanish, grid);
    }

    // Horizontals scroll toward the viewer, spaced by a power curve so they
    // bunch up near the horizon the way perspective actually behaves.
    for (var i = 0; i < 14; i++) {
      final t = ((i + phase) / 14).clamp(0.0, 1.0);
      final y = horizon + pow(t, 2.4).toDouble() * (size.height - horizon);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        grid..color = accent.withValues(alpha: 0.09 * t * intensity),
      );
    }

    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      Paint()
        ..color = accent.withValues(alpha: 0.16 * intensity)
        ..strokeWidth = 1,
    );

    if (season == Season.samhain) {
      _paintSkyline(canvas, size, horizon);
      _paintFog(canvas, size, horizon);
      _paintRevenant(canvas, size, horizon);
    }
  }

  /// A low moon behind the vanishing point, the grid running toward it.
  void _paintMoon(Canvas canvas, Size size, double horizon) {
    final r = size.width * 0.17;
    final centre = Offset(size.width * 0.66, horizon - r * 0.55);
    final halo = Rect.fromCircle(center: centre, radius: r * 2.6);
    canvas.drawCircle(
      centre,
      r * 2.6,
      Paint()
        ..shader = RadialGradient(
          colors: [Cy.amber.withValues(alpha: 0.09 * intensity), Cy.amber.withValues(alpha: 0)],
        ).createShader(halo),
    );
    final disc = Rect.fromCircle(center: centre, radius: r);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [Cy.amber.withValues(alpha: 0.2 * intensity), Cy.amber.withValues(alpha: 0.08 * intensity)],
        ).createShader(disc),
    );
    // Maria: a few darker patches, fixed, so it reads as a moon not a lamp.
    final mare = Paint()..color = Cy.v0id.withValues(alpha: 0.12 * intensity);
    canvas.drawCircle(centre + Offset(-r * 0.3, -r * 0.2), r * 0.22, mare);
    canvas.drawCircle(centre + Offset(r * 0.25, r * 0.15), r * 0.3, mare);
    canvas.drawCircle(centre + Offset(-r * 0.1, r * 0.45), r * 0.14, mare);

    // Bats, crossing in front of it on looping paths, wings beating.
    final bat = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Cy.ink.withValues(alpha: 0.35 * intensity);
    for (var i = 0; i < 3; i++) {
      final p = (phase * (2 + i) + i * 0.37) % 1.0;
      final at = centre + Offset((p - 0.5) * r * 5, sin(2 * pi * p * 2 + i) * r * 0.6 - r * 0.3 * i);
      final beat = sin(2 * pi * phase * 60 * (1 + i * 0.2));
      final span = 5.0 + i;
      final wing = span * 0.6 * beat;
      canvas.drawPath(
        Path()
          ..moveTo(at.dx - span, at.dy - wing)
          ..quadraticBezierTo(at.dx - span / 2, at.dy + 1, at.dx, at.dy)
          ..quadraticBezierTo(at.dx + span / 2, at.dy + 1, at.dx + span, at.dy - wing),
        bat,
      );
    }
  }

  /// Headstones, crosses and one dead tree along the horizon. Laid out from a
  /// fixed seed, so the graveyard is the same on every screen and every day.
  void _paintSkyline(Canvas canvas, Size size, double horizon) {
    final fill = Paint()..color = Cy.v0id;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.22 * intensity);
    final rnd = Random(31);
    var x = -8.0;
    while (x < size.width) {
      final w = 8 + rnd.nextDouble() * 10;
      final h = 7 + rnd.nextDouble() * 14;
      final path = Path();
      switch (rnd.nextInt(5)) {
        case 0:
          // A cross.
          final cx = x + w / 2;
          path
            ..addRect(Rect.fromLTWH(cx - 1.5, horizon - h - 4, 3, h + 4))
            ..addRect(Rect.fromLTWH(cx - w * 0.4, horizon - h + 1, w * 0.8, 3));
        case 1 when x > size.width * 0.1 && x < size.width * 0.3:
          // The tree, once.
          path
            ..moveTo(x + 2, horizon)
            ..lineTo(x + 4, horizon - 30)
            ..lineTo(x - 6, horizon - 44)
            ..lineTo(x + 5, horizon - 33)
            ..lineTo(x + 7, horizon - 52)
            ..lineTo(x + 8, horizon - 34)
            ..lineTo(x + 20, horizon - 46)
            ..lineTo(x + 9, horizon - 28)
            ..lineTo(x + 8, horizon)
            ..close();
        default:
          // A headstone, round-topped.
          path.addRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTWH(x, horizon - h, w, h),
              topLeft: Radius.circular(w / 2),
              topRight: Radius.circular(w / 2),
            ),
          );
      }
      canvas.drawPath(path, fill);
      canvas.drawPath(path, rim);
      x += w + 6 + rnd.nextDouble() * 34;
    }

  }

  /// Three soft banks of fog sliding across the street at different speeds.
  void _paintFog(Canvas canvas, Size size, double horizon) {
    for (var i = 0; i < 3; i++) {
      final drift = sin(2 * pi * (phase + i / 3)) * size.width * 0.25;
      final centre = Offset(size.width * (0.2 + 0.3 * i) + drift, horizon + (size.height - horizon) * (0.1 + 0.3 * i));
      final rect = Rect.fromCenter(center: centre, width: size.width * 1.3, height: size.height * 0.16);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [Cy.magenta.withValues(alpha: 0.07 * intensity), Cy.magenta.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
  }

  /// Every fifth sweep — about every two minutes — a pale runner crosses the
  /// horizon and is gone.
  void _paintRevenant(Canvas canvas, Size size, double horizon) {
    if (cycle % 5 != 2) return;
    const start = 0.15, end = 0.85;
    if (phase < start || phase > end) return;
    final t = (phase - start) / (end - start);
    final fade = sin(pi * t);
    final x = size.width * (-0.05 + 1.1 * t);
    final stride = sin(2 * pi * t * 22);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = Cy.green.withValues(alpha: 0.35 * fade * intensity);
    const h = 16.0;
    final hip = Offset(x, horizon - h * 0.5);
    final neck = Offset(x + 1.5, horizon - h * 0.88);
    canvas
      ..drawLine(hip, neck, paint)
      ..drawCircle(neck + const Offset(0.8, -2.6), 2.2, paint..style = PaintingStyle.fill)
      ..drawLine(hip, Offset(x + 5 * stride, horizon), paint..style = PaintingStyle.stroke)
      ..drawLine(hip, Offset(x - 5 * stride, horizon), paint)
      ..drawLine(neck + const Offset(0, 3), neck + Offset(-4 * stride, 8), paint)
      ..drawLine(neck + const Offset(0, 3), neck + Offset(4 * stride, 8), paint);
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.phase != phase ||
      old.accent != accent ||
      old.intensity != intensity ||
      old.season != season ||
      old.cycle != cycle;
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter({required this.intensity});

  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.16 * intensity)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Vignette: the corners of a cheap CRT.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5 * intensity)],
          stops: const [0.6, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.intensity != intensity;
}
