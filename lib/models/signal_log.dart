/// Which kind of between-run message a signal is.
enum SignalKind { reminder, ambient, debrief }

/// A signal as it was scheduled, kept so it can be read again later.
///
/// What is stored is the *plan*, not a delivery receipt: no Dart runs when a
/// notification fires, so the app cannot know one actually reached the shade.
/// An entry whose time has passed is taken to have been sent — accurate to
/// within the few minutes an inexact alarm may slip, and wrong only when the
/// runner has blocked notifications in Android's settings.
class SignalLogEntry {
  const SignalLogEntry({required this.at, required this.kind, required this.from, required this.text});

  final DateTime at;
  final SignalKind kind;
  final String from;
  final String text;

  /// Identity for de-duplication when two logs are merged on import.
  String get key => '${at.toIso8601String()}|${kind.name}|$from';

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'kind': kind.name,
    'from': from,
    'text': text,
  };

  /// Null rather than throwing for anything malformed, so one bad entry costs
  /// that entry and not the whole log.
  static SignalLogEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse(raw['at'] as String? ?? '');
    final kind = SignalKind.values.where((k) => k.name == raw['kind']).firstOrNull;
    final from = raw['from'];
    final text = raw['text'];
    if (at == null || kind == null || from is! String || text is! String || text.isEmpty) return null;
    return SignalLogEntry(at: at, kind: kind, from: from, text: text);
  }
}
