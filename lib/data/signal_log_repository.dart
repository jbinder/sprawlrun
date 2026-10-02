import 'dart:convert';
import 'dart:io';

import '../models/signal_log.dart';
import 'atomic_write.dart';

/// Keeps the signals the handlers have sent, so the timeline can show them
/// after the notification is gone.
///
/// The only thing on the timeline that is stored. Runs, cleared missions,
/// achievements and codex entries are all projected from the run log and the
/// profile when the timeline is drawn; a signal has no other record anywhere,
/// because the plan that produced it is rebuilt from scratch on every launch.
class SignalLogRepository {
  SignalLogRepository(this.root);

  final Directory root;

  /// How long a sent signal is kept. Long enough to scroll back through a few
  /// weeks of a campaign; short enough that the file stays a few kilobytes at
  /// two signals a day.
  static const Duration keepFor = Duration(days: 60);

  /// A ceiling regardless of age, in case a clock jump or a merged backup
  /// floods the log.
  static const int maxEntries = 300;

  File get _file => File('${root.path}/signals.json');

  List<SignalLogEntry>? _cache;

  /// Every stored entry, newest first — including ones still in the future,
  /// which are the current plan and have not been sent yet.
  Future<List<SignalLogEntry>> loadAll() async {
    if (_cache != null) return _cache!;
    if (!await _file.exists()) return _cache = const [];
    try {
      final raw = jsonDecode(await _file.readAsString());
      final entries = (raw as List).map(SignalLogEntry.tryParse).whereType<SignalLogEntry>().toList()
        ..sort((a, b) => b.at.compareTo(a.at));
      return _cache = entries;
    } on Object {
      // Losing the signal history is a shame, not a disaster — but the file is
      // still kept aside rather than overwritten by the next save.
      await quarantine(_file);
      return _cache = const [];
    }
  }

  /// The entries whose time has come, newest first. What the timeline shows.
  Future<List<SignalLogEntry>> sent(DateTime now) async =>
      (await loadAll()).where((e) => !e.at.isAfter(now)).toList();

  /// Records a freshly scheduled plan.
  ///
  /// Everything already in the past is kept: it fired. Everything still in the
  /// future is dropped and replaced by [plan], because scheduling cancels the
  /// previous plan's pending notifications — so an entry that was planned and
  /// then re-planned away never reaches the timeline. An empty plan, from the
  /// runner switching signals off, therefore clears what was pending and leaves
  /// history alone.
  Future<List<SignalLogEntry>> record(List<SignalLogEntry> plan, DateTime now) async {
    final past = (await loadAll()).where((e) => !e.at.isAfter(now));
    return _write([...past, ...plan.where((e) => e.at.isAfter(now))], now);
  }

  /// Replaces the whole log, for restoring a backup onto this device.
  Future<List<SignalLogEntry>> replaceAll(List<SignalLogEntry> entries, DateTime now) => _write(entries, now);

  /// Adds whatever [entries] has that this log does not, for merging a backup.
  Future<List<SignalLogEntry>> merge(List<SignalLogEntry> entries, DateTime now) async {
    final mine = await loadAll();
    final known = mine.map((e) => e.key).toSet();
    return _write([...mine, ...entries.where((e) => !known.contains(e.key))], now);
  }

  Future<List<SignalLogEntry>> _write(Iterable<SignalLogEntry> entries, DateTime now) async {
    final cutoff = now.subtract(keepFor);
    final kept = entries.where((e) => !e.at.isBefore(cutoff)).toList()..sort((a, b) => b.at.compareTo(a.at));
    final capped = kept.length > maxEntries ? kept.sublist(0, maxEntries) : kept;
    _cache = capped;
    await root.create(recursive: true);
    await writeAtomically(_file, jsonEncode(capped.map((e) => e.toJson()).toList()));
    return capped;
  }
}
