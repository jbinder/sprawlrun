import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colour_theme.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../theme/theme_draft.dart';
import '../widgets/backdrop.dart';
import '../widgets/colour_picker.dart';
import '../widgets/panels.dart';
import '../l10n/l10n.dart';

/// Makes a colour theme in the app, from a copy of one or by changing one the
/// runner made: the four main colours first, every role behind them.
///
/// The screen itself stays in the colours the app is wearing, and only the
/// preview shows the draft — a half-made theme that hid the very controls
/// that could fix it would be worse than none. For the same reason it will
/// not save a theme the contrast rules refuse, and says which role is wrong.
class ThemeEditorScreen extends StatefulWidget {
  const ThemeEditorScreen({super.key, required this.draft});

  final ThemeDraft draft;

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  ThemeDraft get _draft => widget.draft;
  late final TextEditingController _name = TextEditingController(text: _draft.name);
  late final String _startName = _draft.name;
  bool _showAll = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _dirty => _draft.changed || _name.text.trim() != _startName;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final issue = _draft.issue;
    final nameOk = _name.text.trim().isNotEmpty;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          _saving = true;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
                        l.themeEditorTitle,
                        style: CyType.display(size: 14, color: Cy.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                    children: [
                      Text(l.themeEditorName, style: CyType.body(size: 15, weight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        maxLength: ColourTheme.maxNameLength,
                        textCapitalization: TextCapitalization.characters,
                        style: CyType.mono(size: 15, color: Cy.cyan),
                        decoration: _fieldDecoration(),
                        onChanged: (v) => setState(() => _draft.name = v),
                      ),
                      const SizedBox(height: 18),
                      SectionHeader(l.themeEditorPreview),
                      _Preview(palette: _draft.palette),
                      const SizedBox(height: 10),
                      _Verdict(issue: issue),
                      const SizedBox(height: 20),
                      SectionHeader(l.themeEditorMain),
                      NeonPanel(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Column(
                          children: [
                            for (final role in ThemeDraft.mainRoles)
                              _RoleRow(
                                label: roleLabel(l, role),
                                colour: _draft.colours[role]!,
                                onTap: () => _pick(role),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SectionHeader(
                        l.themeEditorAll,
                        trailing: IconButton(
                          onPressed: () => setState(() => _showAll = !_showAll),
                          icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more, color: Cy.inkDim),
                          tooltip: l.themeEditorAll,
                        ),
                      ),
                      if (_showAll) ...[
                        Text(l.themeEditorAllHint, style: CyType.body(size: 13, color: Cy.ghost, height: 1.4)),
                        const SizedBox(height: 10),
                        NeonPanel(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Column(
                            children: [
                              for (final role in ColourTheme.roles)
                                _RoleRow(
                                  label: roleLabel(l, role),
                                  colour: _draft.colours[role]!,
                                  onTap: () => _pick(role),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      CyberButton(
                        label: _saving ? l.working : l.themeEditorSave,
                        icon: Icons.check,
                        onPressed: issue == null && nameOk && !_saving ? _save : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration() => InputDecoration(
    isDense: true,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    filled: true,
    fillColor: Cy.panelHi,
    border: OutlineInputBorder(borderSide: BorderSide(color: Cy.rule), borderRadius: BorderRadius.zero),
    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Cy.rule), borderRadius: BorderRadius.zero),
    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Cy.cyan), borderRadius: BorderRadius.zero),
  );

  Future<void> _pick(String role) async {
    final l = L.of(context);
    var picked = _draft.colours[role]!;
    final use = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Cy.panel,
        shape: const RoundedRectangleBorder(),
        title: Text(roleLabel(l, role), style: CyType.label(color: Cy.cyan, size: 13)),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: ColourPicker(initial: picked, onChanged: (c) => picked = c),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l.themePickerUse)),
        ],
      ),
    );
    if (use == true) setState(() => _draft.set(role, picked));
  }

  Future<bool> _confirmLeave() async {
    final l = L.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Cy.panel,
        shape: const RoundedRectangleBorder(),
        title: Text(l.themeEditorLeaveTitle, style: CyType.label(color: Cy.amber, size: 13)),
        content: Text(l.themeEditorLeaveBody, style: CyType.body(size: 14, color: Cy.ink, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.themeEditorKeepEditing)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l.discard)),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final theme = await state.saveThemeDraft(_draft);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.themeSaved(theme.name), style: CyType.body(size: 14, color: Cy.ink))),
      );
      navigator.pop();
    } on Object catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importFailed('$e'), style: CyType.body(size: 14, color: Cy.red))),
      );
    }
  }
}

