import 'package:flutter/material.dart';

/// One full set of the app's colours. [Cy] reads whichever is in force.
///
/// Every set keeps the roles apart — "you", hostile, the story voice,
/// success and failure must never share a hue — and success stays a green
/// in all of them, so a met goal looks met whatever the runner picked.
class CyPalette {
  const CyPalette({
    required this.v0id,
    required this.panel,
    required this.panelHi,
    required this.rule,
    required this.cyan,
    required this.cyanDim,
    required this.magenta,
    required this.magentaDim,
    required this.amber,
    required this.green,
    required this.red,
    required this.ghost,
    required this.ink,
    required this.inkDim,
  });

  final Color v0id;
  final Color panel;
  final Color panelHi;
  final Color rule;
  final Color cyan;
  final Color cyanDim;
  final Color magenta;
  final Color magentaDim;
  final Color amber;
  final Color green;
  final Color red;
  final Color ghost;
  final Color ink;
  final Color inkDim;

  /// The year-round look.
  static const standard = CyPalette(
    v0id: Color(0xFF04070B),
    panel: Color(0xFF0A1119),
    panelHi: Color(0xFF101B26),
    rule: Color(0xFF1E2E3D),
    cyan: Color(0xFF00F0FF),
    cyanDim: Color(0xFF0A8A96),
    magenta: Color(0xFFFF2D9B),
    magentaDim: Color(0xFF8C1856),
    amber: Color(0xFFFFB000),
    green: Color(0xFF39FF88),
    red: Color(0xFFFF3B4E),
    ghost: Color(0xFF3E525F),
    ink: Color(0xFFD6E8F2),
    inkDim: Color(0xFF7C93A3),
  );

  /// SYNTHWAVE: a hot-pink "you" on a violet night, with a violet threat and
  /// the handlers in pale cyan, so no role keeps its year-round hue.
  static const synth = CyPalette(
    v0id: Color(0xFF0A0612),
    panel: Color(0xFF140C1F),
    panelHi: Color(0xFF1E122D),
    rule: Color(0xFF35224A),
    cyan: Color(0xFFFF3FD2),
    cyanDim: Color(0xFF8C2275),
    magenta: Color(0xFF9D6BFF),
    magentaDim: Color(0xFF4F3290),
    amber: Color(0xFF6FF3FF),
    green: Color(0xFF3DFFA2),
    red: Color(0xFFFF4A3D),
    ghost: Color(0xFF4B3D5C),
    ink: Color(0xFFF1E0F2),
    inkDim: Color(0xFF9E86A6),
  );

  /// GLACIER: corporate ice. A cold cornflower "you" on blue-black, the
  /// threat in a rose red and failure in orange so the two stay apart.
  static const glacier = CyPalette(
    v0id: Color(0xFF04080F),
    panel: Color(0xFF0A121E),
    panelHi: Color(0xFF111C2C),
    rule: Color(0xFF1F3048),
    cyan: Color(0xFF6EA8FF),
    cyanDim: Color(0xFF2F5A99),
    magenta: Color(0xFFFF4D6D),
    magentaDim: Color(0xFF8A2238),
    amber: Color(0xFFFFD27A),
    green: Color(0xFF4DFFC3),
    red: Color(0xFFFF6A3D),
    ghost: Color(0xFF3A4C63),
    ink: Color(0xFFE4EEFA),
    inkDim: Color(0xFF8095AE),
  );

  /// VOLT: hazard tape. A yellow "you" on warm black; the handlers move to
  /// cyan, since amber would sit next to the yellow.
  static const volt = CyPalette(
    v0id: Color(0xFF080806),
    panel: Color(0xFF12120C),
    panelHi: Color(0xFF1B1B12),
    rule: Color(0xFF33331F),
    cyan: Color(0xFFFFE53B),
    cyanDim: Color(0xFF8F7F12),
    magenta: Color(0xFFFF3D7F),
    magentaDim: Color(0xFF8C1F45),
    amber: Color(0xFF5CE1FF),
    green: Color(0xFF39FF88),
    red: Color(0xFFFF4A2E),
    ghost: Color(0xFF4A4A38),
    ink: Color(0xFFF2F0E2),
    inkDim: Color(0xFF9C9A84),
  );

