import '../models/mission.dart';
import '../models/signal_log.dart';

/// Every authored signal line in the loaded packs, by [signalRef] — how the
/// archive gets its words back.
///
/// The reference is always of the English line, and the words are whatever the
/// packs show now: a signal sent in English reads in Spanish once the runner
/// switches, and the other way round.
class SignalLibrary {
  SignalLibrary.fromPacks(List<MissionPack> packs)
    : _byRef = {
        for (final signal in [
          for (final pack in packs) ...[
            ..._signalsOf(pack.signals),
            for (final mission in pack.missions) ..._signalsOf(mission.signals),
          ],
        ])
          signal.ref: signal.text,
      };

  final Map<String, String> _byRef;

  static Iterable<Signal> _signalsOf(SignalPool pool) => [
    ...pool.reminder,
    ...pool.ambient,
    ...pool.debrief.met,
    ...pool.debrief.missed,
    ...pool.debrief.idle,
  ];

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
