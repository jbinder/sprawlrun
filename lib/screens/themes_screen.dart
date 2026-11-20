import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/theme_repository.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/colour_theme.dart';
import '../theme/cyber_palette.dart';
import '../theme/theme_draft.dart';
import '../util/picked_text.dart';
import '../widgets/library_list.dart';
import '../widgets/panels.dart';
import '../widgets/theme_controls.dart';
import 'theme_editor_screen.dart';

/// THEMES on the RIG screen: every colour theme, shipped, made and imported,
/// to make, share and remove. Which one the app wears is chosen in Settings →
/// Identity, as is whether a pack may recolour it.
class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = state.themeRepository;
    final language = state.locale.languageCode;
    final l = L.of(context);
    return LibraryScreen(
      title: l.rigThemes,
      where: l.rigThemesWhere,
      items: [
        for (final theme in state.themes)
          if (theme.nameIn(language) case final name)
            LibraryItem(
              leading: PalettePreview(palette: theme.palette, width: 52),
              title: name,
              lines: [if (theme.author != null) l.songBy(theme.author!)],
              tag: repo.importedIds.contains(theme.id) ? l.packImported : null,
              tagColor: Cy.green,
              onEdit: repo.importedIds.contains(theme.id) && !_busy ? () => _edit(ThemeDraft.of(theme)) : null,
              editTooltip: l.themeEditTooltip(name),
              onExport: _busy
                  ? null
                  : () => shareJson(context, name: theme.id, source: theme.toJson(), subject: l10n.themeShareSubject(theme.name)),
              exportTooltip: l.themeExportTooltip(name),
              onRemove: repo.importedIds.contains(theme.id) && !_busy ? () => _remove(state, theme) : null,
              removeTooltip: l.themeRemoveTooltip(name),
            ),
      ],
      errors: repo.loadErrors,
      actions: [
        CyberButton(
          label: l.themeMakeOwn,
          icon: Icons.tune,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: _busy ? null : () => _edit(_copyOf(state.theme, language)),
        ),
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

  /// A new theme, starting from the one the app wears now.
  ThemeDraft _copyOf(ColourTheme theme, String language) {
    final copyName = l10n.themeCopyName(theme.nameIn(language));
    return ThemeDraft(
      base: theme.palette,
      name: copyName.length > ColourTheme.maxNameLength ? copyName.substring(0, ColourTheme.maxNameLength).trim() : copyName,
    );
  }

  void _edit(ThemeDraft draft) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ThemeEditorScreen(draft: draft)));

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
        if (mounted) sayOnLibrary(context, l10n.themeTooLarge, bad: true);
        return;
      }
      final theme = await state.importTheme(await readPickedText(picked));
      if (mounted) sayOnLibrary(context, l10n.themeImported(theme.nameIn(state.locale.languageCode)));
    } on ThemeFormatException catch (e) {
      if (mounted) sayOnLibrary(context, e.message, bad: true);
    } on Object catch (e) {
      if (mounted) sayOnLibrary(context, l10n.importFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AppState state, ColourTheme theme) async {
    setState(() => _busy = true);
    final name = theme.nameIn(state.locale.languageCode);
    try {
      await state.removeTheme(theme.id);
      if (mounted) sayOnLibrary(context, l10n.themeRemoved(name));
    } on Object catch (e) {
      if (mounted) sayOnLibrary(context, l10n.importFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
