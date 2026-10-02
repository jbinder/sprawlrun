import '../models/mission.dart';
import '../models/signal_log.dart';

/// Every authored signal line in the loaded packs, by [signalRef] — how the
/// archive gets its words back.
class SignalLibrary {
  SignalLibrary.fromPacks(List<MissionPack> packs)
    : _byRef = {
        for (final line in [
          for (final pack in packs) ...[
            ..._linesOf(pack.signals),
            for (final mission in pack.missions) ..._linesOf(mission.signals),
          ],
        ])
          signalRef(line): line,
      };

  final Map<String, String> _byRef;

  static Iterable<String> _linesOf(SignalPool pool) => [
    ...pool.reminder,
    ...pool.ambient,
    ...pool.debrief.met,
    ...pool.debrief.missed,
    ...pool.debrief.idle,
  ].map((s) => s.text);

  /// The entry with its words, or null when its line is no longer in any pack —
  /// reworded since, or its pack removed. Left out rather than shown as a
  /// reference, the same as intel from a pack that is gone.
  SentSignal? resolve(SignalLogEntry entry) {
    final opener = _byRef[entry.ref];
    if (opener == null) return null;
    final figures = entry.figures;
    return SentSignal(
      at: entry.at,
      kind: entry.kind,
      from: entry.from,
      text: figures == null ? opener : '$opener ${figures.sentence}',
    );
  }

  List<SentSignal> resolveAll(Iterable<SignalLogEntry> entries) =>
      entries.map(resolve).whereType<SentSignal>().toList();
}
