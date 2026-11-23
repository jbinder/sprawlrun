import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import 'panels.dart';
import 'sub_screen.dart';

/// A RIG screen: one kind of importable data, as a list.
///
/// Every kind is laid out the same way — where it is chosen, the items, what
/// failed to load, how to add more — so a runner who has learnt one knows them
/// all, and the next kind gets this screen for free. Nothing here changes what
/// the app does: choosing is a setting, and settings live in Settings, which
/// an import's snackbar opens through [openAction].
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.title,
    required this.where,
    required this.items,
    this.errors = const [],
    this.note,
    required this.actions,
  });

  final String title;

  /// Where the runner chooses among these, since it is not here.
  final String where;
  final List<Widget> items;
  final List<String> errors;
  final String? note;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SubScreen(
    title: title,
    children: [
      Text(where, style: CyType.body(size: 13, color: Cy.ghost, height: 1.4)),
      const SizedBox(height: 12),
      NeonPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Container(height: 1, color: Cy.rule)),
              item,
            ],
            for (final error in errors) ...[
              const SizedBox(height: 8),
              Text(error, style: CyType.mono(size: 11, color: Cy.red)),
            ],
          ],
        ),
      ),
      if (note != null) ...[
        const SizedBox(height: 12),
        Text(note!, style: CyType.body(size: 13, color: Cy.ghost, height: 1.4)),
      ],
      for (final action in actions) ...[const SizedBox(height: 10), action],
    ],
  );
}

/// One entry on a [LibraryScreen]: what it is, whose, and what can be done
/// with it. Edit, export and remove each show only when given.
class LibraryItem extends StatelessWidget {
  const LibraryItem({
    super.key,
    required this.leading,
    required this.title,
    this.lines = const [],
    this.tag,
    this.tagColor,
    this.onEdit,
    this.editTooltip,
    this.onExport,
    this.exportTooltip,
    this.onRemove,
    this.removeTooltip,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final List<String> lines;
  final String? tag;
  final Color? tagColor;
  final VoidCallback? onEdit;
  final String? editTooltip;
  final VoidCallback? onExport;
  final String? exportTooltip;
  final VoidCallback? onRemove;
  final String? removeTooltip;

  /// Where tapping the entry leads — for a state shown here but changed
  /// elsewhere, such as a shelved pack. A chevron by the tag says it goes on.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget action(VoidCallback? onPressed, IconData icon, String? tooltip) => IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: Cy.inkDim),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
    final row = Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: CyType.body(size: 15, weight: FontWeight.w600)),
              for (final line in lines) ...[
                const SizedBox(height: 2),
                Text(line, style: CyType.body(size: 12, color: Cy.ghost, height: 1.3)),
              ],
              // Under the name rather than beside it: a row with three
              // buttons has no width to spare at 360 dp.
              if (tag != null) ...[
                const SizedBox(height: 4),
                if (onTap == null)
                  CyberTag(tag!, color: tagColor ?? Cy.ghost)
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Flexible, so a long translation still shrinks as it
                      // does without the chevron.
                      Flexible(child: CyberTag(tag!, color: tagColor ?? Cy.ghost)),
                      Icon(Icons.chevron_right, size: 18, color: tagColor ?? Cy.ghost),
                    ],
                  ),
              ],
            ],
          ),
        ),
        if (onEdit != null) action(onEdit, Icons.tune, editTooltip),
        if (onExport != null) action(onExport, Icons.ios_share, exportTooltip),
        if (onRemove != null) action(onRemove, Icons.delete_outline, removeTooltip),
      ],
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// A snackbar in the RIG screens' voice, red when something went wrong.
///
/// [action] is a way on to where the item is chosen — after an import, the
/// screen that picks it. It only opens that screen: choosing stays there.
void sayOnLibrary(BuildContext context, String message, {bool bad = false, SnackBarAction? action}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: CyType.body(size: 14, color: bad ? Cy.red : Cy.ink)),
      action: action,
    ),
  );
}

/// A snackbar button that opens the screen [open] builds.
SnackBarAction openAction(BuildContext context, String label, WidgetBuilder open) => SnackBarAction(
  label: label,
  textColor: Cy.cyan,
  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: open)),
);

/// The note under a choice that says where its items are imported and
/// shared, as a link to that RIG screen: RIG is otherwise only an icon in the
/// home screen's top bar, and a runner who never notices it never finds out
/// what can be added.
class RigLink extends StatelessWidget {
  const RigLink(this.text, {super.key, required this.open});

  final String text;
  final WidgetBuilder open;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: open)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.memory, size: 16, color: Cy.cyanDim),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: CyType.body(size: 13, color: Cy.cyan, height: 1.4))),
          Icon(Icons.chevron_right, size: 18, color: Cy.cyanDim),
        ],
      ),
    ),
  );
}

/// Hands [source] to the share sheet as `<name>.json`, to keep or pass on.
Future<void> shareJson(BuildContext context, {required String name, required String source, required String subject}) async {
  try {
    final file = File('${(await getTemporaryDirectory()).path}/$name.json');
    await file.writeAsString(source);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/json')], subject: subject),
    );
  } on Object catch (e) {
    if (context.mounted) sayOnLibrary(context, l10n.exportFailed('$e'), bad: true);
  }
}
