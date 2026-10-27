import 'package:flutter/material.dart';

/// A small group of cards that keeps related information together on desktop
/// and stacks it in reading order on smaller screens.
class ResponsiveCards extends StatelessWidget {
  const ResponsiveCards(
      {super.key,
      required this.children,
      this.maxColumns = 2,
      this.minColumnWidth = 320,
      this.spacing = 16});
  final List<Widget> children;
  final int maxColumns;
  final double minColumnWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final columns =
            ((constraints.maxWidth + spacing) / (minColumnWidth + spacing))
                .floor()
                .clamp(1, maxColumns);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var start = 0;
                  start < children.length;
                  start += columns) ...[
                if (start > 0) SizedBox(height: spacing),
                if (columns == 1)
                  children[start]
                else
                  IntrinsicHeight(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        for (var offset = 0; offset < columns; offset++) ...[
                          if (offset > 0) SizedBox(width: spacing),
                          Expanded(
                              child: start + offset < children.length
                                  ? children[start + offset]
                                  : const SizedBox.shrink()),
                        ],
                      ])),
              ],
            ]);
      });
}
