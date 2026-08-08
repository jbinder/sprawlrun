import 'dart:convert';
import 'dart:io';

import '../models/run_record.dart';
import 'atomic_write.dart';

/// Persists the run log to disk as plain JSON.
///
/// Split into two tiers on purpose: `index.json` holds every run *without* its
/// GPS trace and is the only thing stats and achievements ever read, while each
/// trace lives in its own file and is loaded only when a summary screen wants
/// to draw it. A year of running stays a few hundred kilobytes to parse at
/// startup instead of tens of megabytes.
class RunRepository {
  RunRepository(this.root);

  /// Directory that holds `index.json` and `traces/`.
  final Directory root;

  File get _index => File('${root.path}/index.json');
  Directory get _traces => Directory('${root.path}/traces');

  List<RunRecord>? _cache;

  /// Every stored run, newest first. Traces are omitted.
  Future<List<RunRecord>> loadAll() async {
    if (_cache != null) return _cache!;
    if (!await _index.exists()) return _cache = const [];
    try {
      final raw = jsonDecode(await _index.readAsString());
      final list = (raw as List)
          .map((e) => RunRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return _cache = list;
    } on Object {
      // A corrupt log must never brick the app. The file is kept aside rather
      // than left in place, because the next save would otherwise overwrite it.
      await quarantine(_index);
      return _cache = const [];
    }
  }

  Future<void> save(RunRecord record) async {
    final runs = List<RunRecord>.from(await loadAll())
      ..removeWhere((r) => r.id == record.id)
      ..insert(0, record);
    _cache = runs;
    await _writeIndex(runs);
    if (record.trace.isNotEmpty) {
      await _traces.create(recursive: true);
      await writeAtomically(
        File('${_traces.path}/${record.id}.json'),
        jsonEncode(record.trace.map((p) => p.toJson()).toList()),
      );
    }
  }

  Future<void> delete(String id) async {
    final runs = List<RunRecord>.from(await loadAll())..removeWhere((r) => r.id == id);
    _cache = runs;
    await _writeIndex(runs);
    final trace = File('${_traces.path}/$id.json');
    if (await trace.exists()) await trace.delete();
  }

  /// Swaps the entire log for [records] — the restore half of a backup.
  ///
  /// Every trace directory is rebuilt from scratch rather than merged, so a
  /// restore cannot leave orphaned traces from runs that no longer exist.
  /// Records that arrive without a trace simply have none afterwards.
  Future<void> replaceAll(List<RunRecord> records) async {
    final ordered = List<RunRecord>.from(records)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _cache = ordered;

    if (await _traces.exists()) await _traces.delete(recursive: true);
    await _writeIndex(ordered);

    final withTraces = ordered.where((r) => r.trace.isNotEmpty);
    if (withTraces.isNotEmpty) {
      await _traces.create(recursive: true);
      for (final record in withTraces) {
        await writeAtomically(
          File('${_traces.path}/${record.id}.json'),
          jsonEncode(record.trace.map((p) => p.toJson()).toList()),
        );
      }
    }
  }

  Future<void> deleteAll() async {
    _cache = const [];
    if (await _index.exists()) await _index.delete();
    if (await _traces.exists()) await _traces.delete(recursive: true);
  }

  /// The GPS trace for one run, or empty if it was never stored.
  Future<List<TracePoint>> loadTrace(String id) async {
    final file = File('${_traces.path}/$id.json');
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List;
      return raw.map((e) => TracePoint.fromJson(e as List)).toList();
    } on Object {
      return const [];
    }
  }

  Future<void> _writeIndex(List<RunRecord> runs) async {
    await root.create(recursive: true);
    // Traces are stripped here — they live in their own files.
    final payload = runs.map((r) {
      final json = r.toJson();
      json['trace'] = const [];
      return json;
    }).toList();
    await writeAtomically(_index, jsonEncode(payload));
  }
}
