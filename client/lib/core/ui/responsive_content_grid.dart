import 'package:flutter/material.dart';

/// One content scroll owner; previews grow to their natural height.
class ResponsiveContentGrid extends StatelessWidget {
  const ResponsiveContentGrid({
    super.key,
    required this.children,
    this.firstColumnFlex = 1,
    this.spacing = 16,
  });
  final List<Widget> children;
  final double firstColumnFlex, spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = spacing;
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns = constraints.maxWidth >= 680 * scale ? 2 : 1;
      final contentWidth = constraints.maxWidth - gap * (columns - 1);
      final secondWidth = contentWidth / (1 + firstColumnFlex);
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (index, child) in children.indexed)
            SizedBox(
              width: columns == 1
                  ? contentWidth
                  : index.isEven
                  ? contentWidth - secondWidth
                  : secondWidth,
              child: child,
            ),
        ],
      );
    },
  );
}
