import 'package:flutter/material.dart';

/// One content scroll owner; previews grow to their natural height.
class ResponsiveContentGrid extends StatelessWidget {
  const ResponsiveContentGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 16.0;
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns = constraints.maxWidth >= 680 * scale ? 2 : 1;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
