import 'mission.dart';

/// The translatable text of a pack, by key, and the pack in another language.
///
/// One walk over the pack serves both: [packStrings] collects what it is
/// offered, and [localizePack] answers each offer with the translation. So
/// the keys a translator sees and the keys the app looks up cannot drift.
///
/// Keys are paths — `sp01.brief`, `sp01.sp01_b4.2`, `signals.ambient.7` — not
/// hashes of the English, so a translation keeps showing after the English is
/// reworded rather than dropping back to English.
///
/// Names are never offered: the pack's title, a mission's codename and
/// location, speakers and pursuers. Runners talk to each other about these
/// places, and asked for them to be the same in every language.

/// One translatable string: its English and a note on where it appears.
class PackString {
  const PackString(this.english, this.note, {this.missionId});

  final String english;

  /// For the translator, who sees the string without the screen.
  final String note;

  /// The mission the string belongs to, or null for the pack's own text.
  final String? missionId;
}

/// Every translatable string of [pack], in reading order.
Map<String, PackString> packStrings(MissionPack pack) {
  final strings = <String, PackString>{};
  _walk(pack, (key, english, note, missionId) {
    strings[key] = PackString(english, note, missionId: missionId);
    return null;
  });
  return strings;
}

/// [pack] in [language], from [translations] (key → text).
///
/// A mission is translated whole or not at all: only when every one of its
/// strings has a translation, so a scene never switches language halfway.
/// The pack's own text — tagline, codex categories, its signals — is
/// translated string by string, since nothing there is read in sequence.
///
/// Translated story lines carry the [language] and their English original;
/// signals keep their English for the archive's reference.
MissionPack localizePack(MissionPack pack, String language, Map<String, String> translations) {
  if (translations.isEmpty) return pack;
  final strings = packStrings(pack);
  final incomplete = {
    for (final MapEntry(:key, :value) in strings.entries)
      if (value.missionId != null && (translations[key] ?? '').trim().isEmpty) value.missionId!,
  };
  return _walk(pack, (key, english, note, missionId) {
    if (missionId != null && incomplete.contains(missionId)) return null;
    final text = translations[key];
    return text == null || text.trim().isEmpty ? null : text;
  }, language: language);
}

/// The missions of [pack] that [translations] covers completely.
Set<String> translatedMissions(MissionPack pack, Map<String, String> translations) {
  final strings = packStrings(pack);
  return {
    for (final m in pack.missions)
      if (strings.entries.every(
        (e) => e.value.missionId != m.id || (translations[e.key] ?? '').trim().isNotEmpty,
      ))
        m.id,
  };
}

/// Answers one string with its translation, or null to keep the English.
typedef _Offer = String? Function(String key, String english, String note, String? missionId);

const _spoken = 'Spoken aloud during a run, so write it for the ear. At most 260 characters.';
const _signal = 'A notification sent between runs; never spoken. At most 180 characters.';
const _opener =
    'Opens the weekly debrief notification; the app appends the week\'s figures after it. '
    'Say nothing specific about the numbers. At most 90 characters.';

