import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/run_record.dart';
import '../screens/run_detail_screen.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import 'panels.dart';

/// One line of the run log; tapping opens the run.
class RunRow extends StatelessWidget {
  const RunRow({super.key, required this.run, required this.units});

  final RunRecord run;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final accent = run.isSuccess ? Cy.green : Cy.magenta;
    return NeonPanel(
      cut: 8,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RunDetailScreen(run: run))),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.missionCodename ?? 'FREE RUN',
                  overflow: TextOverflow.ellipsis,
                  style: CyType.display(size: 12, color: Cy.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  '${Fmt.dateTime(run.startedAt)} · ${Fmt.pace(run.paceSecondsPerKm, units)}${Fmt.paceUnit(units)}',
                  style: CyType.mono(size: 10, color: Cy.ghost),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.distanceWithUnit(run.distanceMeters, units), style: CyType.readout(15, Cy.ink)),
              const SizedBox(height: 3),
              Text(Fmt.clock(run.elapsedSeconds), style: CyType.mono(size: 11, color: Cy.inkDim)),
            ],
          ),
        ],
      ),
    );
  }
}
