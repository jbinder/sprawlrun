import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/run_record.dart';
import '../theme/cyber_palette.dart';
import 'panels.dart';

/// Steps and cadence, side by side, for a run that counted them. Shared by the
/// summary and the run's own page, so the two cannot word them differently.
class StepFigures extends StatelessWidget {
  const StepFigures({super.key, required this.record, required this.size});

  final RunRecord record;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final cadence = record.cadence;
    return Row(
      children: [
        Expanded(
          child: StatTile(label: l.statSteps, value: '${record.steps}', size: size, accent: Cy.green),
        ),
        Expanded(
          child: StatTile(
            label: l.statCadence,
            value: cadence == null ? '—' : '${cadence.round()}',
            unit: cadence == null ? null : l.unitStepsPerMinute,
            size: size,
          ),
        ),
      ],
    );
  }
}
