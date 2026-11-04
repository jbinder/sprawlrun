import 'package:flutter/painting.dart';

import 'colour_theme.dart';
import 'cyber_palette.dart';

/// A colour theme being made in the app's theme editor, before it is saved.
///
/// It starts as a copy of a theme and keeps that theme's colours as [base].
/// Most runners only want to change a handful of colours, so the editor leads
/// with the four [mainRoles]; each carries the shades that belong to it
/// ([shadesOf]), and moving a main colour moves them with it, the same
/// distance in hue, saturation and lightness as they sat from it in [base].
/// That keeps the copied theme's character — how much lighter its panels are
/// than its background — instead of guessing one. Every role can still be set
/// on its own; a main colour moved afterwards takes its shades along again.
class ThemeDraft {
  ThemeDraft({required this.base, required this.name, this.id, this.author})
    : colours = ColourTheme.rolesOf(base);

  /// The draft of [theme] itself, for changing a theme the runner made or
  /// imported in place: saved under its own [id].
  ThemeDraft.of(ColourTheme theme)
    : base = theme.palette,
      name = theme.name,
      id = theme.id,
      author = theme.author,
      colours = ColourTheme.rolesOf(theme.palette);

  /// The colours the draft started from.
  final CyPalette base;

  /// The id it is saved under, when it replaces a theme; null for a new one.
  final String? id;
  final String? author;
  String name;

  /// Every role's colour as it stands, keyed as a theme file's `colours`.
  final Map<String, Color> colours;

  /// The colours offered first, each with the shades it carries.
  static const Map<String, List<String>> shadesOf = {
    'background': ['panel', 'panelRaised', 'rule'],
    'primary': ['primaryDim'],
    'hostile': ['hostileDim'],
    'story': [],
  };

  static Iterable<String> get mainRoles => shadesOf.keys;

  CyPalette get palette => ColourTheme.paletteOf(colours);

  /// Why the draft cannot be saved yet, or null when it can.
  LegibilityIssue? get issue => ColourTheme.legibilityIssue(palette);

  bool get changed {
    final start = ColourTheme.rolesOf(base);
    return colours.entries.any((e) => start[e.key] != e.value);
  }

  /// Sets [role] to [colour], taking the shades of a main colour along.
  void set(String role, Color colour) {
    final start = ColourTheme.rolesOf(base);
    for (final shade in shadesOf[role] ?? const <String>[]) {
      colours[shade] = shift(colour, from: start[role]!, to: start[shade]!);
    }
    colours[role] = colour;
  }

  /// [colour] moved as far in hue, saturation and lightness as [to] lies
  /// from [from].
  static Color shift(Color colour, {required Color from, required Color to}) {
    final a = HSLColor.fromColor(from), b = HSLColor.fromColor(to), c = HSLColor.fromColor(colour);
    return HSLColor.fromAHSL(
      1,
      (c.hue + b.hue - a.hue) % 360,
      (c.saturation + b.saturation - a.saturation).clamp(0.0, 1.0),
      (c.lightness + b.lightness - a.lightness).clamp(0.0, 1.0),
    ).toColor();
  }

  /// The draft as a theme, under [id] (or this draft's own).
  ColourTheme toTheme(String id) =>
      ColourTheme(id: this.id ?? id, name: name.trim(), author: author, palette: palette);
}
