import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../widgets/panels.dart';
import '../widgets/sub_screen.dart';
import 'themes_screen.dart';
import 'songs_screen.dart';
import 'packs_screen.dart';

/// What a runner can import and export, in one place: colour themes, songs
/// and mission packs. Reached from the home screen's top bar and from the note
/// under each choice. The rule is that content a runner can share lives here,
/// while choices and the runner's own records stay in Settings — which song
/// plays, how loud, whether a pack may recolour the app, and the backup.
///
/// Each kind is a screen of its own, so the next thing a runner can import
/// gets a screen here rather than another section in a long list.
class RigScreen extends StatelessWidget {
  const RigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return SubScreen(
      title: l.rigTitle,
      children: [
        _Entry(
          icon: Icons.palette_outlined,
          title: l.rigThemes,
          hint: l.rigThemesHint,
          accent: Cy.cyan,
          open: (_) => const ThemesScreen(),
        ),
        const SizedBox(height: 12),
        _Entry(
          icon: Icons.graphic_eq,
          title: l.rigSongs,
          hint: l.rigSongsHint,
          accent: Cy.magenta,
          open: (_) => const SongsScreen(),
        ),
        const SizedBox(height: 12),
        _Entry(
          icon: Icons.auto_stories_outlined,
          title: l.rigPacks,
          hint: l.rigPacksHint,
          accent: Cy.amber,
          open: (_) => const PacksScreen(),
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.icon, required this.title, required this.hint, required this.accent, required this.open});

  final IconData icon;
  final String title;
  final String hint;
  final Color accent;
  final WidgetBuilder open;

  @override
  Widget build(BuildContext context) => NeonPanel(
    accent: accent,
    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: open)),
    child: Row(
      children: [
        Icon(icon, size: 28, color: accent),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: CyType.display(size: 16, color: accent)),
              const SizedBox(height: 4),
              Text(hint, style: CyType.body(size: 13, color: Cy.inkDim, height: 1.3)),
            ],
          ),
        ),
        Icon(Icons.chevron_right, size: 22, color: Cy.inkDim),
      ],
    ),
  );
}
