import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/backup_controls.dart';
import '../widgets/panels.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;

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
                    icon: const Icon(Icons.arrow_back, color: Cy.inkDim),
                  ),
                  Text('SETTINGS', style: CyType.display(size: 14, color: Cy.ink)),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  children: [
                    const SectionHeader('IDENTITY'),
                    NeonPanel(
                      child: Column(
                        children: [
                          _TextRow(
                            label: 'Callsign',
                            value: profile.callsign,
                            hint: 'How your handlers address you',
                            onChanged: (v) => update(
                              profile.copyWith(callsign: v.trim().isEmpty ? 'RUNNER' : v.trim()),
                            ),
                          ),
                          const _Rule(),
                          _StepperRow(
                            label: 'Body mass',
                            // Calorie estimates are mass-dependent; this is the
                            // only input the ACSM equations need from the user.
                            value: Fmt.weight(profile.weightKg, profile.units),
                            onDecrease: () =>
                                update(profile.copyWith(weightKg: (profile.weightKg - 1).clamp(30, 200))),
                            onIncrease: () =>
                                update(profile.copyWith(weightKg: (profile.weightKg + 1).clamp(30, 200))),
                          ),
                          const _Rule(),
                          _SegmentRow<UnitSystem>(
                            label: 'Units',
                            value: profile.units,
                            options: const {UnitSystem.metric: 'KM', UnitSystem.imperial: 'MILES'},
                            onChanged: (v) => update(profile.copyWith(units: v)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    const SectionHeader('STREAK', accent: Cy.amber),
                    NeonPanel(
                      child: Column(
                        children: [
                          _SegmentRow<StreakMetric>(
                            label: 'Measured in',
                            value: profile.streakGoal.metric,
                            options: const {
                              StreakMetric.minutes: 'TIME',
                              StreakMetric.kilometres: 'DIST',
                              StreakMetric.missions: 'OPS',
                            },
                            onChanged: (v) => update(
                              profile.copyWith(
                                streakGoal: profile.streakGoal.copyWith(
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
                            label: 'Weekly target',
                            value: profile.streakGoal.label,
                            onDecrease: () => update(
                              profile.copyWith(
                                streakGoal: profile.streakGoal.copyWith(
                                  target: (profile.streakGoal.target - _streakStep(profile.streakGoal.metric))
                                      .clamp(_streakStep(profile.streakGoal.metric), 2000),
                                ),
                              ),
                            ),
                            onIncrease: () => update(
                              profile.copyWith(
                                streakGoal: profile.streakGoal.copyWith(
                                  target: (profile.streakGoal.target + _streakStep(profile.streakGoal.metric))
                                      .clamp(_streakStep(profile.streakGoal.metric), 2000),
                                ),
                              ),
                            ),
                          ),
                          const _Rule(),
                          _Note(
                            'Your streak extends every week you hit this target. '
                            'A week in progress never breaks it — only a finished week that fell short does.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    const SectionHeader('AUDIO', accent: Cy.cyan),
                    NeonPanel(
                      child: Column(
                        children: [
                          _SwitchRow(
                            label: 'Story voice',
                            subtitle: 'Speak transmissions aloud using the device voice',
                            value: profile.voiceEnabled,
                            onChanged: (v) => update(profile.copyWith(voiceEnabled: v)),
                          ),
                          const _Rule(),
                          _SegmentRow<AudioInterrupt>(
                            label: 'Your music',
                            value: profile.audioInterrupt,
                            options: const {
                              AudioInterrupt.pause: 'PAUSE',
                              AudioInterrupt.duck: 'DUCK',
                            },
                            onChanged: (v) => update(profile.copyWith(audioInterrupt: v)),
                          ),
                          const _Rule(),
                          _Note(
                            profile.audioInterrupt == AudioInterrupt.pause
                                ? 'Whatever you are playing pauses for each transmission and resumes afterwards.'
                                : 'Whatever you are playing drops to a low volume under each transmission.',
                          ),
                          if (profile.audioInterrupt == AudioInterrupt.pause) ...[
                            const _Rule(),
                            _SwitchRow(
                              label: 'Force music back on',
                              subtitle: 'Some players stay silent after a long transmission. '
                                  'Presses play for you when that happens.',
                              value: profile.resumeMusic,
                              onChanged: (v) => update(profile.copyWith(resumeMusic: v)),
                            ),
                          ],
                          const _Rule(),
                          _SliderRow(
                            label: 'Speech rate',
                            value: profile.speechRate,
                            min: 0.25,
                            max: 0.9,
                            display: '${(profile.speechRate * 100).round()}%',
                            onChanged: (v) => update(profile.copyWith(speechRate: v)),
                          ),
                          const _Rule(),
                          _SliderRow(
                            label: 'Effects volume',
                            value: profile.sfxVolume,
                            min: 0,
                            max: 1,
                            display: '${(profile.sfxVolume * 100).round()}%',
                            onChanged: (v) => update(profile.copyWith(sfxVolume: v)),
                          ),
                          const _Rule(),
                          _SwitchRow(
                            label: 'Ambient bed',
                            subtitle: 'Low synth drone under the run, for when you bring no music',
                            value: profile.ambientBed,
                            onChanged: (v) => update(profile.copyWith(ambientBed: v)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    const SectionHeader('RUN', accent: Cy.magenta),
                    NeonPanel(
                      child: Column(
                        children: [
                          _SwitchRow(
                            label: 'Pursuits',
                            subtitle: 'Timed chases that ask for a hard effort, scaled to your own pace',
                            value: profile.chasesEnabled,
                            onChanged: (v) => update(profile.copyWith(chasesEnabled: v)),
                          ),
                          const _Rule(),
                          _SwitchRow(
                            label: 'Auto-pause',
                            subtitle: 'Stop the clock when you stop moving',
                            value: profile.autoPause,
                            onChanged: (v) => update(profile.copyWith(autoPause: v)),
                          ),
                          const _Rule(),
                          _SwitchRow(
                            label: 'Keep screen on',
                            subtitle: 'Leave the HUD lit for the whole run',
                            value: profile.keepScreenOn,
                            onChanged: (v) => update(profile.copyWith(keepScreenOn: v)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    const SectionHeader('MISSION PACKS'),
                    NeonPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final pack in state.packs) ...[
                            Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 15, color: Cy.cyanDim),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(pack.title, style: CyType.body(size: 15, weight: FontWeight.w700)),
                                      Text(pack.tagline, style: CyType.body(size: 13, color: Cy.ghost)),
                                    ],
                                  ),
                                ),
                                CyberTag('${pack.missions.length} OPS', color: Cy.ghost),
                              ],
                            ),
                            const _Rule(),
                          ],
                          for (final error in state.missions.loadErrors) ...[
                            Text(error, style: CyType.mono(size: 11, color: Cy.red)),
                            const SizedBox(height: 6),
                          ],
                          _Note(
                            'Drop additional packs as .json into the app documents folder under '
                            'sprawlrun/mission_packs/ and reload. See docs/MISSION_PACKS.md for the format.',
                          ),
                          const SizedBox(height: 12),
                          CyberButton(
                            label: 'Reload packs',
                            icon: Icons.refresh,
                            style: CyberButtonStyle.ghost,
                            dense: true,
                            onPressed: state.reloadMissionPacks,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    const SectionHeader('DATA', accent: Cy.red),
                    NeonPanel(
                      accent: Cy.rule,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Note(
                            'Everything lives on this device. Nothing is uploaded, and the app never '
                            'needs a network connection.',
                          ),
                          const _Rule(),
                          const BackupControls(),
                          const _Rule(),
                          CyberButton(
                            label: 'Reset all progress',
                            icon: Icons.delete_forever_outlined,
                            style: CyberButtonStyle.danger,
                            dense: true,
                            onPressed: () => _confirmReset(context, state),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'SPRAWL//RUN — OFFLINE BUILD',
                        style: CyType.label(size: 9, color: Cy.ghost),
                      ),
                    ),
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
              Text('WIPE PROGRESS?', style: CyType.display(size: 16, color: Cy.red)),
              const SizedBox(height: 10),
              Text(
                'Deletes every run, every achievement, the codex and all campaign progress. '
                'Your settings are kept. This cannot be undone.',
                style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CyberButton(
                      label: 'Cancel',
                      style: CyberButtonStyle.ghost,
                      dense: true,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CyberButton(
                      label: 'Wipe',
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
            border: const OutlineInputBorder(borderSide: BorderSide(color: Cy.rule), borderRadius: BorderRadius.zero),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Cy.rule),
              borderRadius: BorderRadius.zero,
            ),
            focusedBorder: const OutlineInputBorder(
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
