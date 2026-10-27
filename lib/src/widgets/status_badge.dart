import 'package:flutter/material.dart';

/// A passive label. Unlike a Chip, it is not announced as a selectable control.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ]),
      );
}
