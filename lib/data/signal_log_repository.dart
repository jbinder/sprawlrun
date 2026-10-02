import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/signal_log.dart';
import 'atomic_write.dart';

/// Keeps every signal the handlers have sent, for THE WIRE.
///
/// The only thing on THE WIRE that is stored. Runs, cleared operations,
/// achievements and intel are all projected from the run log and the profile;
/// a signal has no other record anywhere, because the plan that produced it is
/// rebuilt from scratch on every launch.
///
/// **One file per year**, under `signals/`. It is an archive with no cap —
/// about 90 KB a year at two signals a day — and a single file would make
/// every launch read and every re-plan rewrite the whole of it: a tenth of a
/// second by year five, a third by year ten, on the thread that draws the UI.
/// Split by year, a re-plan only touches the years that can hold a pending
/// signal — this one, and the next across New Year — so its cost stays flat
/// forever. Earlier years are closed: never written again, and read only when
/// something asks for the whole history.
class SignalLogRepository {
  SignalLogRepository(this.root);

  final Directory root;

  Directory get _dir => Directory('${root.path}/signals');
  File _fileFor(int year) => File('${_dir.path}/$year.json');

  /// The single-file layout this replaced, read once and split up.
  File get _legacy => File('${root.path}/signals.json');

  final Map<int, List<SignalLogEntry>> _years = {};

  /// What each year's file last held, so writing back unchanged content —
  /// the usual re-plan, opening the app twice in an hour — is skipped.
  final Map<int, String> _written = {};

  bool _migrated = false;
  bool _allLoaded = false;

  /// Which years are in memory. For tests that check a re-plan leaves closed
  /// years on disk untouched.
  @visibleForTesting
  Set<int> get yearsInMemory => _years.keys.toSet();

  /// Records a freshly scheduled plan.
  ///
  /// Everything already in the past is kept: it fired. Everything still in the
  /// future is dropped and replaced by [plan], because scheduling cancels the
  /// previous plan's pending notifications. An empty plan — signals switched
  /// off — therefore clears what was pending and leaves history alone.
  ///
  /// Only years from [now]'s onward are read or written. A closed year cannot
  /// hold anything pending, since pending means later than now.
  Future<void> record(List<SignalLogEntry> plan, DateTime now) async {
    await _migrateLegacy();
    final upcoming = plan.where((e) => e.at.isAfter(now)).toList();
    final years = {
      now.year,
      ...upcoming.map((e) => e.at.year),
      ...(await _yearsOnDisk()).where((y) => y > now.year),
    };
    for (final year in years) {
      final kept = (await _load(year)).where((e) => !e.at.isAfter(now));
      await _store(year, [...kept, ...upcoming.where((e) => e.at.year == year)]);
    }
  }

  /// Every stored entry, newest first — including ones still in the future,
  /// which are the current plan and have not been sent yet. Reads every year,
  /// once; later calls are answered from memory.
  Future<List<SignalLogEntry>> loadAll() async {
    await _migrateLegacy();
    if (!_allLoaded) {
      for (final year in await _yearsOnDisk()) {
        await _load(year);
      }
      _allLoaded = true;
    }
    return _sorted(_years.values.expand((e) => e));
  }

  /// The entries whose time has come, newest first.
  Future<List<SignalLogEntry>> sent(DateTime now) async =>
      (await loadAll()).where((e) => !e.at.isAfter(now)).toList();

  /// Replaces the whole archive, for restoring a backup onto this device.
  Future<void> replaceAll(List<SignalLogEntry> entries) async {
    await _migrateLegacy();
    for (final year in await _yearsOnDisk()) {
      await _fileFor(year).delete();
    }
    _years.clear();
    _written.clear();
    for (final MapEntry(key: year, value: inYear) in _byYear(entries).entries) {
      await _store(year, inYear);
    }
    _allLoaded = true;
  }

  /// Adds whatever [entries] has that the archive does not, for merging a
  /// backup. Only the years that gain something are rewritten.
  Future<void> merge(List<SignalLogEntry> entries) async {
    await loadAll();
    for (final MapEntry(key: year, value: incoming) in _byYear(entries).entries) {
      final mine = _years[year] ?? const [];
      final known = mine.map((e) => e.key).toSet();
      final added = incoming.where((e) => !known.contains(e.key)).toList();
      if (added.isNotEmpty) await _store(year, [...mine, ...added]);
    }
  }

  // -- files ----------------------------------------------------------------

  Future<List<int>> _yearsOnDisk() async {
    if (!await _dir.exists()) return const [];
    final years = <int>[];
    await for (final f in _dir.list()) {
      final name = f.uri.pathSegments.last;
      final year = int.tryParse(name.endsWith('.json') ? name.substring(0, name.length - 5) : '');
      if (f is File && year != null) years.add(year);
    }
    return years..sort();
  }

  Future<List<SignalLogEntry>> _load(int year) async {
    final cached = _years[year];
    if (cached != null) return cached;
    final file = _fileFor(year);
    if (!await file.exists()) return _years[year] = const [];
    try {
      final raw = await file.readAsString();
      final entries = _sorted((jsonDecode(raw) as List).map(SignalLogEntry.tryParse).whereType<SignalLogEntry>());
      _written[year] = _encode(entries);
      return _years[year] = entries;
    } on Object {
      // One damaged year costs that year, not the archive — and is kept aside
      // rather than overwritten by the next save.
      await quarantine(file);
      return _years[year] = const [];
    }
  }

  Future<void> _store(int year, Iterable<SignalLogEntry> entries) async {
    final sorted = _sorted(entries);
    _years[year] = sorted;
    final json = _encode(sorted);
    if (json == _written[year]) return;
    final file = _fileFor(year);
    if (sorted.isEmpty) {
      if (await file.exists()) await file.delete();
    } else {
      await _dir.create(recursive: true);
      await writeAtomically(file, json);
    }
    _written[year] = json;
  }

  /// Splits the old single file into years, once. Merged with anything already
  /// in the yearly files, so a crash part-way through and a second attempt
  /// lose nothing; the old file goes only after every year is written.
  Future<void> _migrateLegacy() async {
    if (_migrated) return;
    _migrated = true;
    if (!await _legacy.exists()) return;
    final List<SignalLogEntry> old;
    try {
      old = (jsonDecode(await _legacy.readAsString()) as List)
          .map(SignalLogEntry.tryParse)
          .whereType<SignalLogEntry>()
          .toList();
    } on Object {
      await quarantine(_legacy);
      return;
    }
    for (final MapEntry(key: year, value: inYear) in _byYear(old).entries) {
      final mine = await _load(year);
      final known = mine.map((e) => e.key).toSet();
      await _store(year, [...mine, ...inYear.where((e) => !known.contains(e.key))]);
    }
    await _legacy.delete();
  }

  static Map<int, List<SignalLogEntry>> _byYear(Iterable<SignalLogEntry> entries) {
    final out = <int, List<SignalLogEntry>>{};
    for (final e in entries) {
      (out[e.at.year] ??= []).add(e);
    }
    return out;
  }

  static List<SignalLogEntry> _sorted(Iterable<SignalLogEntry> entries) =>
      entries.toList()..sort((a, b) => b.at.compareTo(a.at));

  static String _encode(List<SignalLogEntry> entries) => jsonEncode(entries.map((e) => e.toJson()).toList());
}
