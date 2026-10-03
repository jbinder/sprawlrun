import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mission_repository.dart';
import '../models/mission.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import 'panels.dart';

/// The MISSION PACKS section of Settings: what is loaded, and how to add more.
///
/// Packs come in through the system file picker, the same way a backup does,
/// and need no storage permission. For a long time this section told the runner
/// to drop files into the app's documents folder — which is private on Android
/// and cannot be reached without root, so that instruction could never be
/// followed. Importing is the only route in that works.
class PackControls extends StatefulWidget {
  const PackControls({super.key});

  @override
  State<PackControls> createState() => _PackControlsState();
}

class _PackControlsState extends State<PackControls> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = state.missions;

    return Column(
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
              if (repo.importedIds.contains(pack.id)) ...[
                CyberTag(repo.bundledIds.contains(pack.id) ? 'REPLACED' : 'IMPORTED', color: Cy.green),
                IconButton(
                  onPressed: _busy ? null : () => _remove(state, pack),
                  icon: const Icon(Icons.delete_outline, size: 18, color: Cy.inkDim),
                  tooltip: 'Remove ${pack.title}',
                ),
              ] else
                CyberTag('${pack.missions.length} OPS', color: Cy.ghost),
            ],
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(height: 1, color: Cy.rule)),
        ],
        for (final error in repo.loadErrors) ...[
          Text(error, style: CyType.mono(size: 11, color: Cy.red)),
          const SizedBox(height: 6),
        ],
        Text(
          'Add a pack by importing its .json file. Importing a newer version of a pack you already '
          'have replaces it, and your progress through it is kept. See docs/MISSION_PACKS.md for the '
          'format.',
          style: CyType.body(size: 13, color: Cy.ghost, height: 1.4),
        ),
        const SizedBox(height: 12),
        CyberButton(
          label: _busy ? 'Working…' : 'Import pack',
          icon: Icons.file_download_outlined,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: _busy ? null : () => _import(state),
        ),
      ],
    );
  }

  void _say(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: CyType.body(size: 14, color: bad ? Cy.red : Cy.ink)),
      ),
    );
  }

  Future<void> _import(AppState state) async {
    setState(() => _busy = true);
    try {
      // Permissive, as for backups: some document providers do not tag .json.
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Mission pack', extensions: ['json'], mimeTypes: ['application/json']),
        ],
      );
      if (picked == null) return;
      if (await picked.length() > MissionRepository.maxPackBytes) {
        _say('That file is far too large to be a mission pack.', bad: true);
        return;
      }

      final repo = state.missions;
      final source = await picked.readAsString();
      final before = {...repo.importedIds};
      final pack = await state.importMissionPack(source);

      final ops = '${pack.missions.length} operation${pack.missions.length == 1 ? '' : 's'}';
      _say(switch ((before.contains(pack.id), repo.bundledIds.contains(pack.id))) {
        (true, _) => 'Updated ${pack.title} — $ops.',
        (false, true) => 'Imported ${pack.title} — $ops. It replaces the built-in version.',
        (false, false) => 'Imported ${pack.title} — $ops.',
      });
    } on PackImportException catch (e) {
      _say(e.message, bad: true);
    } on Object catch (e) {
      _say('Import failed: $e', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AppState state, MissionPack pack) async {
    final restores = state.missions.bundledIds.contains(pack.id);
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
              Text('REMOVE ${pack.title.toUpperCase()}', style: CyType.display(size: 16, color: Cy.red)),
              const SizedBox(height: 10),
              Text(
                [
                  'Your progress through it is kept: import it again and you pick up where you were.',
                  if (restores) 'The version that came with the app takes its place.',
                ].join(' '),
                style: CyType.body(size: 14, color: Cy.ink, height: 1.4),
              ),
              const SizedBox(height: 18),
              CyberButton(
                label: 'Remove',
                icon: Icons.delete_outline,
                style: CyberButtonStyle.danger,
                dense: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 10),
              CyberButton(
                label: 'Cancel',
                style: CyberButtonStyle.ghost,
                dense: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await state.removeMissionPack(pack.id);
      _say(restores ? 'Removed. ${pack.title} is back to the built-in version.' : 'Removed ${pack.title}.');
    } on Object catch (e) {
      _say('Could not remove the pack: $e', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
