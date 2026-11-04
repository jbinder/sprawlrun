import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colour_theme.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../l10n/l10n.dart';

/// Picks an opaque colour: a saturation/brightness field, a hue strip and the
/// hex code, all three kept in step.
///
/// Written here rather than taken from a package: it is small, and a theme
/// only ever needs opaque `#RRGGBB`, which is all this offers.
class ColourPicker extends StatefulWidget {
  const ColourPicker({super.key, required this.initial, required this.onChanged});

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<ColourPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(text: _hexOf(widget.initial));

  static String _hexOf(Color c) => ColourTheme.hex(c).substring(1);

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor hsv, {bool fromHex = false}) {
    setState(() => _hsv = hsv);
    final colour = hsv.toColor();
    if (!fromHex) _hex.text = _hexOf(colour);
    widget.onChanged(colour);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1.6,
          child: LayoutBuilder(
            builder: (context, box) {
              void at(Offset p) => _set(
                _hsv
                    .withSaturation((p.dx / box.maxWidth).clamp(0.0, 1.0))
                    .withValue(1 - (p.dy / box.maxHeight).clamp(0.0, 1.0)),
              );
              return GestureDetector(
                onPanDown: (d) => at(d.localPosition),
                onPanUpdate: (d) => at(d.localPosition),
                child: CustomPaint(painter: _FieldPainter(_hsv), size: Size.infinite),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 28,
          child: LayoutBuilder(
            builder: (context, box) {
              void at(Offset p) => _set(_hsv.withHue((p.dx / box.maxWidth).clamp(0.0, 1.0) * 359.9));
              return GestureDetector(
                onPanDown: (d) => at(d.localPosition),
                onPanUpdate: (d) => at(d.localPosition),
                child: CustomPaint(painter: _HuePainter(_hsv.hue), size: Size.infinite),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                border: Border.all(color: Cy.rule),
              ),
            ),
            const SizedBox(width: 12),
            Text('#', style: CyType.mono(size: 16, color: Cy.inkDim)),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _hex,
                maxLength: 6,
                style: CyType.mono(size: 16, color: Cy.ink),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  labelText: l.themePickerHex,
                  labelStyle: CyType.body(size: 12, color: Cy.inkDim),
                  border: OutlineInputBorder(borderSide: BorderSide(color: Cy.rule), borderRadius: BorderRadius.zero),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Cy.rule),
                    borderRadius: BorderRadius.zero,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Cy.cyan),
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                onChanged: (text) {
                  final colour = ColourTheme.parseColour('#$text');
                  if (colour != null) _set(HSVColor.fromColor(colour), fromHex: true);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [Colors.white, hue]).createShader(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
    final at = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(at, 9, Paint()..color = const Color(0xFF000000)..style = PaintingStyle.stroke..strokeWidth = 4);
    canvas.drawCircle(at, 9, Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.hsv != hsv;
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360.0, 1, 1).toColor()],
        ).createShader(rect),
    );
    final x = hue / 360 * size.width;
    final mark = Rect.fromCenter(center: Offset(x, size.height / 2), width: 6, height: size.height + 4);
    canvas.drawRect(mark, Paint()..color = const Color(0xFF000000)..style = PaintingStyle.stroke..strokeWidth = 4);
    canvas.drawRect(mark, Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}
