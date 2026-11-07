import 'package:flutter/material.dart';

/// One line of text that scrolls slowly back and forth when it does not fit,
/// resting at each end long enough to be read, and sits still when it does.
class ScrollingText extends StatefulWidget {
  const ScrollingText(this.text, {super.key, required this.style});

  /// Slow enough to read while running.
  static const double pixelsPerSecond = 22;
  static const Duration rest = Duration(seconds: 3);

  final String text;
  final TextStyle style;

  @override
  State<ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<ScrollingText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  double _overflow = 0;
  Animation<double> _offset = const AlwaysStoppedAnimation(0);

  void _fit(double overflow) {
    if ((overflow - _overflow).abs() < 0.5) return;
    _overflow = overflow;
    if (overflow <= 0) {
      _controller.stop();
      _offset = const AlwaysStoppedAnimation(0);
      return;
    }
    final travel = overflow / ScrollingText.pixelsPerSecond;
    final rest = ScrollingText.rest.inMilliseconds / 1000;
    _controller.duration = Duration(milliseconds: ((travel + rest) * 2 * 1000).round());
    // Weights are seconds: rest, along, rest, back.
    _offset = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0), weight: rest),
      TweenSequenceItem(tween: Tween(begin: 0, end: overflow), weight: travel),
      TweenSequenceItem(tween: ConstantTween(overflow), weight: rest),
      TweenSequenceItem(tween: Tween(begin: overflow, end: 0), weight: travel),
    ]).animate(_controller);
    _controller.repeat();
  }

  @override
  void didUpdateWidget(ScrollingText old) {
    super.didUpdateWidget(old);
    // A new title starts from its beginning.
    if (old.text != widget.text) _controller.value = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      _fit(painter.width - constraints.maxWidth);
      final height = painter.height;
      final text = Text(widget.text, maxLines: 1, softWrap: false, style: widget.style);
      if (_overflow <= 0) return SizedBox(height: height, child: Align(alignment: Alignment.centerLeft, child: text));
      return SizedBox(
        height: height,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: text,
            ),
            builder: (context, child) => Transform.translate(offset: Offset(-_offset.value, 0), child: child),
          ),
        ),
      );
    },
  );
}
