import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/release_notes.dart';
import '../services/project_links.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import 'panels.dart';

/// Shows what [notes] brought, newest first: after an update, every version
/// the runner missed; from Settings, the installed one.
Future<void> showReleaseNotes(
  BuildContext context,
  List<ReleaseNote> notes, {
  Future<bool> Function(Uri url) open = openInBrowser,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ReleaseNotesDialog(notes: notes, open: open),
  );
}

class ReleaseNotesDialog extends StatelessWidget {
  const ReleaseNotesDialog({super.key, required this.notes, this.open = openInBrowser});

  final List<ReleaseNote> notes;
  final Future<bool> Function(Uri url) open;

  /// One version's page for one version, the whole list for several.
  Uri get _fullNotes =>
      notes.length == 1 ? ProjectLinks.release(notes.single.version) : ProjectLinks.releases;

  Future<void> _openFull(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = _fullNotes;
    if (await open(url)) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.contributeNoBrowser('$url'), style: CyType.body(size: 14, color: Cy.red))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NeonPanel(
        accent: Cy.cyan,
        lit: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.whatsNewTitle, style: CyType.display(size: 16, color: Cy.cyan)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, note) in notes.indexed) ...[
                      if (i > 0) const SizedBox(height: 16),
                      Text(
                        l.whatsNewRelease(note.version, note.name(l)).toUpperCase(),
                        style: CyType.label(size: 11, color: Cy.magenta),
                      ),
                      const SizedBox(height: 8),
                      for (final item in note.items(l))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 7, right: 8),
                                child: Container(width: 4, height: 4, color: Cy.cyanDim),
                              ),
                              Expanded(
                                child: Text(item, style: CyType.body(size: 14, color: Cy.ink, height: 1.4)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            CyberButton(
              label: l.whatsNewFullNotes,
              icon: Icons.open_in_new,
              style: CyberButtonStyle.ghost,
              dense: true,
              onPressed: () => _openFull(context),
            ),
            const SizedBox(height: 10),
            CyberButton(
              label: l.whatsNewClose,
              dense: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
