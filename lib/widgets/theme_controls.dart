import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../l10n/l10n.dart';
import '../screens/themes_screen.dart';
import 'library_list.dart';
import 'panels.dart';

/// The Colours row of Settings: the theme being worn, and a dialog of a swatch
/// per theme to pick another. Making, importing, sharing and removing them is
/// on the RIG screen, since themes are data and picking one is a setting.
///
/// Each swatch is drawn in its theme's own palette — a name alone says little
/// about a colour — and picking one closes the dialog and recolours the app at
/// once, so the screen itself is the preview. The swatches live in a dialog,
/// four to a row, so contributed themes can keep arriving without crowding
/// Settings.
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
        Semantics(
          button: true,
          child: InkWell(
            onTap: () => _pick(context, state),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
                  PalettePreview(palette: current.palette, width: 44, height: 28),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      current.nameIn(language).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CyType.mono(size: 12, color: Cy.cyan),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.unfold_more, size: 16, color: Cy.inkDim),
                ],
              ),
            ),
          ),
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

  /// Every theme as a swatch. The answer is applied once the dialog has gone,
  /// as the other pickers in Settings do, so the recolour lands on Settings.
  Future<void> _pick(BuildContext context, AppState state) async {
    final language = state.locale.languageCode;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: NeonPanel(
          accent: Cy.cyan,
          lit: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: CyType.display(size: 14, color: Cy.cyan)),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: LayoutBuilder(
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
                                selected: theme.id == state.theme.id,
                                onTap: () => Navigator.of(context).pop(theme.id),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != state.theme.id) {
      await state.updateProfile(state.profile.copyWith(theme: picked));
    }
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
  const PalettePreview({super.key, required this.palette, this.selected = false, this.width, this.height = 40});

  final CyPalette palette;
  final bool selected;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget bar(Color c) => Expanded(child: Container(height: 4, color: c));
    return Container(
      height: height,
      width: width,
      padding: EdgeInsets.all(height < 40 ? 5 : 7),
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
