import 'package:flutter/material.dart';

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

