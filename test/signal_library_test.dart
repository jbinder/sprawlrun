import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/signal_log.dart';
import 'package:sprawl_run/services/signal_library.dart';

/// How the archive gets its words back from the packs.
void main() {
  final at = DateTime(2026, 10, 1, 9);
  const pack = MissionPack(
    id: 'null_tide',
    title: 'NULL TIDE',
    tagline: '',
    missions: [],
    signals: SignalPool(
      ambient: [Signal(from: 'WREN', text: 'The gulls have moved inland.')],
      debrief: DebriefPool(missed: [Signal(from: 'MARROW', text: 'Tide is nearly out on the week.')]),
    ),
  );
  final library = SignalLibrary.fromPacks(const [pack]);

  test('a reference finds its line', () {
    final sent = library.resolve(
      SignalLogEntry(at: at, kind: SignalKind.ambient, from: 'WREN', ref: signalRef('The gulls have moved inland.')),
    );
    expect(sent?.text, 'The gulls have moved inland.');
    expect(sent?.from, 'WREN');
  });

  test('a debrief gets its figures back, rendered as the notification read', () {
    final sent = library.resolve(
      SignalLogEntry(
        at: at,
        kind: SignalKind.debrief,
        from: 'MARROW',
        ref: signalRef('Tide is nearly out on the week.'),
        figures: const SignalFigures(value: 12, target: 30, unit: 'MIN', weeks: 3),
      ),
    );
    expect(sent?.text, 'Tide is nearly out on the week. 12 of 30 min, so 18 min short with the week nearly out.');
  });

  test('a line no longer in any pack is left out, not shown as a reference', () {
    // Reworded since, or its pack removed — the same rule as intel from a
    // pack that is gone, and as a run's beats.
    expect(
      library.resolve(SignalLogEntry(at: at, kind: SignalKind.ambient, from: 'WREN', ref: signalRef('Reworded.'))),
      isNull,
    );
  });

  test('references are stable across runs and versions', () {
    // Written to disk and into backups, so this value must never change. A
    // change here means every archive in the field stops resolving.
    expect(signalRef('The gulls have moved inland.'), '7e392c12'); // checked against an independent FNV-1a
    expect(signalRef(''), '811c9dc5');
  });
}