  /// SAMHAIN PROTOCOL: the same roles in sodium orange, spectral violet,
  /// candlelight and ectoplasm, on a black with a bruise of purple in it.
  ///
  /// Failure moves to crimson so it never reads as the orange that now means
  /// "you"; success stays a green, so a met goal looks met in any season.
  static const samhain = CyPalette(
    v0id: Color(0xFF07050A),
    panel: Color(0xFF110C16),
    panelHi: Color(0xFF1A1220),
    rule: Color(0xFF2E2238),
    cyan: Color(0xFFFF7A1A),
    cyanDim: Color(0xFF9A4A12),
    magenta: Color(0xFFB45CFF),
    magentaDim: Color(0xFF5E2C8C),
    amber: Color(0xFFF2D58A),
    green: Color(0xFFB6FF3B),
    red: Color(0xFFE0234A),
    ghost: Color(0xFF4E4256),
    ink: Color(0xFFEFE3D6),
    inkDim: Color(0xFF9C8C9E),
  );
}

/// The colours the runner picked in Settings. Stored by [name] in `Profile`;
/// a season in force wears its own instead (`AppState.palette`).
enum Look {
  neon,
  synth,
  glacier,
  volt;

  CyPalette get palette => switch (this) {
    Look.neon => CyPalette.standard,
    Look.synth => CyPalette.synth,
    Look.glacier => CyPalette.glacier,
    Look.volt => CyPalette.volt,
  };

  /// Anything unknown — a profile from before looks, or a look a later
  /// version added and this one lacks — is the year-round one.
  static Look parse(Object? name) => Look.values.firstWhere((l) => l.name == name, orElse: () => Look.neon);
}

/// The whole app draws from this palette. Nothing else defines raw colours.
///
/// The look is "cheap terminal glass in a rainy megacity": near-black
/// backgrounds, one dominant cyan, magenta for anything hostile or urgent,
/// amber for the story voice, and a toxic green reserved for success.
///
/// The names are roles, not hues: the runner's [Look] or a season swaps the
/// whole set through [use] (see `theme/season.dart`), which is why these are getters rather than
/// constants — and why nothing may capture one in a `const`.
abstract final class Cy {
  static CyPalette _p = CyPalette.standard;

  /// The palette in force.
  static CyPalette get palette => _p;

  /// Switches every colour at once. Whoever calls this rebuilds the widget
  /// tree, since nothing listens for it.
  static void use(CyPalette palette) => _p = palette;

  /// Deepest background — the space between panels.
  static Color get v0id => _p.v0id;

  /// Panel fill.
  static Color get panel => _p.panel;

  /// Panel fill, one step lighter (nested surfaces, list rows).
  static Color get panelHi => _p.panelHi;

  /// Hairlines, dividers, inactive borders.
  static Color get rule => _p.rule;

  /// Primary neon. Interactive, alive, "you".
  static Color get cyan => _p.cyan;
  static Color get cyanDim => _p.cyanDim;

  /// Hostile / urgent / chase.
  static Color get magenta => _p.magenta;
  static Color get magentaDim => _p.magentaDim;

  /// The story voice, handlers, transmissions.
  static Color get amber => _p.amber;

  /// Success, completion, "the goal is met".
  static Color get green => _p.green;

  /// Failure, damage, hard stop.
  static Color get red => _p.red;

  /// Locked, disabled, redacted.
  static Color get ghost => _p.ghost;

  /// Primary body text.
  static Color get ink => _p.ink;

  /// Secondary body text.
  static Color get inkDim => _p.inkDim;

  /// Per-speaker colour, so a voice is recognisable before you parse the name.
  static Color speaker(String id) => switch (id.toUpperCase()) {
    'KESTREL' => amber,
    'HALCYON' => cyan,
    'SIX' => magenta,
    'PACHINKO' => green,
    'LANTERN' => green,
    'VANTAR' || 'ICE' || 'GRIMWALD' || 'OSSUARY' => red,
    'SYSTEM' => inkDim,
    _ => ink,
  };
}

/// Standard neon glow. Used behind text and around active borders.
List<BoxShadow> glow(Color color, {double blur = 18, double spread = 0, double opacity = 0.45}) => [
  BoxShadow(color: color.withValues(alpha: opacity), blurRadius: blur, spreadRadius: spread),
];

/// Text glow, which needs to be much tighter than box glow to stay legible.
List<Shadow> textGlow(Color color, {double blur = 12, double opacity = 0.55}) => [
  Shadow(color: color.withValues(alpha: opacity), blurRadius: blur),
];
