import 'dart:io';

import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/colour_theme.dart';
import 'atomic_write.dart';

/// The colour themes on offer: NEON, every file in `assets/themes/`, and the
/// ones the runner imported.
///
/// Shipped themes are found through the asset manifest rather than listed in
/// code, so contributing one is adding a file — see docs/THEMES.md.
/// Imported themes live in [importDir], the app's private storage, and come
/// in only through [importTheme], fed by the system file picker as mission
/// packs are.
class ThemeRepository {
  ThemeRepository({required this.importDir, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetFolder = 'assets/themes/';

  final Directory importDir;
  final AssetBundle _bundle;

  /// Largest file an import will read. A theme is well under a kilobyte.
  static const int maxThemeBytes = 64 * 1024;

  /// Themes that failed to load, for Settings to show.
  final List<String> loadErrors = [];

  /// Ids of the themes that came from [importDir], and so can be removed.
  final Set<String> importedIds = {};

  /// Ids an import may not take: NEON and every shipped theme.
  final Set<String> builtInIds = {ColourTheme.neon.id};

  /// NEON first, then the shipped themes, then the imported ones, each group
  /// by name.
  Future<List<ColourTheme>> loadThemes() async {
    loadErrors.clear();
    importedIds.clear();
    builtInIds
      ..clear()
      ..add(ColourTheme.neon.id);

    final shipped = <ColourTheme>[];
    for (final path in await _assetThemes()) {
      try {
        final theme = ColourTheme.parse(await _bundle.loadString(path));
        if (builtInIds.add(theme.id)) shipped.add(theme);
      } on Object catch (e) {
        loadErrors.add('$path: $e');
      }
    }

    final imported = <ColourTheme>[];
    if (await importDir.exists()) {
      final files = await importDir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.json'))
          .cast<File>()
          .toList();
      for (final file in files) {
        try {
          final theme = ColourTheme.parse(await file.readAsString());
          // A shipped theme added later under the same id wins over the import.
          if (builtInIds.contains(theme.id) || !importedIds.add(theme.id)) continue;
          imported.add(theme);
        } on Object catch (e) {
          loadErrors.add('${file.uri.pathSegments.last}: $e');
        }
      }
    }

    int byName(ColourTheme a, ColourTheme b) => a.name.compareTo(b.name);
    return [ColourTheme.neon, ...shipped..sort(byName), ...imported..sort(byName)];
  }

  Future<List<String>> _assetThemes() async {
    try {
      final assets = (await AssetManifest.loadFromAssetBundle(_bundle)).listAssets();
      return [for (final a in assets) if (a.startsWith(assetFolder) && a.endsWith('.json')) a]..sort();
    } on Object {
      return const [];
    }
  }

  /// Validates a picked file and keeps it under its id, so importing a revised
  /// version replaces the old one — the edit-and-reimport loop for someone
  /// making a theme. Throws [ThemeFormatException] with a message fit to show
  /// the runner.
  Future<ColourTheme> importTheme(String source) async {
    final theme = ColourTheme.parse(source);
    if (builtInIds.contains(theme.id)) throw ThemeFormatException(l10n.themeErrorBuiltInId(theme.id));
    await importDir.create(recursive: true);
    await writeAtomically(File('${importDir.path}/${theme.id}.json'), source);
    return theme;
  }

  /// Deletes an imported theme. Its id is checked by [ColourTheme.parse] on
  /// the way in, so it is a safe file name.
  Future<void> removeTheme(String id) async {
    final file = File('${importDir.path}/$id.json');
    if (await file.exists()) await file.delete();
  }
}
