import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/app_version.dart';
import '../services/stats_service.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/clock.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/backup_controls.dart';
import '../widgets/pack_controls.dart';
import '../widgets/panels.dart';
import '../l10n/l10n.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;
    final l = L.of(context);

    void update(Profile next) => state.updateProfile(next);

    return Scaffold(
      body: GridBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: Cy.inkDim),
                  ),
                  Text(l.settingsTitle, style: CyType.display(size: 14, color: Cy.ink)),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  children: [
                    SectionHeader(l.sectionIdentity),
                    NeonPanel(
                      child: Column(
                        children: [
                          _TextRow(
                            label: l.settingCallsign,
                            value: profile.callsign,
                            hint: l.settingCallsignHint,
                            onChanged: (v) => update(
                              profile.copyWith(callsign: v.trim().isEmpty ? 'RUNNER' : v.trim()),
                            ),
                          ),
                          const _Rule(),
                          _StepperRow(
                            label: l.settingBodyMass,
                            // Calorie estimates are mass-dependent; this is the
                            // only input the ACSM equations need from the user.
                            value: Fmt.weight(profile.weightKg, profile.units),
                            onDecrease: () =>
                                update(profile.copyWith(weightKg: (profile.weightKg - 1).clamp(30, 200))),
                            onIncrease: () =>
                                update(profile.copyWith(weightKg: (profile.weightKg + 1).clamp(30, 200))),
                          ),
                          const _Rule(),
                          _PickerRow<String>(
                            label: l.settingLanguage,
                            value: profile.language,
                            options: {
                              '': l.languageSystem,
                              // Each in its own language, so a runner who
                              // cannot read the current one still finds theirs.
                              for (final locale in L.supportedLocales)
                                locale.languageCode: lookupL(locale).languageName,
                            },
                            onChanged: (code) => update(profile.copyWith(language: code)),
                          ),
                          const _Rule(),
                          _SegmentRow<UnitSystem>(
                            label: l.settingUnits,
                            value: profile.units,
                            options: {UnitSystem.metric: l.unitsKm, UnitSystem.imperial: l.unitsMiles},
                            onChanged: (v) => update(profile.copyWith(units: v)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    SectionHeader(l.sectionStreak, accent: Cy.amber),
                    NeonPanel(
                      child: Column(
                        children: [
                          _SegmentRow<StreakMetric>(
                            label: l.settingMeasuredIn,
                            value: profile.streakGoal.metric,
                            options: {
                              StreakMetric.minutes: l.metricTime,
                              StreakMetric.kilometres: l.metricDistance,
                              StreakMetric.missions: l.metricOps,
                            },
                            onChanged: (v) => update(
                              profile.withStreakGoal(
                                thisWeek: StatsService.weekStart(appNow()),
                                profile.streakGoal.copyWith(
                                  metric: v,
                                  // Each metric needs its own sensible default;
                                  // 30 kilometres a week is not 30 minutes.
                                  target: switch (v) {
                                    StreakMetric.minutes => 30,
                                    StreakMetric.kilometres => 5,
                                    StreakMetric.missions => 1,
                                  },
                                ),
                              ),
                            ),
                          ),
                          const _Rule(),
                          _StepperRow(
                            label: l.settingWeeklyTarget,
                            value: profile.streakGoal.label,
                            onDecrease: () => update(
                              profile.withStreakGoal(
                                thisWeek: StatsService.weekStart(appNow()),
                                profile.streakGoal.copyWith(
                                  target: (profile.streakGoal.target - _streakStep(profile.streakGoal.metric))
                                      .clamp(_streakStep(profile.streakGoal.metric), 2000),
                                ),
                              ),
                            ),
                            onIncrease: () => update(
                              profile.withStreakGoal(
                                thisWeek: StatsService.weekStart(appNow()),
                                profile.streakGoal.copyWith(
                                  target: (profile.streakGoal.target + _streakStep(profile.streakGoal.metric))
                                      .clamp(_streakStep(profile.streakGoal.metric), 2000),
                                ),
                              ),
                            ),
                          ),
                          const _Rule(),
                          _Note(l.streakNote),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    SectionHeader(l.sectionAudio, accent: Cy.cyan),
                    NeonPanel(
                      child: Column(
                        children: [
                          _SwitchRow(
                            label: l.settingStoryVoice,
                            subtitle: l.settingStoryVoiceHint,
                            value: profile.voiceEnabled,
                            onChanged: (v) => update(profile.copyWith(voiceEnabled: v)),
                          ),
                          const _Rule(),
                          _SegmentRow<AudioInterrupt>(
                            label: l.settingYourMusic,
                            value: profile.audioInterrupt,
                            options: {
                              AudioInterrupt.pause: l.musicPause,
                              AudioInterrupt.duck: l.musicDuck,
                            },
                            onChanged: (v) => update(profile.copyWith(audioInterrupt: v)),
                          ),
                          const _Rule(),
                          _Note(
                            profile.audioInterrupt == AudioInterrupt.pause
                                ? l.musicPauseNote
                                : l.musicDuckNote,
                          ),
                          if (profile.audioInterrupt == AudioInterrupt.pause) ...[
                            const _Rule(),
                            _SwitchRow(
                              label: l.settingForceMusic,
                              subtitle: l.settingForceMusicHint,
                              value: profile.resumeMusic,
                              onChanged: (v) => update(profile.copyWith(resumeMusic: v)),
                            ),
                          ],
                          const _Rule(),
                          _SliderRow(
                            label: l.settingSpeechRate,
                            value: profile.speechRate,
                            min: 0.25,
                            max: 0.9,
                            display: '${(profile.speechRate * 100).round()}%',
                            onChanged: (v) => update(profile.copyWith(speechRate: v)),
                          ),
                          const _Rule(),
                          _SliderRow(
                            label: l.settingEffectsVolume,
                            value: profile.sfxVolume,
                            min: 0,
                            max: 1,
                            display: '${(profile.sfxVolume * 100).round()}%',
                            onChanged: (v) => update(profile.copyWith(sfxVolume: v)),
                          ),
                          const _Rule(),
                          _SwitchRow(
                            label: l.settingAmbientBed,
                            subtitle: l.settingAmbientBedHint,
                            value: profile.ambientBed,
                            onChanged: (v) => update(profile.copyWith(ambientBed: v)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    SectionHeader(l.sectionRun, accent: Cy.magenta),
                    NeonPanel(
                      child: Column(
                        children: [
                          _SwitchRow(
                            label: l.infoPursuits,
                            subtitle: l.settingPursuitsHint,
                            value: profile.chasesEnabled,
                            onChanged: (v) => update(profile.copyWith(chasesEnabled: v)),
                          ),
                          const _Rule(),
                          _SwitchRow(
                            label: l.settingAutoPause,
                            subtitle: l.settingAutoPauseHint,
                            value: profile.autoPause,
                            onChanged: (v) => update(profile.copyWith(autoPause: v)),
                          ),
                          const _Rule(),
                          _SwitchRow(
                            label: l.settingKeepScreenOn,
                            subtitle: l.settingKeepScreenOnHint,
                            value: profile.keepScreenOn,
                            onChanged: (v) => update(profile.copyWith(keepScreenOn: v)),
                          ),
                          const _Rule(),
                          _SwitchRow(
                            label: profile.isMetric ? l.settingSplitsKm : l.settingSplitsMile,
                            subtitle: profile.isMetric ? l.settingSplitsKmHint : l.settingSplitsMileHint,
                            value: profile.splitsEnabled,
                            onChanged: (v) => update(profile.copyWith(splitsEnabled: v)),
                          ),
                          // Only where there is a counter to use: offering a
                          // switch that can do nothing would cost the runner a
                          // permission prompt for it.
                          if (state.stepCounterAvailable) ...[
                            const _Rule(),
                            _SwitchRow(
                              label: l.settingCountSteps,
                              subtitle: l.settingCountStepsHint,
                              value: profile.countSteps,
                              onChanged: (v) async {
                                final messenger = ScaffoldMessenger.of(context);
                                if (v && !await state.setCountSteps(true)) {
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(l10n.countStepsDenied, style: CyType.body(size: 14, color: Cy.ink))),
                                  );
                                } else if (!v) {
                                  await state.setCountSteps(false);
                                }
                              },
                            ),
                          ],
                          const _Rule(),
                          _SwitchRow(
                            label: l.settingSeasonalEvents,
                            subtitle: l.settingSeasonalEventsHint,
                            value: profile.seasonalEvents,
                            onChanged: (v) => update(profile.copyWith(seasonalEvents: v)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    SectionHeader(l.sectionSignals, accent: Cy.green),
                    NeonPanel(
                      child: Column(
                        children: [
                          _SwitchRow(
                            label: l.settingReminders,
                            subtitle: l.settingRemindersHint,
                            value: profile.signals.remindersEnabled,
                            onChanged: (v) => update(
                              profile.copyWith(signals: profile.signals.copyWith(remindersEnabled: v)),
                            ),
                          ),
                          if (profile.signals.remindersEnabled) ...[
                            const _Rule(),
                            _WeekdayRow(
                              label: l.settingDays,
                              selected: profile.signals.weekdays,
                              onChanged: (days) => update(
                                profile.copyWith(signals: profile.signals.copyWith(weekdays: days)),
                              ),
                            ),
                            const _Rule(),
                            _TimeRow(
                              label: l.settingTime,
                              minutesFromMidnight: profile.signals.minutesFromMidnight,
                              onChanged: (m) => update(
                                profile.copyWith(signals: profile.signals.copyWith(minutesFromMidnight: m)),
                              ),
                            ),
                          ],
                          const _Rule(),
                          _StepperRow(
                            label: l.settingSignalNoise,
                            value: profile.signals.ambientPerWeek == 0
                                ? l.off
                                : l.perWeek(profile.signals.ambientPerWeek),
                            onDecrease: () => update(
                              profile.copyWith(
                                signals: profile.signals.copyWith(
                                  ambientPerWeek: (profile.signals.ambientPerWeek - 1).clamp(0, 14),
                                ),
                              ),
                            ),
                            onIncrease: () => update(
                              profile.copyWith(
                                signals: profile.signals.copyWith(
                                  ambientPerWeek: (profile.signals.ambientPerWeek + 1).clamp(0, 14),
                                ),
                              ),
                            ),
                          ),
                          const _Rule(),
                          _SwitchRow(
                            label: l.settingWeeklyDebrief,
                            subtitle: l.settingWeeklyDebriefHint,
                            value: profile.signals.debriefEnabled,
                            onChanged: (v) => update(
                              profile.copyWith(signals: profile.signals.copyWith(debriefEnabled: v)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Note(l.signalsNote),
                    const SizedBox(height: 20),

                    SectionHeader(l.sectionMissionPacks),
                    const NeonPanel(child: PackControls()),
                    const SizedBox(height: 20),

                    SectionHeader(l.sectionData, accent: Cy.red),
                    NeonPanel(
                      accent: Cy.rule,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Note(l.dataNote),
                          const _Rule(),
                          const BackupControls(),
                          const _Rule(),
                          CyberButton(
                            label: l.resetProgress,
                            icon: Icons.delete_forever_outlined,
                            style: CyberButtonStyle.danger,
                            dense: true,
                            onPressed: () => _confirmReset(context, state),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _Colophon(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _streakStep(StreakMetric metric) => switch (metric) {
    StreakMetric.minutes => 5,
    StreakMetric.kilometres => 1,
    StreakMetric.missions => 1,
  };

  Future<void> _confirmReset(BuildContext context, AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: NeonPanel(
          accent: Cy.red,
          lit: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L.of(context).wipeTitle, style: CyType.display(size: 16, color: Cy.red)),
              const SizedBox(height: 10),
              Text(
                L.of(context).wipeBody,
                style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CyberButton(
                      label: L.of(context).cancel,
                      style: CyberButtonStyle.ghost,
                      dense: true,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CyberButton(
                      label: L.of(context).wipe,
                      style: CyberButtonStyle.danger,
                      dense: true,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) await state.resetProgress();
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(height: 1, color: Cy.rule));
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CyType.body(size: 13, color: Cy.ghost, height: 1.4));
}

/// Seven toggles, Monday first. The app has no picker of any kind, so this
/// borrows the chip look the achievement wall already uses rather than
/// introducing Material's own.
class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow({required this.label, required this.selected, required this.onChanged});

  final String label;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CyType.body(size: 15, weight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var day = DateTime.monday; day <= DateTime.sunday; day++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: day == DateTime.sunday ? 0 : 6),
                  child: _DayChip(
                    // Monday is 1 and the table is 0-indexed.
                    letter: Fmt.weekdayInitial(DateTime(2026, 1, 5 + day - 1)),
                    selected: selected.contains(day),
                    onTap: () {
                      final next = Set<int>.from(selected);
                      // Never leave every day off: that is "reminders off",
                      // which is the switch above, not a schedule.
                      if (!next.remove(day)) next.add(day);
                      if (next.isNotEmpty) onChanged(next);
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.letter, required this.selected, required this.onTap});

  final String letter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Cy.cyan : Cy.panel,
          border: Border.all(color: selected ? Cy.cyan : Cy.rule),
        ),
        child: Text(
          letter,
          style: CyType.mono(size: 11, color: selected ? Cy.v0id : Cy.inkDim, letterSpacing: 1),
        ),
      ),
    );
  }
}

/// Hours and minutes on ± buttons, in quarter-hours.
///
/// `showTimePicker` would be the only Material sheet in the product, so this
/// reuses the stepper vocabulary the rest of the screen already speaks.
class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.minutesFromMidnight, required this.onChanged});

  final String label;
  final int minutesFromMidnight;
  final ValueChanged<int> onChanged;

  static const int _step = 15;

  /// Wraps around midnight rather than clamping, so 00:00 is reachable from
  /// either direction.
  int _shifted(int by) => (minutesFromMidnight + by + 24 * 60) % (24 * 60);

  @override
  Widget build(BuildContext context) {
    final hour = minutesFromMidnight ~/ 60;
    final minute = minutesFromMidnight % 60;
    return Row(
      children: [
        Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
        _SmallButton(icon: Icons.remove, onTap: () => onChanged(_shifted(-_step))),
        SizedBox(
          width: 104,
          child: Center(
            child: Text(
              '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
              style: CyType.readout(15, Cy.cyan),
            ),
          ),
        ),
        _SmallButton(icon: Icons.add, onTap: () => onChanged(_shifted(_step))),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: CyType.body(size: 15, weight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: CyType.body(size: 12, color: Cy.ghost, height: 1.3)),
              ],
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
        for (final entry in options.entries)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              onTap: () => onChanged(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: entry.key == value ? Cy.cyan : Colors.transparent,
                  border: Border.all(color: entry.key == value ? Cy.cyan : Cy.rule),
                ),
                child: Text(
                  entry.value,
                  style: CyType.mono(size: 10, color: entry.key == value ? Cy.v0id : Cy.inkDim),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A choice among more options than fit as segments: the current one, and a
/// dialog listing them all.
class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
            Flexible(
              child: Text(
                options[value] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CyType.mono(size: 12, color: Cy.cyan),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.unfold_more, size: 16, color: Cy.inkDim),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: NeonPanel(
          accent: Cy.cyan,
          lit: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: CyType.display(size: 14, color: Cy.cyan)),
              const SizedBox(height: 10),
              for (final entry in options.entries)
                InkWell(
                  onTap: () => Navigator.of(context).pop(entry.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.value,
                            style: CyType.body(size: 16, color: entry.key == value ? Cy.cyan : Cy.ink),
                          ),
                        ),
                        if (entry.key == value) Icon(Icons.check, size: 18, color: Cy.cyan),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
        _SmallButton(icon: Icons.remove, onTap: onDecrease),
        SizedBox(
          width: 104,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: CyType.readout(15, Cy.cyan)),
            ),
          ),
        ),
        _SmallButton(icon: Icons.add, onTap: onIncrease),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: Cy.rule), color: Cy.panelHi),
        child: Icon(icon, size: 16, color: Cy.cyan),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
            Text(display, style: CyType.mono(size: 12, color: Cy.cyan)),
          ],
        ),
        Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}

class _TextRow extends StatefulWidget {
  const _TextRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;
  final ValueChanged<String> onChanged;

  @override
  State<_TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<_TextRow> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: CyType.body(size: 15, weight: FontWeight.w600)),
        if (widget.hint != null) ...[
          const SizedBox(height: 2),
          Text(widget.hint!, style: CyType.body(size: 12, color: Cy.ghost)),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          maxLength: 16,
          style: CyType.mono(size: 15, color: Cy.cyan),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            filled: true,
            fillColor: Cy.panelHi,
            border: OutlineInputBorder(borderSide: BorderSide(color: Cy.rule), borderRadius: BorderRadius.zero),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Cy.rule),
              borderRadius: BorderRadius.zero,
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Cy.cyan),
              borderRadius: BorderRadius.zero,
            ),
          ),
          onSubmitted: widget.onChanged,
          onTapOutside: (_) {
            FocusManager.instance.primaryFocus?.unfocus();
            if (_controller.text != widget.value) widget.onChanged(_controller.text);
          },
        ),
      ],
    );
  }
}

/// Name, version and provenance, at the very bottom where it belongs.
class _Colophon extends StatelessWidget {
  const _Colophon();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersion?>(
      future: AppVersion.load(),
      builder: (context, snapshot) {
        final version = snapshot.data;
        return Column(
          children: [
            Text('SPRAWL//RUN', style: CyType.display(size: 11, color: Cy.inkDim, letterSpacing: 3)),
            const SizedBox(height: 6),
            Text(
              version == null ? L.of(context).offlineBuild : L.of(context).versionOffline(version.label).toUpperCase(),
              style: CyType.mono(size: 10, color: Cy.ghost, letterSpacing: 1.6),
            ),
            const SizedBox(height: 4),
            Text(
              L.of(context).colophonLicense,
              style: CyType.body(size: 11, color: Cy.ghost, weight: FontWeight.w500),
            ),
          ],
        );
      },
    );
  }
}
