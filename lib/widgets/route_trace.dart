import 'dart:math';

import 'package:flutter/material.dart';

import '../models/run_record.dart';
import '../theme/cyber_palette.dart';
import '../theme/season.dart';
import '../theme/cyber_theme.dart';
import '../l10n/l10n.dart';

/// Draws the GPS trace as a neon filament on a grid.
///
/// There is no map here on purpose: map tiles mean a network, and the app is
/// offline by design. The shape of the route, its start and end markers and a
/// scale bar carry everything a runner actually looks at afterwards — and it
/// suits the aesthetic better than a street map would.
///
/// With [animate] the filament draws itself from the start, a lit head running
/// ahead of it, and can be replayed. The head is driven by each fix's
/// timestamp rather than by distance, so it surges on the fast stretches and
/// crawls up the hills — the replay has the shape of the run, not just its
/// outline.
class RouteTrace extends StatefulWidget {
  const RouteTrace({
    super.key,
    required this.trace,
    this.accent,
    this.height = 200,
    this.animate = false,
  });

  final List<TracePoint> trace;
  final Color? accent;
  final double height;
  final bool animate;

  /// Long enough to read as a route being retraced, short enough that nobody
  /// waits for it. The whole run is compressed into this, so relative pace is
  /// preserved while absolute duration is not — a 90-minute run would be
  /// unwatchable at any honest speed.
  static const Duration drawDuration = Duration(milliseconds: 1600);

  @override
  State<RouteTrace> createState() => _RouteTraceState();
}

