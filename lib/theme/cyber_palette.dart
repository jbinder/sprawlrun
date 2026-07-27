import 'package:flutter/material.dart';

/// The whole app draws from this palette. Nothing else defines raw colours.
///
/// The look is "cheap terminal glass in a rainy megacity": near-black
/// backgrounds, one dominant cyan, magenta for anything hostile or urgent,
/// amber for the story voice, and a toxic green reserved for success.
abstract final class Cy {
  /// Deepest background — the space between panels.
  static const Color v0id = Color(0xFF04070B);

  /// Panel fill.
  static const Color panel = Color(0xFF0A1119);

  /// Panel fill, one step lighter (nested surfaces, list rows).
  static const Color panelHi = Color(0xFF101B26);

  /// Hairlines, dividers, inactive borders.
  static const Color rule = Color(0xFF1E2E3D);

  /// Primary neon. Interactive, alive, "you".
  static const Color cyan = Color(0xFF00F0FF);
  static const Color cyanDim = Color(0xFF0A8A96);

  /// Hostile / urgent / chase.
  static const Color magenta = Color(0xFFFF2D9B);
  static const Color magentaDim = Color(0xFF8C1856);

  /// The story voice, handlers, transmissions.
  static const Color amber = Color(0xFFFFB000);

  /// Success, completion, "the goal is met".
  static const Color green = Color(0xFF39FF88);

  /// Failure, damage, hard stop.
  static const Color red = Color(0xFFFF3B4E);

  /// Locked, disabled, redacted.
  static const Color ghost = Color(0xFF3E525F);

  /// Primary body text.
  static const Color ink = Color(0xFFD6E8F2);

  /// Secondary body text.
  static const Color inkDim = Color(0xFF7C93A3);

  /// Per-speaker colour, so a voice is recognisable before you parse the name.
  static Color speaker(String id) => switch (id.toUpperCase()) {
    'KESTREL' => amber,
    'HALCYON' => cyan,
    'SIX' => magenta,
    'PACHINKO' => green,
    'VANTAR' || 'ICE' || 'GRIMWALD' => red,
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
