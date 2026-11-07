import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_version.dart';
import '../services/project_links.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import 'panels.dart';
import '../l10n/l10n.dart';

/// The CONTRIBUTE section of Settings: a bug report, an idea, and how to do
/// more. Each leaves for the browser, and only when tapped.
class ContributeControls extends StatelessWidget {
  const ContributeControls({super.key, this.open = openInBrowser});

  final Future<bool> Function(Uri url) open;

  Future<void> _go(BuildContext context, Uri url) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await open(url)) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.contributeNoBrowser('$url'), style: CyType.body(size: 14, color: Cy.red))),
    );
  }

  Future<void> _bug(BuildContext context) async {
    final english = context.read<AppState>().locale.languageCode == 'en';
    final language = english ? null : l10n.languageName;
    final version = await AppVersion.load();
    if (!context.mounted) return;
    await _go(context, ProjectLinks.bug(version: version?.label, language: language));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.contributeNote, style: CyType.body(size: 13, color: Cy.ghost, height: 1.4)),
        const SizedBox(height: 12),
        CyberButton(
          label: l.contributeBug,
          icon: Icons.bug_report_outlined,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: () => _bug(context),
        ),
        const SizedBox(height: 8),
        CyberButton(
          label: l.contributeIdea,
          icon: Icons.lightbulb_outline,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: () => _go(context, ProjectLinks.idea),
        ),
        const SizedBox(height: 8),
        CyberButton(
          label: l.contributeMusic,
          icon: Icons.library_music_outlined,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: () => _go(context, ProjectLinks.suggestMusic),
        ),
        const SizedBox(height: 8),
        CyberButton(
          label: l.contributeHow,
          icon: Icons.groups_outlined,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: () => _go(context, ProjectLinks.contributing),
        ),
      ],
    );
  }
}
