import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One audio file in the music folder.
class FolderTrack {
  const FolderTrack({required this.uri, required this.name});

  /// The `content://` address that plays it.
  final String uri;

  /// The file's name.
  final String name;

  /// The name as a title, without its extension.
  String get title {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

/// File names as a person sorts them: `Track 2` before `Track 10`, ignoring case.
int naturalOrder(String a, String b) {
  final digits = RegExp(r'\d+|\D+');
  final left = digits.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = digits.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = BigInt.tryParse(left[i]), y = BigInt.tryParse(right[i]);
    final order = x != null && y != null ? x.compareTo(y) : left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return left.length.compareTo(right.length);
}

/// The folder music is played from, if the runner chose one.
///
/// Android keeps the choice as a read permission on that folder (see
/// `MusicFolder.kt`), so this stores nothing itself and it stays out of backups.
class MusicFolder {
  const MusicFolder({required this.current, required this.choose, required this.forget, required this.list});

  /// The chosen folder's name, or null when there is none.
  final Future<String?> Function() current;

  /// Opens the system folder picker. The new folder's name, or null when the
  /// runner backed out, which leaves any earlier choice as it was.
  final Future<String?> Function() choose;

  final Future<void> Function() forget;

  /// The audio files directly inside the folder, in natural order by name. Empty
  /// when there are none, or the folder has gone.
  final Future<List<FolderTrack>> Function() list;

  /// Nothing chosen and nothing to choose from: tests, and every platform but
  /// Android.
  factory MusicFolder.none() => MusicFolder(
    current: () async => null,
    choose: () async => null,
    forget: () async {},
    list: () async => const [],
  );

  factory MusicFolder.platform() {
    if (defaultTargetPlatform != TargetPlatform.android) return MusicFolder.none();
    const channel = MethodChannel('io.github.jbinder.sprawlrun/musicFolder');
    return MusicFolder(
      current: () => channel.invokeMethod<String>('current'),
      choose: () => channel.invokeMethod<String>('choose'),
      forget: () => channel.invokeMethod<void>('forget'),
      list: () async {
        final raw = await channel.invokeListMethod<Map<Object?, Object?>>('list') ?? const [];
        return sorted([
          for (final item in raw)
            if (item['uri'] case final String uri) FolderTrack(uri: uri, name: item['name'] as String? ?? uri),
        ]);
      },
    );
  }

  @visibleForTesting
  static List<FolderTrack> sorted(List<FolderTrack> tracks) => [...tracks]..sort((a, b) => naturalOrder(a.name, b.name));
}
