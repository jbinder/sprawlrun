import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The folder automatic backups go to, if the runner chose one.
///
/// Android keeps the choice as a permission on that folder (see
/// `BackupFolder.kt`), so this only ever asks the platform and stores nothing
/// itself. Every call answers in folder *names*, which is all the app shows.
class BackupFolder {
  const BackupFolder({required this.current, required this.choose, required this.forget, required this.write});

  /// The chosen folder's name, or null when automatic backups are off.
  final Future<String?> Function() current;

  /// Opens the system folder picker. The new folder's name, or null when the
  /// runner backed out — which leaves any earlier choice as it was.
  final Future<String?> Function() choose;

  /// Turns automatic backups off by letting go of the folder.
  final Future<void> Function() forget;

  /// Writes [json] as [name], keeping only the [keep] newest files whose names
  /// start with [prefix]. Throws when the folder cannot be written.
  final Future<void> Function(String name, String json, {required String prefix, required int keep}) write;

  /// Nothing chosen and nothing to choose from: tests, and every platform but
  /// Android.
  factory BackupFolder.none() => BackupFolder(
    current: () async => null,
    choose: () async => null,
    forget: () async {},
    write: (_, _, {required prefix, required keep}) async => throw const BackupFolderException('no folder'),
  );

  factory BackupFolder.platform() {
    if (defaultTargetPlatform != TargetPlatform.android) return BackupFolder.none();
    const channel = MethodChannel('io.github.jbinder.sprawlrun/backup');
    return BackupFolder(
      current: () async {
        try {
          return await channel.invokeMethod<String>('current');
        } on MissingPluginException {
          return null;
        }
      },
      choose: () => channel.invokeMethod<String>('choose'),
      forget: () => channel.invokeMethod<void>('forget'),
      write: (name, json, {required prefix, required keep}) async {
        try {
          await channel.invokeMethod<void>('write', {
            'name': name,
            'bytes': utf8.encode(json),
            'prefix': prefix,
            'keep': keep,
          });
        } on PlatformException catch (e) {
          throw BackupFolderException(e.message ?? e.code);
        }
      },
    );
  }
}

class BackupFolderException implements Exception {
  const BackupFolderException(this.message);

  final String message;

  @override
  String toString() => message;
}
