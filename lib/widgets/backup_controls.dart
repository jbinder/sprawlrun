import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import 'panels.dart';

/// Export and import buttons for the DATA section of Settings.
///
/// Both directions go through the system: export hands the file to the share
/// sheet, import reads one back through the document picker. Neither needs a
/// storage permission, and the app still cannot see any file the runner did not
/// hand it.
class BackupControls extends StatefulWidget {
  const BackupControls({super.key});

  @override
  State<BackupControls> createState() => _BackupControlsState();
}

class _BackupControlsState extends State<BackupControls> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final runs = state.runLog.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A backup holds your settings, campaign progress, achievements, codex and '
          'every run with its GPS trace — everything the app knows. It is plain JSON, '
          'so you can read it yourself.',
          style: CyType.body(size: 13, color: Cy.ghost, height: 1.4),
        ),
        const SizedBox(height: 14),
        CyberButton(
          label: _busy ? 'Working…' : 'Export backup',
          icon: Icons.file_upload_outlined,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: _busy ? null : () => _export(state, runs),
        ),
        const SizedBox(height: 10),
        CyberButton(
          label: _busy ? 'Working…' : 'Import backup',
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

  Future<void> _export(AppState state, int runs) async {
    setState(() => _busy = true);
    try {
      final json = await state.exportBackup();
      // The share sheet needs a real file; the cache directory is the right
      // home for one, since the copy the runner keeps is the one they save out.
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${BackupService.suggestedFileName(DateTime.now())}');
      await file.writeAsString(json);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'SPRAWL//RUN backup',
        ),
      );
      _say('Backup ready — $runs run${runs == 1 ? '' : 's'}, ${_kb(json.length)}.');
    } on Object catch (e) {
      _say('Export failed: $e', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _kb(int bytes) =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(bytes < 1024 * 1024 ? 0 : 1)} KB';

  Future<void> _import(AppState state) async {
    setState(() => _busy = true);
    try {
      // Some document providers do not tag .json, so the type filter stays
      // permissive rather than hiding the file the runner is looking for.
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'SPRAWL//RUN backup', extensions: ['json'], mimeTypes: ['application/json']),
        ],
      );
      if (picked == null) return;

      final archive = BackupArchive.parse(await picked.readAsString());
      if (!mounted) return;

      final mode = await _chooseMode(archive);
      if (mode == null) return;

      final report = await state.importBackup(archive, mode);
      _say(_summarise(report));
    } on BackupFormatException catch (e) {
      _say(e.message, bad: true);
    } on Object catch (e) {
      _say('Import failed: $e', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _summarise(ImportReport r) {
    if (r.mode == ImportMode.replace) {
      return 'Restored ${r.runsAdded} run${r.runsAdded == 1 ? '' : 's'} '
          'and ${r.missionsAdded} completed mission${r.missionsAdded == 1 ? '' : 's'}.';
    }
    final parts = <String>[
      '${r.runsAdded} new run${r.runsAdded == 1 ? '' : 's'}',
      if (r.missionsAdded > 0) '${r.missionsAdded} mission${r.missionsAdded == 1 ? '' : 's'}',
      if (r.achievementsAdded > 0) '${r.achievementsAdded} achievement${r.achievementsAdded == 1 ? '' : 's'}',
      if (r.codexAdded > 0) '${r.codexAdded} codex entr${r.codexAdded == 1 ? 'y' : 'ies'}',
    ];
    final skipped = r.runsAlreadyPresent > 0 ? ' ${r.runsAlreadyPresent} already here.' : '';
    return 'Merged ${parts.join(', ')}.$skipped';
  }

  /// Asks what to do with the data already on the device. Deliberately has no
  /// default action — replacing is destructive and merging is not, and the
  /// difference is worth one tap.
  Future<ImportMode?> _chooseMode(BackupArchive archive) {
    final runs = archive.runs.length;
    final missions = archive.profile.completedMissions.length;
    final when = archive.exportedAt.toLocal();
    final stamp = '${when.year}-${_two(when.month)}-${_two(when.day)} ${_two(when.hour)}:${_two(when.minute)}';

    return showDialog<ImportMode>(
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
              Text('BACKUP FOUND', style: CyType.display(size: 16, color: Cy.cyan)),
              const SizedBox(height: 10),
              Text(
                'Written $stamp.\n'
                '$runs run${runs == 1 ? '' : 's'}, '
                '${archive.traceCount} with a GPS trace, '
                '$missions mission${missions == 1 ? '' : 's'} completed.',
                style: CyType.body(size: 15, color: Cy.inkDim, height: 1.35),
              ),
              const SizedBox(height: 16),
              CyberButton(
                label: 'Merge into this device',
                icon: Icons.merge_outlined,
                dense: true,
                onPressed: () => Navigator.of(context).pop(ImportMode.merge),
              ),
              const SizedBox(height: 6),
              Text(
                'Adds runs and progress this device does not have. Keeps your settings. '
                'Nothing is lost.',
                style: CyType.body(size: 12, color: Cy.ghost, height: 1.3),
              ),
              const SizedBox(height: 14),
              CyberButton(
                label: 'Replace everything',
                icon: Icons.restore_page_outlined,
                style: CyberButtonStyle.danger,
                dense: true,
                onPressed: () => Navigator.of(context).pop(ImportMode.replace),
              ),
              const SizedBox(height: 6),
              Text(
                'Restores this backup exactly. Every run and setting currently on this '
                'device is deleted. Use this on a new phone.',
                style: CyType.body(size: 12, color: Cy.ghost, height: 1.3),
              ),
              const SizedBox(height: 14),
              CyberButton(
                label: 'Cancel',
                style: CyberButtonStyle.ghost,
                dense: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
