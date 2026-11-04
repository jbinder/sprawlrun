import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/theme_repository.dart';
import '../screens/theme_editor_screen.dart';
import '../state/app_state.dart';
import '../theme/colour_theme.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../theme/theme_draft.dart';
import '../util/picked_text.dart';
import 'panels.dart';
import '../l10n/l10n.dart';

/// The Colours row of Settings: a swatch per theme, and importing and
/// removing the runner's own.
///
/// Each swatch is drawn in its theme's own palette — a name alone says little
/// about a colour — and picking one recolours the app at once, so the screen
/// itself is the preview. Four to a row, wrapping, so contributed themes can
/// keep arriving without a redesign.
class ThemeControls extends StatefulWidget {
  const ThemeControls({super.key, required this.label});

  final String label;

  @override
  State<ThemeControls> createState() => _ThemeControlsState();
}

class _ThemeControlsState extends State<ThemeControls> {
  bool _busy = false;

  static const double _gap = 8;
  static const int _perRow = 4;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = state.themeRepository;
    final current = state.theme;
    final language = state.locale.languageCode;
    final season = state.season;
    final pack = season == null && state.packTheme != null ? state.activePack : null;
    final l = L.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: CyType.body(size: 15, weight: FontWeight.w600)),
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
        if (current.author != null || repo.importedIds.contains(current.id)) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  current.author == null ? current.nameIn(language) : l.themeBy(current.nameIn(language), current.author!),
                  style: CyType.body(size: 13, color: Cy.inkDim),
                ),
              ),
              if (repo.importedIds.contains(current.id)) ...[
                CyberTag(l.packImported, color: Cy.green),
                IconButton(
                  onPressed: _busy ? null : () => _export(current),
                  icon: Icon(Icons.ios_share, size: 18, color: Cy.inkDim),
                  tooltip: l.themeExportTooltip(current.nameIn(language)),
                ),
                IconButton(
                  onPressed: _busy ? null : () => _remove(state, current),
                  icon: Icon(Icons.delete_outline, size: 18, color: Cy.inkDim),
                  tooltip: l.themeRemoveTooltip(current.nameIn(language)),
                ),
              ],
            ],
          ),
        ],
        for (final error in repo.loadErrors) ...[
          const SizedBox(height: 6),
          Text(error, style: CyType.mono(size: 11, color: Cy.red)),
        ],
        const SizedBox(height: 12),
        CyberButton(
          label: repo.importedIds.contains(current.id) ? l.themeEditOwn : l.themeMakeOwn,
          icon: Icons.tune,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: _busy ? null : () => _edit(state, current, own: repo.importedIds.contains(current.id)),
        ),
        const SizedBox(height: 8),
        CyberButton(
          label: _busy ? l.working : l.themeImport,
          icon: Icons.palette_outlined,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: _busy ? null : () => _import(state),
        ),
      ],
    );
  }

  void _say(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: CyType.body(size: 14, color: bad ? Cy.red : Cy.ink))),
    );
  }

  Future<void> _import(AppState state) async {
    setState(() => _busy = true);
    try {
      // Permissive, as for packs: some document providers do not tag .json.
      final picked = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(label: l10n.themeFileType, extensions: ['json'], mimeTypes: ['application/json']),
        ],
      );
      if (picked == null) return;
      if (await picked.length() > ThemeRepository.maxThemeBytes) {
        _say(l10n.themeTooLarge, bad: true);
        return;
      }
      final theme = await state.importTheme(await readPickedText(picked));
      _say(l10n.themeImported(theme.nameIn(state.locale.languageCode)));
    } on ThemeFormatException catch (e) {
      _say(e.message, bad: true);
    } on Object catch (e) {
      _say(l10n.importFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the editor on [theme] itself when it is the runner's own, or on a
  /// copy of it to save as a new one.
  void _edit(AppState state, ColourTheme theme, {required bool own}) {
    final name = theme.nameIn(state.locale.languageCode);
    final copyName = l10n.themeCopyName(name);
    final draft = own
        ? ThemeDraft.of(theme)
        : ThemeDraft(
            base: theme.palette,
            name: copyName.length > ColourTheme.maxNameLength ? copyName.substring(0, ColourTheme.maxNameLength).trim() : copyName,
          );
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ThemeEditorScreen(draft: draft)));
  }

  /// Hands the theme's file to the share sheet, to keep or pass on.
  Future<void> _export(ColourTheme theme) async {
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${theme.id}.json');
      await file.writeAsString(theme.toJson());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: l10n.themeShareSubject(theme.name),
        ),
      );
    } on Object catch (e) {
      _say(l10n.exportFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AppState state, ColourTheme theme) async {
    setState(() => _busy = true);
    final name = theme.nameIn(state.locale.languageCode);
    try {
      await state.removeTheme(theme.id);
      _say(l10n.themeRemoved(name));
    } on Object catch (e) {
      _say(l10n.importFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
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
    Widget bar(Color c) => Expanded(child: Container(height: 4, color: c));
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 40,
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
            ),
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