class _RouteTraceState extends State<RouteTrace> with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: RouteTrace.drawDuration,
    value: widget.animate ? 0 : 1,
  );

  bool get _done => _draw.value == 1;

  /// The first draw waits for [didChangeDependencies]: `MediaQuery` cannot be
  /// read during `initState`.
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !_started) {
      _started = true;
      _start();
    }
  }

  void _start() {
    // Someone who has asked the system to stop animating gets the finished
    // route instead of a show.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _draw.value = 1;
      return;
    }
    _draw.forward(from: 0);
  }

  @override
  void didUpdateWidget(RouteTrace old) {
    super.didUpdateWidget(old);
    // A different run in the same slot redraws from the beginning.
    if (widget.trace != old.trace && widget.animate) _start();
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.trace.length < 2) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Cy.panel, border: Border.all(color: Cy.rule)),
        child: Text(L.of(context).noRouteData, style: CyType.label()),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(color: Cy.panel, border: Border.all(color: Cy.rule)),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _draw,
                builder: (context, _) => CustomPaint(
                  painter: _TracePainter(
                    trace: widget.trace,
                    accent: widget.accent ?? Cy.cyan,
                    // Linear: any easing here would be a pace the runner
                    // never ran.
                    progress: _draw.value,
                    season: Season.active,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            if (widget.animate)
              Positioned(
                right: 2,
                top: 2,
                child: AnimatedBuilder(
                  animation: _draw,
                  // Offering a replay while it is still drawing would just
                  // restart what the runner is already watching.
                  builder: (context, _) => AnimatedOpacity(
                    opacity: _done ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                      onPressed: _done ? _start : null,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      color: Cy.inkDim,
                      tooltip: L.of(context).replayRoute,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where the head sits at [progress] through the run: an index into [trace]
/// and how far from that point towards the next, 0 to 1.
///
/// Driven by each fix's own timestamp, so the head covers ground at the speed
/// it was actually covered. Falls back to even spacing for a trace whose
/// points share a timestamp, which only synthetic data does.
@visibleForTesting
(int, double) traceHeadAt(List<TracePoint> trace, double progress) {
  final first = trace.first.elapsedSeconds;
  final span = trace.last.elapsedSeconds - first;
  final p = progress.clamp(0.0, 1.0);

  if (span <= 0) {
    final at = p * (trace.length - 1);
    final index = at.floor().clamp(0, trace.length - 2);
    return (index, at - index);
  }

  final target = first + p * span;
  for (var i = 0; i < trace.length - 1; i++) {
    final from = trace[i].elapsedSeconds;
    final to = trace[i + 1].elapsedSeconds;
    if (target <= to) {
      // Two fixes sharing a timestamp would divide by zero; step over.
      return (i, to <= from ? 0.0 : (target - from) / (to - from));
    }
  }
  return (trace.length - 2, 1);
}

class _TracePainter extends CustomPainter {
  _TracePainter({required this.trace, required this.accent, this.progress = 1, this.season});

  final List<TracePoint> trace;
  final Color accent;

  /// Under SAMHAIN PROTOCOL the filament is ectoplasm, the start a candle, the
  /// finish a headstone, and the replay's head a wisp with a tail.
  final Season? season;
  bool get _samhain => season == Season.samhain;

  /// How much of the filament is drawn, 0 to 1.
  final double progress;

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

    final full = Path()..moveTo(project(trace.first).dx, project(trace.first).dy);
    for (final p in trace.skip(1)) {
      final o = project(p);
      full.lineTo(o.dx, o.dy);
    }

    // The drawn part of the filament, and where its head currently is.
    Path path = full;
    Offset? head;
    if (progress < 1) {
      final (index, fraction) = traceHeadAt(trace, progress);
      head = Offset.lerp(project(trace[index]), project(trace[index + 1]), fraction)!;
      path = Path()..moveTo(project(trace.first).dx, project(trace.first).dy);
      for (var i = 1; i <= index; i++) {
        final o = project(trace[i]);
        path.lineTo(o.dx, o.dy);
      }
      path.lineTo(head.dx, head.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = (_samhain ? Cy.green : accent).withValues(alpha: _samhain ? 0.26 : 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _samhain ? 9 : 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = _samhain ? Cy.green : accent,
    );

    final start = project(trace.first);
    if (_samhain) {
      _candle(canvas, start);
      if (head != null) {
        _wisp(canvas, head, path);
      } else {
        _headstone(canvas, project(trace.last));
      }
      return;
    }
    canvas.drawCircle(start, 5, Paint()..color = Cy.green);
    canvas.drawCircle(
      start,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Cy.green.withValues(alpha: 0.6),
    );

    if (head != null) {
      // The leading edge, so the eye knows which way the run is going.
      canvas.drawCircle(
        head,
        4,
        Paint()
          ..color = Cy.ink
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4),
      );
      return;
    }

    final end = project(trace.last);
    canvas.drawCircle(end, 5, Paint()..color = Cy.magenta);
    canvas.drawCircle(
      end,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Cy.magenta.withValues(alpha: 0.6),
    );
  }

  /// A candle stub with its flame, standing on [at].
  void _candle(Canvas canvas, Offset at) {
    canvas.drawRect(Rect.fromLTWH(at.dx - 2.5, at.dy - 6, 5, 9), Paint()..color = Cy.ink.withValues(alpha: 0.85));
    final flame = Path()
      ..moveTo(at.dx, at.dy - 15)
      ..quadraticBezierTo(at.dx + 4, at.dy - 9, at.dx, at.dy - 7)
      ..quadraticBezierTo(at.dx - 4, at.dy - 9, at.dx, at.dy - 15)
      ..close();
    canvas
      ..drawCircle(at + const Offset(0, -10), 7, Paint()..color = Cy.amber.withValues(alpha: 0.25))
      ..drawPath(flame, Paint()..color = Cy.amber);
  }

  /// A round-topped headstone with a cross cut in it, where the run ended.
  void _headstone(Canvas canvas, Offset at) {
    final stone = RRect.fromRectAndCorners(
      Rect.fromCenter(center: at + const Offset(0, -6), width: 13, height: 16),
      topLeft: const Radius.circular(6.5),
      topRight: const Radius.circular(6.5),
    );
    canvas
      ..drawRRect(stone, Paint()..color = Cy.panelHi)
      ..drawRRect(
        stone,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Cy.magenta,
      );
    final cross = Paint()
      ..color = Cy.magenta
      ..strokeWidth = 1.4;
    canvas
      ..drawLine(at + const Offset(0, -11), at + const Offset(0, -2), cross)
      ..drawLine(at + const Offset(-3, -8), at + const Offset(3, -8), cross);
  }

  /// The replay's head: a pale wisp trailing the last stretch of the route.
  void _wisp(Canvas canvas, Offset head, Path drawn) {
    final metric = drawn.computeMetrics().lastOrNull;
    if (metric != null && metric.length > 0) {
      const tail = 40.0;
      final from = max(0.0, metric.length - tail);
      for (var i = 0; i < 8; i++) {
        final d = from + (metric.length - from) * i / 8;
        final pos = metric.getTangentForOffset(d)?.position;
        if (pos == null) continue;
        canvas.drawCircle(pos, 1.5 + i * 0.4, Paint()..color = Cy.ink.withValues(alpha: 0.05 + i * 0.04));
      }
    }
    canvas.drawCircle(
      head,
      5,
      Paint()
        ..color = Cy.ink
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 7),
    );
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
  bool shouldRepaint(_TracePainter old) =>
      old.trace != trace || old.accent != accent || old.progress != progress || old.season != season;
}
