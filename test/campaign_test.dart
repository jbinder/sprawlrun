import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/services/narrator.dart';

/// Guards the shipped campaign against the kinds of damage that only show up
/// twenty minutes into a run: a beat that never fires, a codex entry nothing
/// unlocks, a chase with no lines.
void main() {
  // Every bundled pack gets the same checks. A pack that only side-loads can
  // be added here temporarily to get them too.
  for (final path in MissionRepository.bundledPacks) {
    group(path.split('/').last, () => _checks(path));
  }

  test('the voices the packs speak with are the ones the narrator can voice', () {
    // Cheap sanity on the table itself: every profile is distinct enough to
    // tell apart in a pocket.
    final profiles = VoiceProfile.bySpeaker.values.map((v) => (v.pitch, v.rateScale)).toList();
    expect(profiles.toSet(), hasLength(profiles.length), reason: 'two speakers share a voice');
  });
}

void _checks(String path) {
  late MissionPack pack;

  setUpAll(() {
    final raw = File(path).readAsStringSync();
    pack = MissionPack.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  });

  test('the pack holds ten missions in unbroken order', () {
    expect(pack.missions, hasLength(10));
    for (var i = 0; i < pack.missions.length; i++) {
      expect(pack.missions[i].order, i + 1);
    }
  });

  test('mission ids are unique', () {
    final ids = pack.missions.map((m) => m.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('the pack has its achievements: a registered id prefix every mission uses', () {
    // Pack-completion achievements recognise a pack's missions by this prefix,
    // so a pack without an entry here can never be "completed" on the wall.
    final prefix = kPackMissionPrefixes[pack.id];
    expect(prefix, isNotNull, reason: '${pack.id} is missing from kPackMissionPrefixes');
    for (final m in pack.missions) {
      expect(m.id, startsWith(prefix!), reason: '${m.id} does not carry the ${pack.id} prefix');
    }
    final others = kPackMissionPrefixes.entries.where((e) => e.key != pack.id && e.value == prefix);
    expect(others, isEmpty, reason: 'another pack shares the prefix $prefix');
  });

  test('every mission has the text the UI renders', () {
    for (final m in pack.missions) {
      expect(m.codename, isNotEmpty, reason: '${m.id} codename');
      expect(m.title, isNotEmpty, reason: '${m.id} title');
      expect(m.location, isNotEmpty, reason: '${m.id} location');
      expect(m.brief.length, greaterThan(80), reason: '${m.id} brief is too thin to be a briefing');
      expect(m.objective, isNotEmpty, reason: '${m.id} objective');
      expect(m.debrief.length, greaterThan(40), reason: '${m.id} debrief');
    }
  });

  test('every mission has a usable goal', () {
    for (final m in pack.missions) {
      expect(m.suggestedGoal.value, greaterThan(0), reason: m.id);
      if (m.suggestedGoal.isTime) {
        expect(m.suggestedGoal.value, inInclusiveRange(300, 7200), reason: '${m.id} time goal');
      } else {
        expect(m.suggestedGoal.value, inInclusiveRange(1000, 42200), reason: '${m.id} distance goal');
      }
    }
  });

  test('beats are ordered by trigger, so none can be skipped', () {
    for (final m in pack.missions) {
      var previous = -1.0;
      for (final beat in m.beats) {
        final fraction = beat.trigger.fraction;
        if (fraction == null) continue;
        expect(
          fraction,
          greaterThanOrEqualTo(previous),
          reason: '${m.id}/${beat.id} triggers before the beat above it',
        );
        expect(fraction, inInclusiveRange(0.0, 1.0), reason: '${m.id}/${beat.id}');
        previous = fraction;
      }
    }
  });

  test('beat ids are unique inside a mission', () {
    for (final m in pack.missions) {
      final ids = m.beats.map((b) => b.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: m.id);
    }
  });

  test('every beat says something, from a known speaker', () {
    // The narrator's own table, so a new speaker cannot be added to a pack
    // without also being given a voice.
    final known = VoiceProfile.bySpeaker.keys.toSet();
    for (final m in pack.missions) {
      for (final beat in m.beats) {
        expect(beat.lines, isNotEmpty, reason: '${m.id}/${beat.id}');
        for (final line in beat.lines) {
          expect(line.text.trim(), isNotEmpty, reason: '${m.id}/${beat.id}');
          expect(known, contains(line.speaker), reason: '${m.id}/${beat.id} unknown speaker');
          // Lines are spoken aloud mid-run; anything longer stops being a line
          // and starts being a paragraph.
          expect(line.text.length, lessThan(260), reason: '${m.id}/${beat.id} line is too long to speak');
        }
      }
    }
  });

  test('every mission opens at the start and resolves at the target', () {
    for (final m in pack.missions) {
      expect(
        m.beats.any((b) => b.trigger.fraction == 0.0),
        isTrue,
        reason: '${m.id} has no opening beat',
      );
      expect(
        m.beats.any((b) => b.trigger.fraction == 1.0),
        isTrue,
        reason: '${m.id} has nothing to say when the target is met',
      );
    }
  });

  test('every mission has at least one pursuit, fully specified', () {
    for (final m in pack.missions) {
      expect(m.chaseBeats, isNotEmpty, reason: '${m.id} has no pursuit');
      for (final beat in m.chaseBeats) {
        final chase = beat.chase!;
        expect(chase.duration.inSeconds, inInclusiveRange(30, 180), reason: '${m.id}/${beat.id}');
        expect(chase.paceFactor, inInclusiveRange(1.02, 1.5), reason: '${m.id}/${beat.id}');
        expect(chase.pursuer, isNot('unknown'), reason: '${m.id}/${beat.id}');
        expect(chase.escapedLines, isNotEmpty, reason: '${m.id}/${beat.id} has no escape lines');
        expect(chase.caughtLines, isNotEmpty, reason: '${m.id}/${beat.id} has no caught lines');
      }
    }
  });

  test('every codex entry is unlocked by exactly one beat, and vice versa', () {
    final defined = <String>{};
    for (final m in pack.missions) {
      for (final entry in m.codex) {
        expect(defined.add(entry.id), isTrue, reason: 'duplicate codex id ${entry.id}');
        expect(entry.title, isNotEmpty);
        expect(entry.body.length, greaterThan(60), reason: '${entry.id} body');
      }
    }

    final referenced = <String>[];
    for (final m in pack.missions) {
      for (final beat in m.beats) {
        if (beat.unlocksCodex != null) referenced.add(beat.unlocksCodex!);
      }
    }

    expect(referenced.toSet().difference(defined), isEmpty, reason: 'beats unlock codex entries that do not exist');
    expect(defined.difference(referenced.toSet()), isEmpty, reason: 'codex entries no beat ever unlocks');
    expect(referenced.toSet(), hasLength(referenced.length), reason: 'a codex entry is unlocked twice');
  });

  test('a codex entry is only unlocked by the mission that defines it', () {
    for (final m in pack.missions) {
      final own = m.codex.map((c) => c.id).toSet();
      final unlockedHere = m.beats.map((b) => b.unlocksCodex).whereType<String>().toSet();
      expect(unlockedHere, equals(own), reason: '${m.id} unlocks entries it does not define, or vice versa');
    }
  });

  test('every referenced sound effect is a file that ships', () {
    final available = Directory('assets/sfx')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last.replaceAll('.wav', ''))
        .toSet();

    for (final m in pack.missions) {
      for (final beat in m.beats) {
        for (final line in [...beat.lines, ...?beat.chase?.escapedLines, ...?beat.chase?.caughtLines]) {
          for (final sfx in [line.sfxBefore, line.sfxAfter].whereType<String>()) {
            expect(available, contains(sfx), reason: '${m.id}/${beat.id} references missing sfx "$sfx"');
          }
        }
      }
    }
  });

  test('every signal is sendable: a known speaker, short, and never repeated', () {
    // Signals are notifications, never spoken — but the speaker still has to
    // be someone the pack actually uses, or the name on the notification is
    // a character who does not exist.
    final pools = <String, SignalPool>{
      'pack': pack.signals,
      for (final m in pack.missions)
        if (!m.signals.isEmpty) m.id: m.signals,
    };

    final seen = <String>{};
    pools.forEach((owner, pool) {
      for (final signal in [...pool.reminder, ...pool.ambient]) {
        expect(
          VoiceProfile.bySpeaker.keys,
          contains(signal.from),
          reason: '$owner: unknown speaker ${signal.from}',
        );
        expect(signal.text.trim(), isNotEmpty, reason: owner);
        // Android truncates a long notification body; anything past this is
        // written for a screen the runner will not see.
        expect(signal.text.length, lessThan(180), reason: '$owner: "${signal.text}"');
        expect(seen.add(signal.text), isTrue, reason: 'duplicated signal: "${signal.text}"');
      }
    });
  });

  test('the pack can always speak, whatever the runner has finished', () {
    // Mission pools are optional — copy gets written over time — but the
    // generic pool is the fallback for a finished campaign and for a runner
    // who never starts one, so it has to exist.
    expect(pack.signals.reminder, isNotEmpty, reason: 'no generic reminders to fall back on');
  });

  test('the final mission carries an epilogue and nothing else does', () {
    for (final m in pack.missions) {
      if (m.order == 10) {
        expect(m.epilogue, isNotNull);
        expect(m.epilogue!.length, greaterThan(100));
      } else {
        expect(m.epilogue, isNull, reason: '${m.id} should not end the campaign');
      }
    }
  });

  test('there is enough story to fill the run', () {
    for (final m in pack.missions) {
      // Ten beats across a 15-40 minute run is a transmission every few
      // minutes, which is the pacing the whole design rests on.
      expect(m.beats.length, greaterThanOrEqualTo(8), reason: '${m.id} is too quiet');
    }
  });
}
