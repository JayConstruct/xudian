import 'package:flutter/material.dart';

/// A neutral first-frame surface while the module produces real content.
class PageLoadingPlaceholder extends StatelessWidget {
  const PageLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Text('正在加载页面…'),
      ],
    ),
  );
}
