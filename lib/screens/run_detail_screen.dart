import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../models/run_record.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/panels.dart';
import '../widgets/route_trace.dart';

/// One stored run, with its GPS trace loaded on demand.
class RunDetailScreen extends StatefulWidget {
  const RunDetailScreen({super.key, required this.run});

  final RunRecord run;

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  List<TracePoint>? _trace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final points = await context.read<AppState>().runs.loadTrace(widget.run.id);
    if (mounted) setState(() => _trace = points);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: NeonPanel(
          accent: Cy.magenta,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DELETE RUN?', style: CyType.display(size: 16, color: Cy.magenta)),
              const SizedBox(height: 10),
              Text(
                'This removes it from your totals, your streak and the achievement wall. '
                'It cannot be undone.',
                style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CyberButton(
                      label: 'Keep',
                      style: CyberButtonStyle.ghost,
                      dense: true,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CyberButton(
                      label: 'Delete',
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
    if (confirmed != true || !mounted) return;
    await context.read<AppState>().deleteRun(widget.run.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final units = context.select<AppState, UnitSystem>((s) => s.profile.units);
    final accent = run.isSuccess ? Cy.green : Cy.magenta;

    return Scaffold(
      body: GridBackdrop(
        accent: accent,
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Cy.inkDim),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline, color: Cy.inkDim),
                    tooltip: 'Delete run',
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                  children: [
                    Text(Fmt.dateTime(run.startedAt), style: CyType.label(size: 10)),
                    const SizedBox(height: 8),
                    Text(
                      run.missionCodename ?? 'FREE RUN',
                      style: CyType.display(size: 26, color: Cy.ink, shadows: textGlow(accent, blur: 14)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CyberTag(
                          run.isSuccess ? 'SUCCESS' : 'FAILED',
                          color: accent,
                          filled: run.isSuccess,
                        ),
                        const SizedBox(width: 8),
                        CyberTag('TARGET ${run.goal}', color: Cy.ghost),
                      ],
                    ),
                    const SizedBox(height: 18),
                    NeonPanel(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Distance',
                                  value: Fmt.distance(run.distanceMeters, units),
                                  unit: Fmt.distanceUnit(units),
                                  accent: Cy.cyan,
                                ),
                              ),
                              Expanded(
                                child: StatTile(label: 'Time', value: Fmt.clock(run.elapsedSeconds)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Avg pace',
                                  value: Fmt.pace(run.paceSecondsPerKm, units),
                                  unit: Fmt.paceUnit(units),
                                  size: 20,
                                ),
                              ),
                              Expanded(
                                child: StatTile(
                                  label: 'Calories',
                                  value: Fmt.calories(run.calories),
                                  unit: 'kcal',
                                  accent: Cy.amber,
                                  size: 20,
                                ),
                              ),
                              Expanded(
                                child: StatTile(
                                  label: 'Evaded',
                                  value: run.chasesTotal == 0
                                      ? '—'
                                      : '${run.chasesEvaded}/${run.chasesTotal}',
                                  accent: Cy.magenta,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SectionHeader('ROUTE'),
                    if (_trace == null)
                      Container(
                        height: 200,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Cy.panel, border: Border.all(color: Cy.rule)),
                        child: Text('LOADING TRACE', style: CyType.label()),
                      )
                    else
                      RouteTrace(trace: _trace!, accent: accent, height: 240),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
