import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/cyber_palette.dart';

/// Text that occasionally tears into RGB-split copies of itself.
///
/// Glitches are rare and short by default — the effect is a punctuation mark,
/// not a texture. [alwaysOn] shortens the interval for moments that should feel
/// genuinely unstable (a chase opening, a containment failure).
class GlitchText extends StatefulWidget {
  const GlitchText(
    this.text, {
    super.key,
    this.style,
    this.alwaysOn = false,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final bool alwaysOn;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  State<GlitchText> createState() => _GlitchTextState();
}

class _GlitchTextState extends State<GlitchText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  final Random _random = Random();
  double _offset = 0;
  Timer? _next;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!mounted) return;
      setState(() => _offset = (1 - _controller.value) * (_random.nextDouble() * 3.5 + 1.2));
    });
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _schedule();
    });
    _schedule();
  }

  void _schedule() {
    _next?.cancel();
    final gap = widget.alwaysOn
        ? Duration(milliseconds: 500 + _random.nextInt(1200))
        : Duration(milliseconds: 3500 + _random.nextInt(7000));
    // Held so it can be cancelled on dispose — an orphaned timer would keep
    // firing into a dead State.
    _next = Timer(gap, () {
      if (!mounted) return;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    Widget layer(Color color, double dx) => Positioned(
      left: dx,
      child: Text(
        widget.text,
        style: style.copyWith(color: color.withValues(alpha: 0.75), shadows: const []),
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_offset > 0.05) ...[
          layer(Cy.magenta, -_offset),
          layer(Cy.cyan, _offset),
        ],
        Text(
          widget.text,
          style: style,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
        ),
      ],
    );
  }
}

/// Reveals text character by character, like a terminal printing it.
///
/// Used for mission briefs and story lines. The speed is tuned to be faster
/// than reading pace so it never becomes an obstacle between the runner and
/// the words.
class TypewriterText extends StatefulWidget {
  const TypewriterText(
    this.text, {
    super.key,
    this.style,
    this.charactersPerSecond = 90,
    this.onComplete,
  });

  final String text;
  final TextStyle? style;
  final double charactersPerSecond;
  final VoidCallback? onComplete;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _durationFor(widget.text))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onComplete?.call();
      })
      ..forward();
  }

  Duration _durationFor(String text) =>
      Duration(milliseconds: (text.length / widget.charactersPerSecond * 1000).round().clamp(200, 20000));

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _controller
        ..duration = _durationFor(widget.text)
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shown = (widget.text.length * _controller.value).round();
        return RichText(
          text: TextSpan(
            style: widget.style ?? DefaultTextStyle.of(context).style,
            children: [
              TextSpan(text: widget.text.substring(0, shown)),
              // The untyped remainder is laid out transparently so the block
              // does not reflow as it fills in.
              TextSpan(
                text: widget.text.substring(shown),
                style: const TextStyle(color: Colors.transparent),
              ),
            ],
          ),
        );
      },
    );
  }
}
