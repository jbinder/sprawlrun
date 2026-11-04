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

    final palette = paletteOf(colours);
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

  /// [palette] by role, the keys of a theme file's `colours` block.
  static Map<String, Color> rolesOf(CyPalette p) => {
    'background': p.v0id,
    'panel': p.panel,
    'panelRaised': p.panelHi,
    'rule': p.rule,
    'primary': p.cyan,
    'primaryDim': p.cyanDim,
    'hostile': p.magenta,
    'hostileDim': p.magentaDim,
    'story': p.amber,
    'success': p.green,
    'failure': p.red,
    'locked': p.ghost,
    'text': p.ink,
    'textDim': p.inkDim,
  };

  /// The palette for a full set of [roles].
  static CyPalette paletteOf(Map<String, Color> c) => CyPalette(
    v0id: c['background']!,
    panel: c['panel']!,
    panelHi: c['panelRaised']!,
    rule: c['rule']!,
    cyan: c['primary']!,
    cyanDim: c['primaryDim']!,
    magenta: c['hostile']!,
    magentaDim: c['hostileDim']!,
    amber: c['story']!,
    green: c['success']!,
    red: c['failure']!,
    ghost: c['locked']!,
    ink: c['text']!,
    inkDim: c['textDim']!,
  );

  /// `#RRGGBB`, as a theme file writes a colour.
  static String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// This theme as a theme file, ready to import on another phone.
  String toJson() => const JsonEncoder.withIndent('  ').convert({
    'id': id,
    'name': name,
    if (names.isNotEmpty) 'names': names,
    'author': ?author,
    'colours': {for (final MapEntry(:key, :value) in rolesOf(palette).entries) key: hex(value)},
  });

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
  static String? legibilityProblem(CyPalette p) => switch (legibilityIssue(p)) {
    null => null,
    LowContrast(:final role, :final needed) => l10n.themeErrorContrast(role, needed.toStringAsFixed(1)),
    SameColour(:final first, :final second) => l10n.themeErrorSameColour(first, second),
  };

  /// The first thing that makes [p] hard to read, by role, or null. The theme
  /// editor words it for the runner; [legibilityProblem] for a theme author.
  static LegibilityIssue? legibilityIssue(CyPalette p) {
    final checks = {
      'text': (p.ink, minTextContrast),
      'textDim': (p.inkDim, minDimTextContrast),
      'primary': (p.cyan, minAccentContrast),
      'hostile': (p.magenta, minAccentContrast),
      'story': (p.amber, minAccentContrast),
      'success': (p.green, minAccentContrast),
      'failure': (p.red, minAccentContrast),
    };
    for (final MapEntry(key: role, value: (colour, min)) in checks.entries) {
      final ratio = contrast(colour, p.panel);
      if (ratio < min) return LowContrast(role, ratio, min);
    }
    final seen = <Color, String>{};
    for (final role in const ['primary', 'hostile', 'story', 'success', 'failure']) {
      final colour = checks[role]!.$1;
      final other = seen[colour];
      if (other != null) return SameColour(other, role);
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

/// Why a palette cannot be read; see [ColourTheme.legibilityIssue].
sealed class LegibilityIssue {
  const LegibilityIssue();
}

/// [role] stands out from the panel by only [ratio]:1, and needs [needed]:1.
class LowContrast extends LegibilityIssue {
  const LowContrast(this.role, this.ratio, this.needed);
  final String role;
  final double ratio;
  final double needed;
}

/// Two accent roles share a colour, so they could not be told apart.
class SameColour extends LegibilityIssue {
  const SameColour(this.first, this.second);
  final String first;
  final String second;
}

/// A theme file that cannot be used, with a message fit to show the runner.
class ThemeFormatException implements Exception {
  ThemeFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}
