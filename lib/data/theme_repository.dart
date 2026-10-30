import 'dart:convert';
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
    for (final file in await _importedFiles()) {
      try {
        final theme = ColourTheme.parse(await file.readAsString());
        // A shipped theme added later under the same id wins over the import.
        if (builtInIds.contains(theme.id) || !importedIds.add(theme.id)) continue;
        imported.add(theme);
      } on Object catch (e) {
        loadErrors.add('${file.uri.pathSegments.last}: $e');
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

  /// The imported themes as their files have them, for a backup: they are
  /// the runner's own and exist nowhere else. Only the ones that still load.
  Future<List<Map<String, dynamic>>> importedForBackup() async {
    final themes = <Map<String, dynamic>>[];
    for (final file in await _importedFiles()) {
      try {
        final source = await file.readAsString();
        ColourTheme.parse(source);
        themes.add(Map<String, dynamic>.from(jsonDecode(source) as Map));
      } on Object {
        continue;
      }
    }
    return themes;
  }

  /// Puts back the themes a backup carried, each checked as an import is.
  /// [replace] makes this device's imported themes exactly the backup's;
  /// otherwise only the ones it lacks are added, and a theme it already has
  /// under the same id stays as it is here. One that no longer passes — or
  /// whose id a shipped theme has taken since — is skipped rather than
  /// failing the restore. Returns how many were added.
  Future<int> restore(List<Map<String, dynamic>> themes, {required bool replace}) async {
    if (replace) {
      for (final file in await _importedFiles()) {
        await file.delete();
      }
    }
    await loadThemes();
    final have = {...importedIds};
    var added = 0;
    for (final raw in themes) {
      if (have.contains(raw['id'])) continue;
      try {
        final theme = await importTheme(jsonEncode(raw));
        have.add(theme.id);
        added++;
      } on ThemeFormatException {
        continue;
      }
    }
    return added;
  }

  Future<List<File>> _importedFiles() async {
    if (!await importDir.exists()) return const [];
    return importDir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.json'))
        .cast<File>()
        .toList();
  }

  /// Deletes an imported theme. Its id is checked by [ColourTheme.parse] on
  /// the way in, so it is a safe file name.
  Future<void> removeTheme(String id) async {
    final file = File('${importDir.path}/$id.json');
    if (await file.exists()) await file.delete();
  }
}
