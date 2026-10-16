import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mission_repository.dart';
import '../models/mission.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/picked_text.dart';
import 'panels.dart';
import '../l10n/l10n.dart';

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
    final l = L.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final pack in state.packs) ...[
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 15, color: Cy.cyanDim),
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
                CyberTag(repo.bundledIds.contains(pack.id) ? l.packReplaced : l.packImported, color: Cy.green),
                IconButton(
                  onPressed: _busy ? null : () => _remove(state, pack),
                  icon: Icon(Icons.delete_outline, size: 18, color: Cy.inkDim),
                  tooltip: l.packRemoveTooltip(pack.title),
                ),
              ] else
                CyberTag(l.packOpsTag(pack.missions.length), color: Cy.ghost),
            ],
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(height: 1, color: Cy.rule)),
        ],
        for (final error in repo.loadErrors) ...[
          Text(error, style: CyType.mono(size: 11, color: Cy.red)),
          const SizedBox(height: 6),
        ],
        Text(
          l.packExplainer,
          style: CyType.body(size: 13, color: Cy.ghost, height: 1.4),
        ),
        const SizedBox(height: 12),
        CyberButton(
          label: _busy ? l.working : l.packImport,
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
        acceptedTypeGroups: [
          XTypeGroup(label: l10n.packFileType, extensions: ['json'], mimeTypes: ['application/json']),
        ],
      );
      if (picked == null) return;
      if (await picked.length() > MissionRepository.maxPackBytes) {
        _say(l10n.packTooLarge, bad: true);
        return;
      }

      final repo = state.missions;
      final source = await readPickedText(picked);
      final before = {...repo.importedIds};
      final pack = await state.importMissionPack(source);

      final ops = pack.missions.length;
      _say(switch ((before.contains(pack.id), repo.bundledIds.contains(pack.id))) {
        (true, _) => l10n.packUpdated(pack.title, ops),
        (false, true) => l10n.packImportedReplacing(pack.title, ops),
        (false, false) => l10n.packImportedNew(pack.title, ops),
      });
    } on PackImportException catch (e) {
      _say(e.message, bad: true);
    } on Object catch (e) {
      _say(l10n.importFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AppState state, MissionPack pack) async {
    final restores = state.missions.bundledIds.contains(pack.id);
    final l = L.of(context);
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
              Text(l.packRemoveTitle(pack.title.toUpperCase()), style: CyType.display(size: 16, color: Cy.red)),
              const SizedBox(height: 10),
              Text(
                [
                  l.packRemoveKeepsProgress,
                  if (restores) l.packRemoveRestores,
                ].join(' '),
                style: CyType.body(size: 14, color: Cy.ink, height: 1.4),
              ),
              const SizedBox(height: 18),
              CyberButton(
                label: l.remove,
                icon: Icons.delete_outline,
                style: CyberButtonStyle.danger,
                dense: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 10),
              CyberButton(
                label: l.cancel,
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
      _say(restores ? l10n.packRemovedRestored(pack.title) : l10n.packRemoved(pack.title));
    } on Object catch (e) {
      _say(l10n.packRemoveFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
