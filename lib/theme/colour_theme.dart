import 'dart:convert';

import 'package:flutter/painting.dart';

import '../l10n/l10n.dart';
import 'cyber_palette.dart';

/// A colour theme the runner can pick in Settings: a name and a [CyPalette].
///
/// NEON is built in, since it is the default and what draws the app before
/// anything has loaded. Every other theme is one JSON file — shipped in
/// `assets/themes/`, or imported by the runner — in the format described in
/// docs/THEMES.md. A season in force wears its own palette over whichever is
/// picked.
class ColourTheme {
  const ColourTheme({
    required this.id,
    required this.name,
    required this.palette,
    this.names = const {},
    this.author,
  });

  /// Stored in `Profile.theme`, and the file name an import is kept under.
  final String id;

  /// Shown under the swatch in any language [names] does not cover.
  final String name;

  /// The name in other languages, by language code, where the theme gives
  /// one. Optional: a name that reads as a name everywhere needs none.
  final Map<String, String> names;

  /// The name to show in [language].
  String nameIn(String language) => names[language] ?? name;

  /// Who made it, if the file says.
  final String? author;
  final CyPalette palette;

  static const neon = ColourTheme(id: 'neon', name: 'NEON', names: {'es': 'NEÓN'}, palette: CyPalette.standard);

  /// Longest name that still fits under a swatch at 360 dp.
  static const int maxNameLength = 16;

  /// The keys of the `colours` block, each a role rather than a hue, in the
  /// order docs/THEMES.md lists them.
  static const List<String> roles = [
    'background',
    'panel',
    'panelRaised',
    'rule',
    'primary',
    'primaryDim',
    'hostile',
    'hostileDim',
    'story',
    'success',
    'failure',
    'locked',
    'text',
    'textDim',
  ];

  /// Reads a theme file. Throws [ThemeFormatException] with a message fit to
  /// show the runner for anything that is not a usable theme, including one
  /// whose text would be unreadable — a theme that hides the very picker that
  /// could undo it is worse than none.
  factory ColourTheme.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw ThemeFormatException(l10n.fileNotJson);
    }
    if (decoded is! Map || decoded['colours'] is! Map) throw ThemeFormatException(l10n.themeErrorNotATheme);

    final id = decoded['id'];
    if (id is! String || !RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(id)) {
      throw ThemeFormatException(l10n.themeErrorBadId);
    }
    final name = decoded['name'];
    if (name is! String || name.trim().isEmpty || name.trim().length > maxNameLength) {
      throw ThemeFormatException(l10n.themeErrorBadName(maxNameLength));
    }
    final author = decoded['author'];
    final rawNames = decoded['names'] ?? const {};
    if (rawNames is! Map) throw ThemeFormatException(l10n.themeErrorNames);
    final names = <String, String>{};
    for (final MapEntry(key: language, value: text) in rawNames.entries) {
      if (language is! String || !RegExp(r'^[a-z]{2,3}$').hasMatch(language) || text is! String) {
        throw ThemeFormatException(l10n.themeErrorNames);
      }
      if (text.trim().isEmpty || text.trim().length > maxNameLength) {
        throw ThemeFormatException(l10n.themeErrorBadName(maxNameLength));
      }
      names[language] = text.trim();
    }

    final raw = decoded['colours'] as Map;
    for (final key in raw.keys) {
      if (!roles.contains(key)) throw ThemeFormatException(l10n.themeErrorUnknownRole('$key'));
    }
    final colours = <String, Color>{};
    for (final role in roles) {
      final value = raw[role];
      if (value == null) throw ThemeFormatException(l10n.themeErrorMissingRole(role));
      final colour = value is String ? parseColour(value) : null;
      if (colour == null) throw ThemeFormatException(l10n.themeErrorBadColour(role, '$value'));
      colours[role] = colour;
    }

    final palette = CyPalette(
      v0id: colours['background']!,
      panel: colours['panel']!,
      panelHi: colours['panelRaised']!,
      rule: colours['rule']!,
      cyan: colours['primary']!,
      cyanDim: colours['primaryDim']!,
      magenta: colours['hostile']!,
      magentaDim: colours['hostileDim']!,
      amber: colours['story']!,
      green: colours['success']!,
      red: colours['failure']!,
      ghost: colours['locked']!,
      ink: colours['text']!,
      inkDim: colours['textDim']!,
    );
    final problem = legibilityProblem(palette);
    if (problem != null) throw ThemeFormatException(problem);

    return ColourTheme(
      id: id,
      name: name.trim(),
      names: names,
      author: author is String && author.trim().isNotEmpty ? author.trim() : null,
      palette: palette,
    );
  }

  /// `#RRGGBB`, opaque only: a translucent panel would show the backdrop
  /// through every screen.
  static Color? parseColour(String value) {
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value.trim());
    return match == null ? null : Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }

  /// Minimum contrast against a panel, as WCAG measures it, for each role a
  /// runner has to read. Set just under what the shipped themes manage, so
  /// they pass with room and a theme that cannot be read mid-run does not.
  static const double minTextContrast = 7;
  static const double minDimTextContrast = 4.5;
  static const double minAccentContrast = 4;

  /// Why [palette] cannot be read, or null if it can: body text, secondary
  /// text and every accent role against the panel they sit on, and the five
  /// accent roles each a colour of their own.
  static String? legibilityProblem(CyPalette p) {
    String? low(String role, Color c, double min) =>
        contrast(c, p.panel) < min ? l10n.themeErrorContrast(role, min.toStringAsFixed(1)) : null;
    final accents = {'primary': p.cyan, 'hostile': p.magenta, 'story': p.amber, 'success': p.green, 'failure': p.red};
    final found =
        low('text', p.ink, minTextContrast) ??
        low('textDim', p.inkDim, minDimTextContrast) ??
        [for (final e in accents.entries) low(e.key, e.value, minAccentContrast)].nonNulls.firstOrNull;
    if (found != null) return found;
    final seen = <Color, String>{};
    for (final MapEntry(key: role, value: colour) in accents.entries) {
      final other = seen[colour];
      if (other != null) return l10n.themeErrorSameColour(other, role);
      seen[colour] = role;
    }
    return null;
  }

  /// WCAG contrast ratio, 1 to 21.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }
}

/// A theme file that cannot be used, with a message fit to show the runner.
class ThemeFormatException implements Exception {
  ThemeFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}
