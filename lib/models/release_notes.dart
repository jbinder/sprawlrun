import '../l10n/l10n.dart';

/// What one version brought, as the runner is told about it after updating.
///
/// A few lines of what is new, and fixes in one general line at most — the
/// whole list is on the GitHub release, which the popup links to. The text is
/// in the ARB files like every other string, so translators see it.
class ReleaseNote {
  const ReleaseNote({required this.version, required this.name, required this.items});

  /// `versionName`, e.g. `0.9.0`.
  final String version;

  /// The release's name, e.g. "Soundtrack".
  final String Function(L l) name;

  /// What is new, one line each, most important first.
  final List<String> Function(L l) items;
}

/// Every version that has notes, newest first.
///
/// **Add the new version's entry at the top of [all] with every release**, and
/// keep the older ones: a runner who skipped versions is shown each one they
/// missed.
class ReleaseNotes {
  ReleaseNotes._();

  static final List<ReleaseNote> all = [
    ReleaseNote(
      version: '0.9.0',
      name: (l) => l.release090Name,
      items: (l) => [l.release090Music, l.release090Library, l.release090Fixes],
    ),
  ];

  /// How many versions a catch-up popup lists; anything older is on GitHub.
  static const int shownAtMost = 5;

  static ReleaseNote? of(String version, {List<ReleaseNote>? from}) {
    for (final note in from ?? all) {
      if (note.version == version) return note;
    }
    return null;
  }

  /// The notes a runner on [current] has not seen, newest first, given the
  /// version whose notes they last saw.
  ///
  /// [seen] is null for an installation from before release notes existed:
  /// which version it last ran is unknown, so it is told about [current] only.
  /// [from] stands in for [all] in tests.
  static List<ReleaseNote> since(String? seen, String current, {List<ReleaseNote>? from}) {
    if (seen == current) return const [];
    if (seen == null) {
      final note = of(current, from: from);
      return note == null ? const [] : [note];
    }
    return [
      for (final note in from ?? all)
        if (compareVersions(note.version, seen) > 0 && compareVersions(note.version, current) <= 0) note,
    ].take(shownAtMost).toList();
  }

  /// Orders `1.2.3`-style versions numerically; anything after `+` or `-` is
  /// ignored, and a part that is not a number counts as 0.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split(RegExp('[+-]')).first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < x.length || i < y.length; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }
}
