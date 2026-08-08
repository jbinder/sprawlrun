import 'dart:io';

import 'package:flutter/foundation.dart';

/// Writes [contents] to [file] so that a reader can never see a half-written
/// document.
///
/// `writeAsString` truncates the file and then streams into it. If the process
/// dies in between — the OS killing a backgrounded run, or the installer
/// stopping the app mid-update — what survives is a truncated JSON document
/// that no longer parses, and the repositories treat an unparseable log as an
/// empty one. Writing to a sibling and renaming makes the swap atomic: the old
/// document stays intact until the new one is complete on disk.
Future<void> writeAtomically(File file, String contents) async {
  final temp = File('${file.path}.tmp');
  // flush: true so the bytes are on the device before the rename publishes
  // them, rather than sitting in a page cache the rename would outrun.
  await temp.writeAsString(contents, flush: true);
  await temp.rename(file.path);
}

/// Moves a file that could not be parsed out of the way, keeping it under a
/// timestamped name.
///
/// Without this, a corrupt log reads as empty and the very next save overwrites
/// it with a single run — turning a recoverable file into a certain loss. The
/// runner cannot repair it from inside the app, but the bytes are still there
/// for whoever wants to try.
Future<void> quarantine(File file) async {
  try {
    if (!await file.exists()) return;
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await file.rename('${file.path}.corrupt-$stamp');
    debugPrint('Kept unreadable ${file.path} as ${file.path}.corrupt-$stamp');
  } on Object catch (e) {
    // Best effort. Failing to quarantine must not stop the app from starting.
    debugPrint('Could not quarantine ${file.path}: $e');
  }
}
