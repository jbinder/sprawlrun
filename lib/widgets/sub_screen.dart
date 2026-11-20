import 'package:flutter/material.dart';

import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import 'backdrop.dart';

/// A screen under the home screen's top bar: a back arrow, a title, and a
/// scrolling column. What Settings looks like, so the screens split off it
/// still feel like one place.
class SubScreen extends StatelessWidget {
  const SubScreen({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: GridBackdrop(
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back, color: Cy.inkDim),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CyType.display(size: 14, color: Cy.ink),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 28), children: children),
            ),
          ],
        ),
      ),
    ),
  );
}
