import 'mission.dart';

/// Which kind of between-run message a signal is.
enum SignalKind { reminder, ambient, debrief }

/// A short, stable reference to an authored signal line: 32-bit FNV-1a over the
/// text, as eight hex digits.
///
/// Not `String.hashCode`, which Dart does not promise to keep the same between
/// runs or versions — and these are written to disk and into backups.
String signalRef(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// The numbers behind a weekly debrief. Stored rather than referenced, because
/// they are the one part of a signal no pack author wrote.
class SignalFigures {
  const SignalFigures({required this.value, required this.target, required this.unit, required this.weeks});

  /// Progress toward the week's target, in the goal's own unit.
  final double value;
  final double target;

  /// The goal's unit as the streak card shows it: `MIN`, `KM`, `OPS`.
  final String unit;

  /// How long the streak had stood when the debrief was planned.
  final int weeks;

  DebriefOutcome get outcome => value >= target
      ? DebriefOutcome.met
      : value > 0
      ? DebriefOutcome.missed
      : DebriefOutcome.idle;

  /// The sentence appended to the authored opener.
  String get sentence {
    final unitWord = unit.toLowerCase();
    final done = _trim(value);
    final goal = _trim(target);
    final stood = weeks == 1 ? 'one week' : '$weeks weeks';
    return switch (outcome) {
      DebriefOutcome.met => weeks > 0 ? '$done of $goal $unitWord. The streak stands at $stood.' : '$done of $goal $unitWord.',
      DebriefOutcome.missed =>
        '$done of $goal $unitWord, so ${_trim(target - value)} $unitWord short with the week nearly out.',
      DebriefOutcome.idle => weeks > 0
          ? 'Nothing logged. $goal $unitWord would keep a streak that has stood $stood.'
          : 'Nothing logged all week. The target is $goal $unitWord.',
    };
  }

  /// Whole numbers without a trailing `.0`; one decimal otherwise.
  static String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  Map<String, dynamic> toJson() => {'value': value, 'target': target, 'unit': unit, 'weeks': weeks};

  static SignalFigures? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['value'];
    final target = raw['target'];
    final unit = raw['unit'];
    final weeks = raw['weeks'];
    if (value is! num || target is! num || unit is! String || weeks is! num) return null;
    return SignalFigures(value: value.toDouble(), target: target.toDouble(), unit: unit, weeks: weeks.toInt());
  }
}

/// A signal as it was scheduled, kept so it can be read again — for good.
///
/// Stores a [ref] to the authored line rather than its text, the same way a
/// run's story log stores beat ids rather than dialogue: the words live in the
/// pack and are looked up when the archive is shown. That keeps an entry to a
/// few dozen bytes, which is what makes an archive with no cap reasonable. The
/// cost is the same as for beats — a line later reworded in its pack, or a
/// pack removed altogether, can no longer be shown.
///
/// What is stored is the *plan*, not a delivery receipt: no Dart runs when a
/// notification fires. An entry whose time has passed is taken to have been
/// sent — wrong only when the runner has blocked notifications in Android.
class SignalLogEntry {
  const SignalLogEntry({
    required this.at,
    required this.kind,
    required this.from,
    required this.ref,
    this.figures,
  });

  final DateTime at;
  final SignalKind kind;
  final String from;

  /// [signalRef] of the authored line. For a debrief, of its opener only.
  final String ref;

  /// Set for a debrief only.
  final SignalFigures? figures;

  /// Identity for de-duplication when two logs are merged on import.
  String get key => '${at.toIso8601String()}|${kind.name}|$from';

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'kind': kind.name,
    'from': from,
    'ref': ref,
    if (figures != null) 'figures': figures!.toJson(),
  };

  /// Null rather than throwing for anything malformed, so one bad entry costs
  /// that entry and not the whole archive.
  static SignalLogEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse(raw['at'] as String? ?? '');
    final kind = SignalKind.values.where((k) => k.name == raw['kind']).firstOrNull;
    final from = raw['from'];
    // An entry written with its full text, before references, is read by
    // referencing that text — which resolves for any line still in its pack.
    final ref = raw['ref'] ?? (raw['text'] is String ? signalRef(raw['text'] as String) : null);
    if (at == null || kind == null || from is! String || ref is! String || ref.isEmpty) return null;
    return SignalLogEntry(at: at, kind: kind, from: from, ref: ref, figures: SignalFigures.tryParse(raw['figures']));
  }
}

/// A sent signal with its words looked up, ready to show.
class SentSignal {
  const SentSignal({required this.at, required this.kind, required this.from, required this.text});

  final DateTime at;
  final SignalKind kind;
  final String from;
  final String text;
}
