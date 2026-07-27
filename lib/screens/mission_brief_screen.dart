import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/goal.dart';
import '../models/mission.dart';
import '../models/profile.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/glitch_text.dart';
import '../widgets/panels.dart';
import 'run_screen.dart';

/// Pre-run screen: the story setup, then the only decision the runner has to
/// make — how far or how long.
class MissionBriefScreen extends StatefulWidget {
  const MissionBriefScreen({super.key, required this.mission});

  /// Null for a free run: same tracking, no story.
  final Mission? mission;

  @override
  State<MissionBriefScreen> createState() => _MissionBriefScreenState();
}

class _MissionBriefScreenState extends State<MissionBriefScreen> {
  late RunGoal _goal;

  @override
  void initState() {
    super.initState();
    final mission = widget.mission;
    _goal = mission == null
        ? RunGoal.defaultGoal
        : context.read<AppState>().goalFor(mission);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final mission = widget.mission;
    final accent = mission == null ? Cy.cyan : Cy.magenta;

    return Scaffold(
      body: GridBackdrop(
        accent: accent,
        child: SafeArea(
          child: Column(
            children: [
              _BriefBar(mission: mission),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  children: [
                    if (mission != null) ...[
                      Text(mission.location.toUpperCase(), style: CyType.label(size: 10, color: accent)),
                      const SizedBox(height: 8),
                      GlitchText(
                        mission.codename,
                        style: CyType.display(size: 30, color: Cy.ink, shadows: textGlow(accent, blur: 18)),
                      ),
                      const SizedBox(height: 6),
                      Text(mission.title, style: CyType.body(size: 17, color: Cy.inkDim)),
                      const SizedBox(height: 20),
                      NeonPanel(
                        accent: Cy.rule,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BRIEFING', style: CyType.label(size: 10, color: accent)),
                            const SizedBox(height: 10),
                            TypewriterText(
                              mission.brief,
                              style: CyType.body(size: 16, height: 1.5, color: Cy.ink),
                            ),
                            const SizedBox(height: 16),
                            Container(height: 1, color: Cy.rule),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.flag_outlined, size: 15, color: accent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    mission.objective,
                                    style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoCell(
                              label: 'Transmissions',
                              value: '${mission.beats.length}',
                              icon: Icons.record_voice_over_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InfoCell(
                              label: 'Pursuits',
                              value: '${mission.chaseBeats.length}',
                              icon: Icons.radar,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InfoCell(
                              label: 'Suggested',
                              value: mission.suggestedGoal.toString(),
                              icon: Icons.tune,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      GlitchText(
                        'FREE RUN',
                        style: CyType.display(size: 30, color: Cy.ink, shadows: textGlow(accent, blur: 18)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No story, no handler, no one chasing you. Distance and time still count '
                        'toward your streak, your totals and the wall.',
                        style: CyType.body(size: 16, color: Cy.inkDim, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                    ],

                    const SectionHeader('SET YOUR TARGET'),
                    _GoalPicker(
                      goal: _goal,
                      units: state.profile.units,
                      onChanged: (g) => setState(() => _goal = g),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      mission == null
                          ? 'Reach the target and the run is logged as a success.'
                          : 'Reach the target and the operation is a success. Stop short and it counts as a failure — '
                                'you can retry it as many times as you like. You can always keep running past the target.',
                      style: CyType.body(size: 14, color: Cy.ghost, height: 1.35),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                child: CyberButton(
                  label: mission == null ? 'Start run' : 'Begin operation',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () async {
                    if (mission != null) {
                      await context.read<AppState>().rememberGoal(mission, _goal);
                    }
                    if (!context.mounted) return;
                    await Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => RunScreen(mission: mission, goal: _goal),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BriefBar extends StatelessWidget {
  const _BriefBar({required this.mission});

  final Mission? mission;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Cy.inkDim),
          ),
          const Spacer(),
          Text(
            mission == null ? 'UNLOGGED RUN' : 'OPERATION ${mission!.order.toString().padLeft(2, '0')}',
            style: CyType.label(size: 10),
          ),
        ],
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      cut: 8,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Cy.inkDim),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: CyType.readout(16, Cy.ink)),
          ),
          const SizedBox(height: 3),
          Text(label.toUpperCase(), style: CyType.label(size: 8)),
        ],
      ),
    );
  }
}

/// Time-or-distance toggle plus presets and a fine adjustment.
///
/// Presets cover what people actually run; the stepper exists so nobody is
/// stuck with a target that is close-but-not-what-they-wanted.
class _GoalPicker extends StatelessWidget {
  const _GoalPicker({required this.goal, required this.units, required this.onChanged});

  final RunGoal goal;
  final UnitSystem units;
  final ValueChanged<RunGoal> onChanged;

  static const List<double> _timePresets = [600, 900, 1200, 1500, 1800, 2400, 3000, 3600, 5400];
  static const List<double> _metricDistance = [1000, 2000, 3000, 5000, 7500, 10000, 15000, 21100, 30000];
  static const List<double> _imperialDistance = [1609, 3219, 4828, 8047, 10000, 16093, 21100, 32187, 42195];

  List<double> get _distancePresets => units == UnitSystem.imperial ? _imperialDistance : _metricDistance;

  String _label(double value) =>
      goal.isTime ? '${(value / 60).round()} min' : Fmt.distanceWithUnit(value, units);

  /// One tap of the stepper: a minute, or a quarter of the display unit.
  double get _step => goal.isTime ? 60 : (units == UnitSystem.imperial ? 402.336 : 250);

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ModeButton(
                  label: 'TIME',
                  icon: Icons.timer_outlined,
                  selected: goal.isTime,
                  onTap: () => onChanged(const RunGoal(GoalType.time, 1500)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeButton(
                  label: 'DISTANCE',
                  icon: Icons.route_outlined,
                  selected: goal.isDistance,
                  onTap: () => onChanged(
                    RunGoal(GoalType.distance, units == UnitSystem.imperial ? 4828 : 5000),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(
                  icon: Icons.remove,
                  onTap: () => onChanged(goal.copyWith(value: (goal.value - _step).clamp(_step, 200000))),
                ),
                const SizedBox(width: 18),
                SizedBox(
                  width: 150,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_label(goal.value), style: CyType.readout(30, Cy.cyan)),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                _StepButton(
                  icon: Icons.add,
                  onTap: () => onChanged(goal.copyWith(value: (goal.value + _step).clamp(_step, 200000))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in goal.isTime ? _timePresets : _distancePresets)
                _PresetChip(
                  label: _label(preset),
                  selected: (goal.value - preset).abs() < 1,
                  onTap: () => onChanged(goal.copyWith(value: preset)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Cy.cyan : Cy.ghost;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Cy.cyan.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Text(label, style: CyType.display(size: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: Cy.rule), color: Cy.panelHi),
        child: Icon(icon, size: 20, color: Cy.cyan),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Cy.cyan : Cy.panelHi,
          border: Border.all(color: selected ? Cy.cyan : Cy.rule),
        ),
        child: Text(
          label,
          style: CyType.mono(size: 11, color: selected ? Cy.v0id : Cy.inkDim),
        ),
      ),
    );
  }
}
