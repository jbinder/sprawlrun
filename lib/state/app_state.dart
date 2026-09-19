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
import '../models/run_outcome.dart';
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

  /// The pack the ops screen is showing. Falls back to the first loaded pack
  /// when nothing is selected or the selected one has been removed, so the
  /// screen never points at nothing while packs exist.
  MissionPack? get activePack {
    if (packs.isEmpty) return null;
    for (final pack in packs) {
      if (pack.id == profile.activePackId) return pack;
    }
    return packs.first;
  }

  /// The active pack's missions with their locked/available/completed state.
  /// Each pack is its own chain: finishing one never gates another.
  List<MissionProgress> get chain => chainFor(activePack);

  List<MissionProgress> chainFor(MissionPack? pack) =>
      pack == null ? const [] : resolveChain(pack.missions, profile.completedMissions, profile.missionAttempts);

  /// The one playable mission in the active pack, or null once it is cleared.
  MissionProgress? get currentMission {
    for (final m in chain) {
      if (m.state == MissionState.available) return m;
    }
    return null;
  }

  int get missionsCompleted => chain.where((m) => m.state == MissionState.completed).length;
  int get missionsTotal => chain.length;

  /// Every loaded pack with how far the runner is through it.
  List<PackProgress> get packProgress => [
    for (final pack in packs)
      PackProgress(pack: pack, chain: chainFor(pack), selected: pack.id == activePack?.id),
  ];

  /// The next pack worth switching to once the active one is cleared: the
  /// first after it in load order that still has missions open, wrapping
  /// round, or null if everything is done.
  MissionPack? get nextOpenPack {
    final active = activePack;
    if (active == null) return null;
    final start = packs.indexWhere((p) => p.id == active.id);
    for (var i = 1; i < packs.length; i++) {
      final pack = packs[(start + i) % packs.length];
      if (!PackProgress(pack: pack, chain: chainFor(pack), selected: false).isDone) return pack;
    }
    return null;
  }

  Future<void> selectPack(String id) async {
    if (!packs.any((p) => p.id == id) || profile.activePackId == id) return;
    profile = profile.copyWith(activePackId: id);
    await profiles.save(profile);
    notifyListeners();
  }

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

  /// Looks a mission up across every loaded pack — for reading an old run's
  /// story back, where the mission may since have moved or gone.
  Mission? missionById(String id) {
    for (final pack in packs) {
      for (final mission in pack.missions) {
        if (mission.id == id) return mission;
      }
    }
    return null;
  }

  /// Looks a codex entry up across every loaded pack.
  CodexEntry? codexEntry(String id) {
    for (final pack in packs) {
      for (final mission in pack.missions) {
        for (final entry in mission.codex) {
          if (entry.id == id) return entry;
        }
      }
    }
    return null;
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
    // Intel is banked only by a successful operation. Only what was not
    // already known counts either way — a replayed mission hears the same
    // lines again.
    final fresh = [
      for (final id in codexHeard)
        if (!next.unlockedCodex.contains(id)) id,
    ];
    final recovered = record.isSuccess ? fresh : const <String>[];
    final lost = record.isSuccess ? const <String>[] : fresh;
    if (recovered.isNotEmpty) {
      next = next.copyWith(unlockedCodex: {...next.unlockedCodex, ...recovered});
    }

    // Achievements are evaluated against the stats the new run produces, using
    // the streak goal the runner has set right now.
    final stats = StatsService.lifetime(runLog, next.streakGoal);
    final earned = AchievementEngine.newlyEarned(stats, next.unlockedAchievements.keys.toSet());
    if (earned.isNotEmpty) {
      final now = DateTime.now();
      next = next.copyWith(
        unlockedAchievements: {...next.unlockedAchievements, for (final a in earned) a.id: now},
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
      newAchievements: earned,
      codexRecovered: [for (final id in recovered) ?codexEntry(id)],
      codexLost: [for (final id in lost) ?codexEntry(id)],
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
  }
}
