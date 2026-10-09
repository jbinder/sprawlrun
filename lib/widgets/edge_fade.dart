import 'package:flutter/material.dart';

/// Fades the top or bottom edge of a vertical scroller while that edge still
/// hides content — the same signal the filter rails give sideways (see
/// `filter_rail.dart`). A list that fits shows no fade at all, and each edge
/// clears once it is scrolled to its end.
///
/// Without it a long list simply stopped at the filter rail or the bottom of
/// the screen, and nothing said there was more — a runner noticed it in THE
/// WIRE. It is applied to every vertical scroller through
/// [CyberScrollBehavior], so a new screen gets it without asking.
class EdgeFade extends StatefulWidget {
  const EdgeFade({super.key, required this.child});

  final Widget child;

  @override
  State<EdgeFade> createState() => EdgeFadeState();
}

class EdgeFadeState extends State<EdgeFade> {
  bool _moreAbove = false;
  bool _moreBelow = false;

  /// Which edges are faded right now, for tests.
  bool get moreAbove => _moreAbove;
  bool get moreBelow => _moreBelow;

  /// Shorter than the rail's 56: a list row is far shorter than it is wide.
  static const double _fade = 32;

  bool _onMetrics(ScrollMetrics m) {
    final above = m.pixels > m.minScrollExtent + 1;
    final below = m.pixels < m.maxScrollExtent - 1;
    if (above != _moreAbove || below != _moreBelow) {
      setState(() {
        _moreAbove = above;
        _moreBelow = below;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Only this scroller's own notifications: a scroller nested inside it
    // (a filter rail, say) reports at a greater depth and is ignored.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
        // Always a ShaderMask, even with nothing to fade: swapping it in and
        // out would rebuild the scroller underneath and lose its position.
        child: ShaderMask(
          shaderCallback: (bounds) {
            final f = bounds.height <= 0 ? 0.0 : (_fade / bounds.height).clamp(0.0, 0.5);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
              stops: [0, _moreAbove ? f : 0, _moreBelow ? 1 - f : 1, 1],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The app's scroll behaviour: Material's, with [EdgeFade] on every vertical
/// scroller. Horizontal ones are left alone — the filter rails fade their own
/// edges and add a chevron, and a single-line text field must not fade at all.
///
/// Used by the app and by the screenshot tool, so the published shots show the
/// screens as they really look.
class CyberScrollBehavior extends MaterialScrollBehavior {
  const CyberScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    final indicator = super.buildOverscrollIndicator(context, child, details);
    if (axisDirectionToAxis(details.direction) != Axis.vertical) return indicator;
    return EdgeFade(child: indicator);
  }
}