/// The runner's word for a colour role.
String roleLabel(L l, String role) => switch (role) {
  'background' => l.themeRoleBackground,
  'panel' => l.themeRolePanel,
  'panelRaised' => l.themeRolePanelRaised,
  'rule' => l.themeRoleRule,
  'primary' => l.themeRolePrimary,
  'primaryDim' => l.themeRolePrimaryDim,
  'hostile' => l.themeRoleHostile,
  'hostileDim' => l.themeRoleHostileDim,
  'story' => l.themeRoleStory,
  'success' => l.themeRoleSuccess,
  'failure' => l.themeRoleFailure,
  'locked' => l.themeRoleLocked,
  'text' => l.themeRoleText,
  'textDim' => l.themeRoleTextDim,
  _ => role,
};

class _RoleRow extends StatelessWidget {
  const _RoleRow({required this.label, required this.colour, required this.onTap});

  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: colour, border: Border.all(color: Cy.rule)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: CyType.body(size: 15, color: Cy.ink))),
            const SizedBox(width: 8),
            Text(ColourTheme.hex(colour), style: CyType.mono(size: 12, color: Cy.inkDim)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: Cy.inkDim),
          ],
        ),
      ),
    );
  }
}

/// Whether the draft can be read, said in the runner's words.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.issue});

  final LegibilityIssue? issue;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final (text, colour, icon) = switch (issue) {
      null => (l.themeEditorReadable, Cy.green, Icons.check_circle_outline),
      LowContrast(:final role, :final ratio, :final needed) => (
        l.themeEditorLowContrast(roleLabel(l, role), ratio.toStringAsFixed(1), needed.toStringAsFixed(1)),
        Cy.amber,
        Icons.warning_amber,
      ),
      SameColour(:final first, :final second) => (
        l.themeEditorSameColour(roleLabel(l, first), roleLabel(l, second)),
        Cy.amber,
        Icons.warning_amber,
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colour),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: CyType.body(size: 13, color: colour, height: 1.4))),
      ],
    );
  }
}

/// A slice of the app drawn in the draft's colours: background, a panel with
/// its text, and every accent where the app uses it.
class _Preview extends StatelessWidget {
  const _Preview({required this.palette});

  final CyPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final p = palette;
    Widget tag(String text, Color colour) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: colour)),
      child: Text(text, style: CyType.mono(size: 10, color: colour)),
    );

    return Container(
      color: p.v0id,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: p.panel,
              border: Border.all(color: p.rule),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.themePreviewHeading, style: CyType.display(size: 13, color: p.ink)),
                const SizedBox(height: 4),
                Text(l.themePreviewBody, style: CyType.body(size: 13, color: p.inkDim, height: 1.3)),
                const SizedBox(height: 10),
                Text(l.themePreviewStory, style: CyType.body(size: 13, color: p.amber, height: 1.3)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    tag(l.themePreviewPursuit, p.magenta),
                    tag(l.tagSuccess, p.green),
                    tag(l.tagFailed, p.red),
                    tag(l.tagLocked, p.ghost),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 6,
                  color: p.cyanDim,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: 0.6, child: Container(color: p.cyan)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: p.panelHi,
              border: Border.all(color: p.cyan),
            ),
            child: Text(
              l.themePreviewButton,
              textAlign: TextAlign.center,
              style: CyType.mono(size: 13, color: p.cyan),
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 3, color: p.magentaDim),
        ],
      ),
    );
  }
}
