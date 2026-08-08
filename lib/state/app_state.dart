import 'package:flutter/foundation.dart';

import '../data/backup.dart';
import '../data/mission_repository.dart';
import '../data/profile_repository.dart';
import '../data/run_repository.dart';
import '../models/achievement.dart';
import '../models/goal.dart';
import '../models/mission.dart';
import '../models/profile.dart';
import '../models/run_record.dart';
import '../models/stats.dart';
import '../services/achievement_engine.dart';
import '../services/narrator.dart';
import '../services/stats_service.dart';

/// The single source of truth the UI reads from.
///
/// Holds the loaded profile, run log and mission packs, and keeps the derived
/// stats caches in step with them. Everything expensive is recomputed once per
/// mutation rather than per rebuild.
class AppState extends ChangeNotifier {
  AppState({
    required this.profiles,
    required this.runs,
    required this.missions,
    required this.narrator,
  });

  final ProfileRepository profiles;
  final RunRepository runs;
  final MissionRepository missions;
  final Narrator narrator;

  late final BackupService backups = BackupService(profiles: profiles, runs: runs);

  Profile profile = const Profile();
  List<RunRecord> runLog = const [];
  List<MissionPack> packs = const [];

  LifetimeStats lifetime = LifetimeStats.empty;
  StreakStatus streak = StreakStatus.empty;
  PeriodStats week = PeriodStats.empty;
  PeriodStats month = PeriodStats.empty;

  bool loading = true;

  Future<void> load() async {
    profile = await profiles.load();
    runLog = await runs.loadAll();
    packs = await missions.loadPacks();
    _recompute();
    loading = false;
    await narrator.init(profile);
    notifyListeners();
  }

  // -- campaign -------------------------------------------------------------

  /// All missions across all packs, with their locked/available/completed state.
  List<MissionProgress> get chain {
    final all = [for (final pack in packs) ...pack.missions];
    return resolveChain(all, profile.completedMissions, profile.missionAttempts);
  }

  MissionProgress? get currentMission {
    for (final m in chain) {
      if (m.state == MissionState.available) return m;
    }
    return null;
  }

  int get missionsCompleted => chain.where((m) => m.state == MissionState.completed).length;
  int get missionsTotal => chain.length;

  /// Every codex entry the runner has actually unlocked, newest pack last.
  List<CodexEntry> get unlockedCodex {
    final out = <CodexEntry>[];
    for (final pack in packs) {
      for (final mission in pack.missions) {
        for (final entry in mission.codex) {
          if (profile.unlockedCodex.contains(entry.id)) out.add(entry);
        }
      }
    }
    return out;
  }

  int get codexTotal =>
      packs.fold(0, (s, p) => s + p.missions.fold(0, (t, m) => t + m.codex.length));

  /// The goal to preselect on the brief screen: whatever the runner chose last
  /// time for this mission, otherwise the author's suggestion.
  RunGoal goalFor(Mission mission) {
    final stored = profile.lastGoalByMission[mission.id];
    if (stored == null) return mission.suggestedGoal;
    try {
      return RunGoal.fromJson(stored);
    } on Object {
      return mission.suggestedGoal;
    }
  }

  // -- mutations ------------------------------------------------------------

  Future<void> updateProfile(Profile next) async {
    profile = next;
    await profiles.save(next);
    await narrator.applyProfile(next);
    _recompute();
    notifyListeners();
  }

  Future<void> rememberGoal(Mission mission, RunGoal goal) async {
    await updateProfile(
      profile.copyWith(
        lastGoalByMission: {...profile.lastGoalByMission, mission.id: goal.toJson()},
      ),
    );
  }

  /// Files a finished run: stores it, advances the campaign, banks any codex
  /// entries heard along the way, and awards whatever that made true.
  Future<RunOutcomeReport> completeRun(
    RunRecord record, {
    Mission? mission,
    List<String> codexHeard = const [],
  }) async {
    if (record.countsForStats) {
      await runs.save(record);
      runLog = await runs.loadAll();
    }

    var next = profile;

    if (mission != null) {
      next = next.copyWith(
        missionAttempts: {...next.missionAttempts, mission.id: (next.missionAttempts[mission.id] ?? 0) + 1},
      );
      if (record.isSuccess) {
        next = next.copyWith(completedMissions: {...next.completedMissions, mission.id});
      }
    }
    if (codexHeard.isNotEmpty) {
      next = next.copyWith(unlockedCodex: {...next.unlockedCodex, ...codexHeard});
    }

    // Achievements are evaluated against the stats the new run produces, using
    // the streak goal the runner has set right now.
    final stats = StatsService.lifetime(runLog, next.streakGoal);
    final fresh = AchievementEngine.newlyEarned(stats, next.unlockedAchievements.keys.toSet());
    if (fresh.isNotEmpty) {
      final now = DateTime.now();
      next = next.copyWith(
        unlockedAchievements: {...next.unlockedAchievements, for (final a in fresh) a.id: now},
      );
    }

    profile = next;
    await profiles.save(next);
    _recompute();
    notifyListeners();

    // The mission that just became playable, if the campaign moved on.
    String? unlocked;
    if (mission != null && record.isSuccess) {
      final upcoming = currentMission;
      if (upcoming != null && upcoming.mission.order > mission.order) {
        unlocked = upcoming.mission.codename;
      }
    }

    return RunOutcomeReport(
      record: record,
      newAchievements: fresh.map((a) => a.title).toList(),
      missionUnlocked: unlocked,
    );
  }

  Future<void> deleteRun(String id) async {
    await runs.delete(id);
    runLog = await runs.loadAll();
    _recompute();
    notifyListeners();
  }

  /// Wipes progress but keeps settings — used by the reset action in Settings.
  Future<void> resetProgress() async {
    await runs.deleteAll();
    runLog = const [];
    profile = profile.copyWith(
      completedMissions: const {},
      unlockedAchievements: const {},
      unlockedCodex: const {},
      missionAttempts: const {},
    );
    await profiles.save(profile);
    _recompute();
    notifyListeners();
  }

  // -- backup ---------------------------------------------------------------

  /// The whole device state as a JSON document, ready to be written out.
  Future<String> exportBackup() => backups.exportToJson();

  /// Restores [archive] and rebuilds everything derived from it.
  ///
  /// The profile is re-applied to the narrator because a replace can bring in
  /// different speech and interrupt settings.
  Future<ImportReport> importBackup(BackupArchive archive, ImportMode mode) async {
    final report = await backups.import(archive, mode);
    profile = await profiles.load();
    runLog = await runs.loadAll();
    await narrator.applyProfile(profile);
    _recompute();
    notifyListeners();
    return report;
  }

  Future<void> reloadMissionPacks() async {
    missions.invalidate();
    packs = await missions.loadPacks();
    notifyListeners();
  }

  List<AchievementView> get achievementWall =>
      AchievementEngine.wall(lifetime, profile.unlockedAchievements);

  void _recompute() {
    lifetime = StatsService.lifetime(runLog, profile.streakGoal);
    streak = StatsService.streak(runLog, profile.streakGoal);
    week = StatsService.lastDays(runLog, 7, label: 'LAST 7 DAYS');
    month = StatsService.lastDays(runLog, 30, label: 'LAST 30 DAYS');
  }
}
