import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../l10n/l10n.dart';
import '../screens/themes_screen.dart';
import 'library_list.dart';

/// The Colours row of Settings: a swatch per theme. Making, importing, sharing
/// and removing them is on the RIG screen, since themes are data and picking
/// one is a setting.
///
/// Each swatch is drawn in its theme's own palette — a name alone says little
/// about a colour — and picking one recolours the app at once, so the screen
/// itself is the preview. Four to a row, wrapping, so contributed themes can
/// keep arriving without a redesign.
class ThemeControls extends StatelessWidget {
  const ThemeControls({super.key, required this.label});

  final String label;

  static const double _gap = 8;
  static const int _perRow = 4;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final current = state.theme;
    final language = state.locale.languageCode;
    final season = state.season;
    final pack = season == null && state.packTheme != null ? state.activePack : null;
    final l = L.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CyType.body(size: 15, weight: FontWeight.w600)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            final width = (box.maxWidth - _gap * (_perRow - 1)) / _perRow;
            return Wrap(
              spacing: _gap,
              runSpacing: 12,
              children: [
                for (final theme in state.themes)
                  SizedBox(
                    width: width,
                    child: _Swatch(
                      name: theme.nameIn(language),
                      palette: theme.palette,
                      selected: theme.id == current.id,
                      onTap: () => state.updateProfile(state.profile.copyWith(theme: theme.id)),
                    ),
                  ),
              ],
            );
          },
        ),
        if (season != null) ...[
          const SizedBox(height: 10),
          Text(l.settingLookSeason(season.title), style: CyType.body(size: 13, color: Cy.ghost, height: 1.4)),
        ] else if (pack != null) ...[
          const SizedBox(height: 10),
          Text(l.settingLookPack(pack.title), style: CyType.body(size: 13, color: Cy.ghost, height: 1.4)),
        ],
        if (current.author != null) ...[
          const SizedBox(height: 10),
          Text(l.themeBy(current.nameIn(language), current.author!), style: CyType.body(size: 13, color: Cy.inkDim)),
        ],
        const SizedBox(height: 4),
        RigLink(l.settingLookRig, open: (_) => const ThemesScreen()),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.palette, required this.selected, required this.onTap});

  final String name;
  final CyPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            PalettePreview(palette: palette, selected: selected),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                style: CyType.mono(size: 10, color: selected ? Cy.cyan : Cy.inkDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A theme drawn in its own colours, which says more than its name.
class PalettePreview extends StatelessWidget {
  const PalettePreview({super.key, required this.palette, this.selected = false, this.width});

  final CyPalette palette;
  final bool selected;
  final double? width;

  @override
  Widget build(BuildContext context) {
    Widget bar(Color c) => Expanded(child: Container(height: 4, color: c));
    return Container(
      height: 40,
      width: width,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: palette.v0id,
        border: Border.all(color: selected ? Cy.cyan : Cy.rule, width: selected ? 2 : 1),
        boxShadow: selected ? glow(Cy.cyan, blur: 10, opacity: 0.35) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // "You" leads, as it does on every screen; then the threat,
          // the story voice and success.
          Row(children: [bar(palette.cyan)]),
          Row(
            children: [
              bar(palette.magenta),
              const SizedBox(width: 3),
              bar(palette.amber),
              const SizedBox(width: 3),
              bar(palette.green),
            ],
          ),
        ],
      ),
    );
  }
}
