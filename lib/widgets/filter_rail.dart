import 'package:flutter/material.dart';

import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';

// Shared by the WALL's category filter and THE WIRE's kind filter, so the two
// rails look and behave the same — including the faded edge and chevron that
// say there is more, which a runner once failed to notice on the WALL.

/// A horizontally scrolling row that says so: the chips fade out at an edge
/// that still hides some, with a chevron on the trailing side. Both go away
/// once the rail is scrolled to that end, so a row that fits shows nothing.
class FilterRail extends StatefulWidget {
  const FilterRail({super.key, required this.children, required this.padding});

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  State<FilterRail> createState() => _FilterRailState();
}

class _FilterRailState extends State<FilterRail> {
  final _controller = ScrollController();
  bool _moreLeft = false;
  bool _moreRight = false;

  static const double _fade = 56;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    // The extent is only known once laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final left = pos.pixels > 1;
    final right = pos.pixels < pos.maxScrollExtent - 1;
    if (left != _moreLeft || right != _moreRight) {
      setState(() {
        _moreLeft = left;
        _moreRight = right;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0, _moreLeft ? _fade / bounds.width : 0, _moreRight ? 1 - _fade / bounds.width : 1, 1],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            child: Row(children: widget.children),
          ),
        ),
        if (_moreLeft) const _RailArrow(Icons.chevron_left, Alignment.centerLeft),
        if (_moreRight) const _RailArrow(Icons.chevron_right, Alignment.centerRight),
      ],
    );
  }
}

/// The `‹` / `›` sitting over a faded edge. Ignores pointers so the chips
/// underneath stay tappable and the rail still scrolls from here.
class _RailArrow extends StatelessWidget {
  const _RailArrow(this.icon, this.alignment);

  final IconData icon;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(icon, size: 16, color: Cy.inkDim),
        ),
      ),
    );
  }
}

class RailChip extends StatelessWidget {
  const RailChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Cy.cyan : Cy.panel,
          border: Border.all(color: selected ? Cy.cyan : Cy.rule),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? Cy.v0id : Cy.inkDim),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: CyType.mono(size: 10, color: selected ? Cy.v0id : Cy.inkDim, letterSpacing: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
