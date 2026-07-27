import 'dart:math';

import 'package:flutter/material.dart';

import '../models/run_record.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';

/// Draws the GPS trace as a neon filament on a grid.
///
/// There is no map here on purpose: map tiles mean a network, and the app is
/// offline by design. The shape of the route, its start and end markers and a
/// scale bar carry everything a runner actually looks at afterwards — and it
/// suits the aesthetic better than a street map would.
class RouteTrace extends StatelessWidget {
  const RouteTrace({super.key, required this.trace, this.accent = Cy.cyan, this.height = 200});

  final List<TracePoint> trace;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (trace.length < 2) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Cy.panel, border: Border.all(color: Cy.rule)),
        child: Text('NO ROUTE DATA', style: CyType.label()),
      );
    }
    return Container(
      height: height,
      decoration: BoxDecoration(color: Cy.panel, border: Border.all(color: Cy.rule)),
      child: ClipRect(
        child: CustomPaint(
          painter: _TracePainter(trace: trace, accent: accent),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({required this.trace, required this.accent});

  final List<TracePoint> trace;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 18.0;
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLon = double.infinity, maxLon = -double.infinity;
    for (final p in trace) {
      minLat = min(minLat, p.lat);
      maxLat = max(maxLat, p.lat);
      minLon = min(minLon, p.lon);
      maxLon = max(maxLon, p.lon);
    }

    // Longitude degrees shrink with latitude; without this correction every
    // route looks stretched east-west.
    final latSpan = max(maxLat - minLat, 1e-6);
    final lonSpan = max((maxLon - minLon) * cos(((minLat + maxLat) / 2) * pi / 180), 1e-6);

    final scale = min((size.width - pad * 2) / lonSpan, (size.height - pad * 2) / latSpan);
    final offsetX = (size.width - lonSpan * scale) / 2;
    final offsetY = (size.height - latSpan * scale) / 2;

    Offset project(TracePoint p) => Offset(
      offsetX + (p.lon - minLon) * cos(((minLat + maxLat) / 2) * pi / 180) * scale,
      // Screen y grows downward, latitude grows north.
      size.height - offsetY - (p.lat - minLat) * scale,
    );

    _paintGrid(canvas, size);

    final path = Path()..moveTo(project(trace.first).dx, project(trace.first).dy);
    for (final p in trace.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );

    final start = project(trace.first);
    final end = project(trace.last);
    canvas.drawCircle(start, 5, Paint()..color = Cy.green);
    canvas.drawCircle(start, 8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Cy.green.withValues(alpha: 0.6));
    canvas.drawCircle(end, 5, Paint()..color = Cy.magenta);
    canvas.drawCircle(end, 8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Cy.magenta.withValues(alpha: 0.6));
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Cy.rule.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_TracePainter old) => old.trace != trace || old.accent != accent;
}
