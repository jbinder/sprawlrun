import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/cyber_palette.dart';

/// The city under everything: a slow perspective grid, a horizon glow, and a
/// scanline wash.
///
/// One animation drives all three layers and runs at a deliberately low
/// frequency — this sits behind every screen, including a 40-minute run HUD, so
/// it is built to be cheap and to never demand a repaint of its children.
class GridBackdrop extends StatefulWidget {
  const GridBackdrop({super.key, required this.child, this.accent = Cy.cyan, this.intensity = 1.0});

  final Widget child;
  final Color accent;

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
                  accent: widget.accent,
                  intensity: widget.intensity,
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
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.phase, required this.accent, required this.intensity});

  final double phase;
  final Color accent;
  final double intensity;

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
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.phase != phase || old.accent != accent || old.intensity != intensity;
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
