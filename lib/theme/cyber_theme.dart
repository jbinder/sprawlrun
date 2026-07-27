import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cyber_palette.dart';

/// Three typefaces, three jobs:
///   * [display] — Orbitron, for signage and screen titles.
///   * body      — Rajdhani, condensed and dense, for everything readable.
///   * [mono]    — Share Tech Mono, for anything that should look like a readout.
abstract final class CyType {
  static const String displayFamily = 'Orbitron';
  static const String bodyFamily = 'Rajdhani';
  static const String monoFamily = 'ShareTechMono';

  /// Orbitron ships as a variable font, so weight comes from the `wght` axis
  /// rather than [FontWeight] — asking for w700 alone would render regular.
  static TextStyle display({
    double size = 18,
    double weight = 700,
    Color color = Cy.ink,
    double letterSpacing = 2.4,
    List<Shadow>? shadows,
    double? height,
  }) => TextStyle(
    fontFamily: displayFamily,
    fontVariations: [FontVariation('wght', weight)],
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
    shadows: shadows,
    height: height,
  );

  static TextStyle body({
    double size = 16,
    FontWeight weight = FontWeight.w600,
    Color color = Cy.ink,
    double letterSpacing = 0.4,
    double? height,
    FontStyle? style,
  }) => TextStyle(
    fontFamily: bodyFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
    fontStyle: style,
  );

  static TextStyle mono({
    double size = 14,
    Color color = Cy.ink,
    double letterSpacing = 1.0,
    List<Shadow>? shadows,
    double? height,
  }) => TextStyle(
    fontFamily: monoFamily,
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
    shadows: shadows,
    height: height,
  );

  /// Big telemetry numbers (distance, clock, pace) on the run HUD.
  static TextStyle readout(double size, Color color) => TextStyle(
    fontFamily: monoFamily,
    fontSize: size,
    color: color,
    letterSpacing: 1.5,
    height: 1.0,
    shadows: textGlow(color, blur: size * 0.5, opacity: 0.5),
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Small all-caps label above a value or section.
  static TextStyle label({Color color = Cy.inkDim, double size = 11}) =>
      TextStyle(fontFamily: monoFamily, fontSize: size, color: color, letterSpacing: 2.2);
}

ThemeData buildCyberTheme() {
  const scheme = ColorScheme.dark(
    primary: Cy.cyan,
    onPrimary: Cy.v0id,
    secondary: Cy.magenta,
    onSecondary: Cy.v0id,
    tertiary: Cy.amber,
    surface: Cy.panel,
    onSurface: Cy.ink,
    error: Cy.red,
    onError: Cy.v0id,
    outline: Cy.rule,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Cy.v0id,
    canvasColor: Cy.v0id,
    fontFamily: CyType.bodyFamily,
    splashColor: Cy.cyan.withValues(alpha: 0.08),
    highlightColor: Cy.cyan.withValues(alpha: 0.05),
    dividerTheme: const DividerThemeData(color: Cy.rule, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: Cy.cyan, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: Cy.v0id,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: CyType.display(size: 16, color: Cy.ink, shadows: textGlow(Cy.cyan, blur: 10, opacity: 0.35)),
      iconTheme: const IconThemeData(color: Cy.cyan),
    ),
    textTheme: TextTheme(
      displayLarge: CyType.display(size: 30),
      headlineMedium: CyType.display(size: 20),
      titleMedium: CyType.body(size: 18, weight: FontWeight.w700),
      bodyLarge: CyType.body(size: 16, height: 1.35),
      bodyMedium: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
      labelSmall: CyType.label(),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: Cy.cyan,
      inactiveTrackColor: Cy.rule,
      thumbColor: Cy.cyan,
      overlayColor: Cy.cyan.withValues(alpha: 0.15),
      trackHeight: 2,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Cy.cyan : Cy.ghost),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Cy.cyan.withValues(alpha: 0.3) : Cy.panelHi,
      ),
      trackOutlineColor: WidgetStateProperty.all(Cy.rule),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Cy.panelHi,
      contentTextStyle: CyType.mono(size: 13, color: Cy.ink),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Dark status/nav bars with no scrim, so the grid background runs edge to edge.
const SystemUiOverlayStyle cyberOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Cy.v0id,
  systemNavigationBarIconBrightness: Brightness.light,
);
