import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../audio/song.dart';

/// The songs on offer: every file in `assets/songs/`.
///
/// Found through the asset manifest rather than listed in code, so adding a song
/// is adding a file, as with colour themes.
class SongLibrary {
  SongLibrary({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetFolder = 'assets/songs/';

  /// What the switch in Settings plays until there is a choice to make.
  static const String firstSongId = 'neon_pursuit';

  final AssetBundle _bundle;

  /// The file for [id], checked, or null if there is no such song or it does not
  /// parse. A bad file costs the runner the music, never the run.
  Future<String?> sourceOf(String id) async {
    for (final path in await _files()) {
      try {
        final source = await _bundle.loadString(path);
        if (Song.parse(source).id == id) return source;
      } on Object catch (e) {
        debugPrint('Song $path: $e');
      }
    }
    return null;
  }

  Future<List<String>> _files() async {
    try {
      final assets = (await AssetManifest.loadFromAssetBundle(_bundle)).listAssets();
      return [for (final a in assets) if (a.startsWith(assetFolder) && a.endsWith('.json')) a]..sort();
    } on Object {
      return const [];
    }
  }
}
