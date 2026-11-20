import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/project_links.dart';
import 'panels.dart';

import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';

/// The rows Settings and the screens under it are made of.

class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: CyType.body(size: 15, weight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: CyType.body(size: 12, color: Cy.ghost, height: 1.3)),
              ],
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class SegmentRow<T> extends StatelessWidget {
  const SegmentRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
        for (final entry in options.entries)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              onTap: () => onChanged(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: entry.key == value ? Cy.cyan : Colors.transparent,
                  border: Border.all(color: entry.key == value ? Cy.cyan : Cy.rule),
                ),
                child: Text(
                  entry.value,
                  style: CyType.mono(size: 10, color: entry.key == value ? Cy.v0id : Cy.inkDim),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Out to a page in the browser. The app itself fetches nothing.
class LinkRow extends StatelessWidget {
  const LinkRow({super.key, required this.label, required this.url});

  final String label;
  final Uri url;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await openInBrowser(url)) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.contributeNoBrowser('$url'), style: CyType.body(size: 14, color: Cy.red))),
    );
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _open(context),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
          Icon(Icons.open_in_new, size: 16, color: Cy.inkDim),
        ],
      ),
    ),
  );
}


class RowRule extends StatelessWidget {
  const RowRule({super.key});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(height: 1, color: Cy.rule));
}


/// A quiet line of explanation under a row.
class SettingNote extends StatelessWidget {
  const SettingNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CyType.body(size: 13, color: Cy.ghost, height: 1.4));
}


/// A choice among more options than fit as segments: the current one, and a
/// dialog listing them all.
class PickerRow<T> extends StatelessWidget {
  const PickerRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
            Flexible(
              child: Text(
                options[value] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CyType.mono(size: 12, color: Cy.cyan),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.unfold_more, size: 16, color: Cy.inkDim),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<T>(
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
              Text(label.toUpperCase(), style: CyType.display(size: 14, color: Cy.cyan)),
              const SizedBox(height: 10),
              for (final entry in options.entries)
                InkWell(
                  onTap: () => Navigator.of(context).pop(entry.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.value,
                            style: CyType.body(size: 16, color: entry.key == value ? Cy.cyan : Cy.ink),
                          ),
                        ),
                        if (entry.key == value) Icon(Icons.check, size: 18, color: Cy.cyan),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }
}


class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: CyType.body(size: 15, weight: FontWeight.w600))),
            Text(display, style: CyType.mono(size: 12, color: Cy.cyan)),
          ],
        ),
        Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
