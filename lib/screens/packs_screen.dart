import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mission_repository.dart';
import '../l10n/l10n.dart';
import '../models/mission.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/picked_text.dart';
import '../widgets/library_list.dart';
import '../widgets/panels.dart';
import 'missions_screen.dart';

/// MISSION PACKS on the RIG screen: the packs, shipped and imported, to add,
/// share and remove. Which one is played is chosen on OPS. Settings' Mission
/// Packs section until 0.10.0.
///
/// Packs come in through the system file picker, the same way a backup does,
/// and need no storage permission. For a long time Settings told the runner
/// to drop files into the app's documents folder — which is private on Android
/// and cannot be reached without root, so that instruction could never be
/// followed. Importing is the only route in that works.
class PacksScreen extends StatefulWidget {
  const PacksScreen({super.key});

  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = state.missions;
    final l = L.of(context);
    return LibraryScreen(
      title: l.rigPacks,
      where: l.rigPacksWhere,
      items: [
        for (final pack in state.packs)
          if (repo.importedIds.contains(pack.id) case final imported)
            LibraryItem(
              leading: Icon(Icons.inventory_2_outlined, size: 20, color: Cy.cyanDim),
              title: pack.title,
              lines: [pack.tagline, if (pack.author != null) l.packBy(pack.author!)],
              tag: imported
                  ? (repo.bundledIds.contains(pack.id) ? l.packReplaced : l.packImported)
                  : l.packOpsTag(pack.missions.length),
              tagColor: imported ? Cy.green : Cy.ghost,
              onExport: _busy ? null : () => _export(state, pack),
              exportTooltip: l.packExportTooltip(pack.title),
              onRemove: imported && !_busy ? () => _remove(state, pack) : null,
              removeTooltip: l.packRemoveTooltip(pack.title),
            ),
      ],
      errors: repo.loadErrors,
      note: l.packExplainer,
      actions: [
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

  void _say(String message, {bool bad = false}) => sayOnLibrary(context, message, bad: bad);

  Future<void> _export(AppState state, MissionPack pack) async {
    final source = await state.missions.sourceOf(pack.id);
    if (source == null || !mounted) return;
    await shareJson(context, name: pack.id, source: source, subject: l10n.packShareSubject(pack.title));
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
      if (!mounted) return;
      sayOnLibrary(
        context,
        switch ((before.contains(pack.id), repo.bundledIds.contains(pack.id))) {
          (true, _) => l10n.packUpdated(pack.title, ops),
          (false, true) => l10n.packImportedReplacing(pack.title, ops),
          (false, false) => l10n.packImportedNew(pack.title, ops),
        },
        action: openAction(context, l10n.packImportedOpen, (_) => MissionsScreen(openPack: pack.id)),
      );
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