MissionPack _walk(MissionPack pack, _Offer offer, {String? language}) {
  String? opt(String key, String? english, String note, [String? missionId]) =>
      english == null || english.trim().isEmpty ? english : offer(key, english, note, missionId) ?? english;
  String req(String key, String english, String note, [String? missionId]) => opt(key, english, note, missionId)!;

  List<StoryLine> lines(String prefix, List<StoryLine> source, String where, String missionId) => [
    for (final (i, line) in source.indexed)
      () {
        final text = line.text.trim().isEmpty
            ? null
            : offer('$prefix.$i', line.text, '${line.speaker}, $where. $_spoken', missionId);
        return text != null
            ? StoryLine(
                speaker: line.speaker,
                text: text,
                sfxBefore: line.sfxBefore,
                sfxAfter: line.sfxAfter,
                pauseAfterMs: line.pauseAfterMs,
                language: language,
                original: line.text,
              )
            : line;
      }(),
  ];

  List<Signal> signals(String prefix, List<Signal> source, String note, [String? missionId]) => [
    for (final (i, s) in source.indexed)
      () {
        final text = s.text.trim().isEmpty ? null : offer('$prefix.$i', s.text, '${s.from}. $note', missionId);
        return text == null ? s : Signal(from: s.from, text: text, original: s.source);
      }(),
  ];

  SignalPool pool(String prefix, SignalPool source, String context, [String? missionId]) => SignalPool(
    reminder: signals('$prefix.reminder', source.reminder, 'Nudges the runner to go out$context. $_signal', missionId),
    ambient: signals('$prefix.ambient', source.ambient, 'Unprompted chatter from the city$context. $_signal', missionId),
    debrief: DebriefPool(
      met: signals('$prefix.debrief.met', source.debrief.met, 'The weekly target was met. $_opener', missionId),
      missed: signals('$prefix.debrief.missed', source.debrief.missed, 'The weekly target was missed. $_opener', missionId),
      idle: signals('$prefix.debrief.idle', source.debrief.idle, 'No runs at all this week. $_opener', missionId),
    ),
  );

  // Each category once per pack, however many entries share it.
  final categories = <String, String>{};
  String category(String english) => categories.putIfAbsent(
    english,
    () => req(
      'category.$english',
      english,
      'A section heading in the codex, set in capitals. Short: one or two words.',
    ),
  );

  return MissionPack(
    id: pack.id,
    title: pack.title,
    tagline: opt('tagline', pack.tagline, 'One line under the campaign\'s name (${pack.title}) in the pack list.') ?? '',
    season: pack.season,
    signals: pool('signals', pack.signals, ''),
    missions: [
      for (final m in pack.missions)
        () {
          final id = m.id;
          final at = 'operation ${m.codename} ($id)';
          return Mission(
            id: id,
            packId: m.packId,
            order: m.order,
            codename: m.codename,
            location: m.location,
            suggestedGoal: m.suggestedGoal,
            title: req('$id.title', m.title, 'The title of $at, shown under its codename.', id),
            objective: opt('$id.objective', m.objective, 'One line: what the runner does in $at.', id) ?? '',
            brief: opt('$id.brief', m.brief, 'The briefing of $at, read before the run.', id) ?? '',
            debrief: opt('$id.debrief', m.debrief, 'Shown after $at is completed.', id) ?? '',
            epilogue: opt('$id.epilogue', m.epilogue, 'Shown after $at, the last of ${pack.title}.', id),
            codex: [
              for (final c in m.codex)
                CodexEntry(
                  id: c.id,
                  title: req(
                    '$id.codex.${c.id}.title',
                    c.title,
                    'The title of a codex entry found in $at. Keep it as it is if it is a name.',
                    id,
                  ),
                  category: category(c.category),
                  body: req('$id.codex.${c.id}.body', c.body, 'A codex entry about "${c.title}", read at leisure.', id),
                ),
            ],
            beats: [
              for (final b in m.beats)
                () {
                  final where = 'in $at, scene ${b.id}';
                  final chase = b.chase;
                  return StoryBeat(
                    id: b.id,
                    trigger: b.trigger,
                    unlocksCodex: b.unlocksCodex,
                    headline: opt(
                      '$id.${b.id}.headline',
                      b.headline,
                      'A banner flashed on the run screen $where. Capitals, two or three words.',
                      id,
                    ),
                    lines: lines('$id.${b.id}', b.lines, where, id),
                    chase: chase == null
                        ? null
                        : ChaseSpec(
                            duration: chase.duration,
                            paceFactor: chase.paceFactor,
                            pursuer: chase.pursuer,
                            escapedLines: lines(
                              '$id.${b.id}.escaped',
                              chase.escapedLines,
                              '$where, after the runner escapes ${chase.pursuer}',
                              id,
                            ),
                            caughtLines: lines(
                              '$id.${b.id}.caught',
                              chase.caughtLines,
                              '$where, after ${chase.pursuer} catches the runner',
                              id,
                            ),
                          ),
                  );
                }(),
            ],
            signals: pool('$id.signals', m.signals, ' while $at is the next one waiting', id),
          );
        }(),
    ],
    translations: pack.translations,
  );
}
