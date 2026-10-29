import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/gpx_export.dart';
import '../models/profile.dart';
import '../models/run_record.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/panels.dart';
import '../widgets/step_figures.dart';
import '../widgets/route_trace.dart';
import '../widgets/story_log.dart';
import '../l10n/l10n.dart';

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

  /// Hands the run's trace to the system share sheet as GPX, which is how it
  /// reaches a map app like OsmAnd. The file goes to the cache directory: the
  /// copy that matters is whatever the runner saves out of the sheet.
  Future<void> _shareGpx() async {
    final trace = _trace;
    if (trace == null || trace.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${GpxExport.fileName(widget.run)}');
      await file.writeAsString(GpxExport.of(widget.run, trace));
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/gpx+xml')],
          subject: widget.run.missionCodename ?? L.of(context).gpxShareSubject,
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.of(context).exportFailed('$e'), style: CyType.body(size: 14, color: Cy.red))),
      );
    }
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
              Text(L.of(context).deleteRunTitle, style: CyType.display(size: 16, color: Cy.magenta)),
              const SizedBox(height: 10),
              Text(
                L.of(context).deleteRunBody,
                style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CyberButton(
                      label: L.of(context).keep,
                      style: CyberButtonStyle.ghost,
                      dense: true,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CyberButton(
                      label: L.of(context).delete,
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
                    icon: Icon(Icons.arrow_back, color: Cy.inkDim),
                  ),
                  const Spacer(),
                  IconButton(
                    // Disabled until the trace is in memory, and hidden
                    // entirely for a run that never recorded one.
                    onPressed: _trace == null || _trace!.isEmpty ? null : _shareGpx,
                    icon: const Icon(Icons.ios_share, size: 20),
                    color: Cy.inkDim,
                    disabledColor: Cy.ghost.withValues(alpha: 0.4),
                    tooltip: L.of(context).exportGpx,
                  ),
                  IconButton(
                    onPressed: _delete,
                    icon: Icon(Icons.delete_outline, color: Cy.inkDim),
                    tooltip: L.of(context).deleteRun,
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
                      run.missionCodename ?? L.of(context).freeRun,
                      style: CyType.display(size: 26, color: Cy.ink, shadows: textGlow(accent, blur: 14)),
                    ),
                    const SizedBox(height: 8),
                    // Wrapped, not a Row: a long goal plus three tags does not
                    // fit a narrow phone on one line.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        CyberTag(
                          run.isSuccess ? L.of(context).tagSuccess : L.of(context).tagFailed,
                          color: accent,
                          filled: run.isSuccess,
                        ),
                        CyberTag(L.of(context).targetTag(run.goal.toString()), color: Cy.ghost),
                        if (run.isWalk) CyberTag(L.of(context).tagWalk, color: Cy.cyan),
                        if (run.isTimeOnly) CyberTag(L.of(context).timeOnly, color: Cy.amber),
                        if (run.distanceEstimated) CyberTag(L.of(context).distanceFromSteps, color: Cy.amber),
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
                                  label: L.of(context).statDistance,
                                  value: Fmt.distance(run.distanceMeters, units, estimated: run.distanceEstimated),
                                  unit: Fmt.distanceUnit(units),
                                  accent: Cy.cyan,
                                ),
                              ),
                              Expanded(
                                child: StatTile(label: L.of(context).statTime, value: Fmt.clock(run.elapsedSeconds)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: L.of(context).statAvgPace,
                                  value: Fmt.pace(run.paceSecondsPerKm, units),
                                  unit: Fmt.paceUnit(units),
                                  size: 20,
                                ),
                              ),
                              Expanded(
                                child: StatTile(
                                  label: L.of(context).statCalories,
                                  value: Fmt.calories(run.calories),
                                  unit: 'kcal',
                                  accent: Cy.amber,
                                  size: 20,
                                ),
                              ),
                              Expanded(
                                child: StatTile(
                                  label: L.of(context).statEvaded,
                                  value: run.chasesTotal == 0
                                      ? '—'
                                      : '${run.chasesEvaded}/${run.chasesTotal}',
                                  accent: Cy.magenta,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          if (run.steps != null) ...[
                            const SizedBox(height: 18),
                            StepFigures(record: run, size: 20),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(L.of(context).sectionRoute),
                    if (_trace == null)
                      Container(
                        height: 200,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Cy.panel, border: Border.all(color: Cy.rule)),
                        child: Text(L.of(context).loadingTrace, style: CyType.label()),
                      )
                    else
                      RouteTrace(trace: _trace!, accent: accent, height: 240, animate: true),

                    if (run.missionId != null) ...[
                      const SizedBox(height: 18),
                      SectionHeader(L.of(context).sectionStory, accent: Cy.cyan),
                      if (run.story.isEmpty)
                        NeonPanel(
                          accent: Cy.rule,
                          child: Text(
                            L.of(context).noStoryLog,
                            style: CyType.body(size: 14, color: Cy.inkDim, height: 1.35),
                          ),
                        )
                      else
                        NeonPanel(
                          accent: Cy.rule,
                          padding: const EdgeInsets.fromLTRB(12, 18, 16, 18),
                          child: StoryLog(
                            story: run.story,
                            mission: context.read<AppState>().missionById(run.missionId!),
                            codexTitle: (id) => context.read<AppState>().codexEntry(id)?.title,
                          ),
                        ),
                    ],
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
