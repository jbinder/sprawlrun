import 'dart:convert';
import 'dart:io';

import '../models/run_record.dart';
import 'atomic_write.dart';

/// A run in progress, as it stood when it was last saved.
class ActiveRunSnapshot {
  const ActiveRunSnapshot({required this.record, required this.codexHeard});

  /// The run as if it had been finished at the moment of saving: `endedAt` is
  /// when it was saved, and the outcome is what finishing then would have
  /// recorded.
  final RunRecord record;

  /// Intel heard so far — banked only if the run turns out a success, as for
  /// any finished run.
  final List<String> codexHeard;

  Map<String, dynamic> toJson() => {
    'record': record.toJson(),
    'codexHeard': codexHeard,
  };

  factory ActiveRunSnapshot.fromJson(Map<String, dynamic> json) => ActiveRunSnapshot(
    record: RunRecord.fromJson(Map<String, dynamic>.from(json['record'] as Map)),
    codexHeard: [for (final id in json['codexHeard'] as List? ?? const []) id as String],
  );
}

/// Keeps the run in progress on disk, so that losing the app mid-run does not
/// lose the run.
///
/// Until this existed a run lived only in memory until it was finished, and a
/// runner lost a whole one by swiping the app away. Swiping no longer ends a
/// run, but the process can still die — a vendor battery saver, a crash, a
/// flat battery — and whatever was saved here is then offered back on the next
/// launch.
///
/// The file exists only while a run does: it is deleted when the run is
/// finished or abandoned. That is also why it is not part of a backup — it is
/// never meant to outlive the run it describes.
class ActiveRunStore {
  ActiveRunStore(Directory root) : file = File('${root.path}/active_run.json');

  final File file;

  Future<void> save(ActiveRunSnapshot snapshot) async {
    await file.parent.create(recursive: true);
    await writeAtomically(file, jsonEncode(snapshot.toJson()));
  }

  /// The run a previous launch left unfinished, or null.
  ///
  /// A file that does not parse is quarantined rather than deleted: it is the
  /// only copy of someone's run.
  Future<ActiveRunSnapshot?> load() async {
    if (!await file.exists()) return null;
    try {
      return ActiveRunSnapshot.fromJson(Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map));
    } on Object {
      await quarantine(file);
      return null;
    }
  }

  /// Deletes the saved run only if it is still run [id]. A run started since
  /// has been saving over it, and its copy must not go with the old one.
  Future<void> clearIf(String id) async {
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map;
      if ((raw['record'] as Map)['id'] != id) return;
    } on Object {
      return;
    }
    await file.delete();
  }
}
