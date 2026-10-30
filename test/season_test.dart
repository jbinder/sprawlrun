import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/models/achievement.dart';
import 'package:sprawl_run/models/mission.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/services/achievement_engine.dart';
import 'package:sprawl_run/services/narrator.dart';
import 'package:sprawl_run/services/signal_planner.dart';
import 'package:sprawl_run/services/stats_service.dart';
import 'package:sprawl_run/state/app_state.dart';
import 'package:sprawl_run/theme/cyber_palette.dart';
import 'package:sprawl_run/theme/season.dart';
import 'package:sprawl_run/util/clock.dart';

import 'support/fakes.dart';

void main() {
  tearDown(() {
    debugNow = null;
    Season.debugReset();
  });

  group('the window', () {
    test('SAMHAIN PROTOCOL is 10 October to 2 November, inclusive, every year', () {
      const s = Season.samhain;
      expect(s.from, (month: 10, day: 10));
      expect(s.until, (month: 11, day: 2));
      expect(s.contains(DateTime(2026, 10, 9, 23, 59)), isFalse);
      expect(s.contains(DateTime(2026, 10, 10)), isTrue);
      expect(s.contains(DateTime(2031, 10, 31, 22)), isTrue);
      expect(s.contains(DateTime(2026, 11, 2, 23, 59)), isTrue);
      expect(s.contains(DateTime(2026, 11, 3)), isFalse);
    });

    test('counts down the days left', () {
      const s = Season.samhain;
      expect(s.daysLeft(DateTime(2026, 10, 30, 23)), 3);
      expect(s.daysLeft(DateTime(2026, 11, 2, 8)), 0);
      // Across the clocks going back on 25 October.
      expect(s.daysLeft(DateTime(2026, 10, 20, 12)), 13);
    });

    test('nothing is in season in the summer', () {
      expect(Season.at(DateTime(2026, 7, 27, 21, 14)), isNull);
      // The store screenshots are pinned to this instant; they must show the
      // year-round look.
      expect(Season.at(DateTime(2026, 9, 27, 21)), isNull);
    });

    test('applying a season swaps the palette and clearing it puts it back', () {
      expect(Season.apply(Season.samhain), isTrue);
      expect(Cy.cyan, CyPalette.samhain.cyan);
      expect(Season.apply(Season.samhain), isFalse, reason: 'no change, nothing to rebuild');
      Season.apply(null);
      expect(Cy.cyan, CyPalette.standard.cyan);
    });
  });

  group('the runner\'s look', () {
    test('is worn outside a season and yields to one inside it', () {
      expect(Season.apply(null, otherwise: CyPalette.glacier), isTrue, reason: 'a new look is a change');
      expect(Cy.cyan, CyPalette.glacier.cyan);
      expect(Season.apply(null, otherwise: CyPalette.glacier), isFalse);

      Season.apply(Season.samhain, otherwise: CyPalette.glacier);
      expect(Cy.cyan, CyPalette.samhain.cyan);
      expect(Season.apply(null, otherwise: CyPalette.glacier), isTrue);
      expect(Cy.cyan, CyPalette.glacier.cyan, reason: 'it comes back when the season ends');
    });

    test('is stored by name and decodes from a profile that lacks it', () {
      expect(Profile.fromJson(const {'callsign': 'CASE'}).look, Look.neon);
      expect(Profile.fromJson(const Profile(look: Look.volt).toJson()).look, Look.volt);
      expect(Profile.fromJson(const {'look': 'chartreuse'}).look, Look.neon, reason: 'a look from a newer build');
    });

    test('every look keeps the roles apart, and success is the same green family', () {
      for (final look in Look.values) {
        final p = look.palette;
        final roles = {p.cyan, p.magenta, p.amber, p.green, p.red};
        expect(roles, hasLength(5), reason: '\${look.name} gives two roles one colour');
        final hsv = HSVColor.fromColor(p.green);
        expect(hsv.hue, inInclusiveRange(80, 165), reason: '\${look.name}: a met goal should look met');
      }
    });
  });

  test('every seasonal sound effect has its file', () {
    for (final season in Season.values) {
      for (final name in season.sfxVariants) {
        final asset = AudioNarrator.sfxAsset(name, season);
        expect(File(asset).existsSync(), isTrue, reason: '$asset is missing; run tool/gen_sfx.dart');
      }
    }
    expect(AudioNarrator.sfxAsset('alert', Season.samhain), 'assets/sfx/alert.wav', reason: 'no variant, plain one');
    expect(AudioNarrator.sfxAsset('drone', null), 'assets/sfx/drone.wav');
  });

  test('an old profile has seasonal events on', () {
    expect(Profile.fromJson(const {'callsign': 'CASE'}).seasonalEvents, isTrue);
    expect(Profile.fromJson(const Profile(seasonalEvents: false).toJson()).seasonalEvents, isFalse);
  });

  group('the event pack', () {
    late Directory root;
    setUp(() => root = tempRoot('season'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<AppState> loaded({required DateTime at, bool events = true}) async {
      debugNow = at;
      final profiles = ProfileRepository(root);
      await profiles.save(Profile(callsign: 'CASE', seasonalEvents: events));
      final state = AppState(
        profiles: profiles,
        runs: RunRepository(Directory('${root.path}/runs')),
        missions: MissionRepository(externalDir: Directory('${root.path}/packs'), bundle: _DiskBundle()),
        narrator: FakeNarrator(),
      );
      await state.load();
      return state;
    }

    test('is offered in season', () async {
      final state = await loaded(at: DateTime(2026, 10, 30, 19));
      expect(state.season, Season.samhain);
      expect(state.visiblePacks.map((p) => p.id), contains('samhain'));
      expect(state.seasonalPack?.id, 'samhain');
    });

    test('is hidden out of season, but its missions still resolve for old runs', () async {
      final state = await loaded(at: DateTime(2026, 12, 5, 19));
      expect(state.season, isNull);
      expect(state.visiblePacks.map((p) => p.id), isNot(contains('samhain')));
      expect(state.missionById('sh01'), isNotNull);
    });

    test('is hidden when the runner turned seasonal events off', () async {
      final state = await loaded(at: DateTime(2026, 10, 30, 19), events: false);
      expect(state.season, isNull);
      expect(state.seasonalPack, isNull);
    });

    test('a selected event pack falls back to a campaign once the season is over', () async {
      final inSeason = await loaded(at: DateTime(2026, 10, 30, 19));
      await inSeason.selectPack('samhain');
      expect(inSeason.activePack?.id, 'samhain');

      debugNow = DateTime(2026, 11, 20, 19);
      expect(inSeason.activePack?.id, 'sprawl_prime');
    });
  });

  group('handler traffic', () {
    const settings = SignalSettings(ambientPerWeek: 14);
    final seasonal = SignalPool(
      ambient: [for (var i = 0; i < 20; i++) Signal(from: 'LANTERN', text: 'seasonal $i')],
      reminder: const [Signal(from: 'LANTERN', text: 'seasonal reminder')],
    );
    final campaign = MissionPack(
      id: 'c',
      title: 'C',
      tagline: '',
      missions: const [],
      signals: SignalPool(ambient: [for (var i = 0; i < 20; i++) Signal(from: 'KESTREL', text: 'campaign $i')]),
    );

    test('a season cuts in on the campaign rather than replacing it', () {
      final plan = SignalPlanner.plan(
        now: DateTime(2026, 10, 26, 9),
        settings: settings,
        runLog: const [],
        pack: campaign,
        seasonal: seasonal,
      );
      final from = plan.where((p) => p.kind == SignalKind.ambient).map((p) => p.from).toSet();
      expect(from, containsAll(['LANTERN', 'KESTREL']));
    });

    test('nothing seasonal without a season', () {
      final plan = SignalPlanner.plan(now: DateTime(2026, 10, 26, 9), settings: settings, runLog: const [], pack: campaign);
      expect(plan.map((p) => p.from), everyElement('KESTREL'));
    });
  });

  group('seasonal achievements', () {
    test('count runs by the calendar, across years', () {
      final log = [
        run(at: DateTime(2025, 10, 31, 21)),
        run(at: DateTime(2026, 10, 10, 7)),
        run(at: DateTime(2026, 10, 25, 7)),
        run(at: DateTime(2026, 11, 2, 7)),
        run(at: DateTime(2026, 11, 3, 7)),
        run(at: DateTime(2026, 10, 9, 7)),
      ];
      final stats = StatsService.lifetime(log, const StreakGoal());
      expect(stats.hallowsEveRuns, 1);
      expect(stats.samhainRuns, 4);
      expect(stats.samhainYears, 2);

      final earned = AchievementEngine.newlyEarned(stats, const {}).map((a) => a.id);
      expect(earned, containsAll(['hallows_eve', 'samhain_years_2']));
      expect(earned, isNot(contains('samhain_5')));
    });

    test('the event pack has its completion achievements', () {
      expect(kAchievements.where((a) => a.category == AchCategory.seasonal).map((a) => a.id), containsAll(['sh_1', 'sh_4']));
    });
  });
}

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.view(bytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}
