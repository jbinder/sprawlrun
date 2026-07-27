import 'package:flutter/material.dart';

import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';

/// Clips the corners off a rectangle, which is the single shape the entire UI
/// is built from. [cut] is the bite taken out of each chosen corner.
class NotchedBorder extends ShapeBorder {
  const NotchedBorder({
    this.cut = 12,
    this.topLeft = false,
    this.topRight = true,
    this.bottomLeft = true,
    this.bottomRight = false,
    this.side = BorderSide.none,
  });

  final double cut;
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final c = cut;
    final path = Path()..moveTo(rect.left + (topLeft ? c : 0), rect.top);
    path.lineTo(rect.right - (topRight ? c : 0), rect.top);
    if (topRight) path.lineTo(rect.right, rect.top + c);
    path.lineTo(rect.right, rect.bottom - (bottomRight ? c : 0));
    if (bottomRight) path.lineTo(rect.right - c, rect.bottom);
    path.lineTo(rect.left + (bottomLeft ? c : 0), rect.bottom);
    if (bottomLeft) path.lineTo(rect.left, rect.bottom - c);
    path.lineTo(rect.left, rect.top + (topLeft ? c : 0));
    if (topLeft) path.lineTo(rect.left + c, rect.top);
    return path..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      getOuterPath(rect.deflate(side.width / 2), textDirection: textDirection),
      side.toPaint()..style = PaintingStyle.stroke,
    );
  }

  @override
  ShapeBorder scale(double t) => NotchedBorder(
    cut: cut * t,
    topLeft: topLeft,
    topRight: topRight,
    bottomLeft: bottomLeft,
    bottomRight: bottomRight,
    side: side.scale(t),
  );
}

/// The standard surface: notched, hairlined, optionally lit.
class NeonPanel extends StatelessWidget {
  const NeonPanel({
    super.key,
    required this.child,
    this.accent = Cy.rule,
    this.padding = const EdgeInsets.all(16),
    this.fill = Cy.panel,
    this.lit = false,
    this.cut = 14,
    this.onTap,
  });

  final Widget child;
  final Color accent;
  final EdgeInsets padding;
  final Color fill;

  /// Adds the outer glow. Reserved for things that are active or urgent.
  final bool lit;
  final double cut;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = NotchedBorder(cut: cut, side: BorderSide(color: accent, width: 1));
    final panel = DecoratedBox(
      decoration: ShapeDecoration(
        color: fill,
        shape: shape,
        shadows: lit ? glow(accent, blur: 22, opacity: 0.22) : null,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return panel;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        splashColor: accent.withValues(alpha: 0.12),
        child: panel,
      ),
    );
  }
}

/// `▸ SECTION NAME ─────────` with an optional trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.accent = Cy.cyan, this.trailing});

  final String title;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 3, height: 13, color: accent),
          const SizedBox(width: 8),
          Text(title.toUpperCase(), style: CyType.label(color: accent, size: 12)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: Cy.rule)),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// A labelled readout: small caps label, big mono value, optional unit.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.accent = Cy.ink,
    this.size = 26,
  });

  final String label;
  final String value;
  final String? unit;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: CyType.label(size: 10)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: CyType.readout(size, accent)),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!, style: CyType.mono(size: 11, color: Cy.inkDim)),
            ],
          ],
        ),
      ],
    );
  }
}

enum CyberButtonStyle { primary, ghost, danger }

/// Notched, monospaced, deliberately physical-feeling button.
class CyberButton extends StatelessWidget {
  const CyberButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.style = CyberButtonStyle.primary,
    this.expand = true,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final CyberButtonStyle style;
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = switch (style) {
      CyberButtonStyle.primary => Cy.cyan,
      CyberButtonStyle.ghost => Cy.inkDim,
      CyberButtonStyle.danger => Cy.magenta,
    };
    final color = enabled ? accent : Cy.ghost;
    final filled = style == CyberButtonStyle.primary && enabled;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: dense ? 15 : 18, color: filled ? Cy.v0id : color),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: CyType.display(
              size: dense ? 11 : 13,
              weight: 700,
              color: filled ? Cy.v0id : color,
              letterSpacing: 2.0,
            ),
          ),
        ),
      ],
    );

    final shape = NotchedBorder(cut: dense ? 8 : 11, side: BorderSide(color: color, width: 1.2));

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        customBorder: shape,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: filled ? accent : accent.withValues(alpha: enabled ? 0.07 : 0.0),
            shape: shape,
            shadows: filled ? glow(accent, blur: 16, opacity: 0.3) : null,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 18, vertical: dense ? 8 : 14),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Small status word in a box: `LOCKED`, `CLEARED`, `ACTIVE`.
class CyberTag extends StatelessWidget {
  const CyberTag(this.text, {super.key, this.color = Cy.cyan, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.5)),
      ),
      child: Text(
        text.toUpperCase(),
        style: CyType.mono(size: 10, color: filled ? Cy.v0id : color, letterSpacing: 1.6),
      ),
    );
  }
}

/// Full-bleed empty state with a bit of attitude.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.body, this.icon = Icons.blur_on});

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Cy.ghost),
            const SizedBox(height: 16),
            Text(title.toUpperCase(), style: CyType.display(size: 14, color: Cy.inkDim)),
            const SizedBox(height: 10),
            Text(body, textAlign: TextAlign.center, style: CyType.body(size: 15, color: Cy.ghost)),
          ],
        ),
      ),
    );
  }
}
