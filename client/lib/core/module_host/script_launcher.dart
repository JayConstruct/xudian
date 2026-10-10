import 'package:flutter/material.dart';

import 'module_host.dart';
import 'script_page.dart';

/// Generic module contribution; the shell never identifies the business owner.
class ScriptLauncher extends StatelessWidget {
  const ScriptLauncher({
    super.key,
    required this.host,
    required this.moduleId,
    required this.handler,
    required this.label,
    required this.id,
    this.floating = true,
  });
  final ModuleHost host;
  final String moduleId, handler, label, id;
  final bool floating;
  @override
  Widget build(BuildContext context) {
    void open() => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: ScriptPage(host: host, moduleId: moduleId, handler: handler),
      ),
    );
    if (!floating) {
      return TextButton.icon(
        onPressed: open,
        icon: const Icon(Icons.extension_outlined),
        label: Text(label),
      );
    }
    return Stack(
      children: [
        Positioned(
          right: 16,
          bottom:
              MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.paddingOf(context).bottom +
              128,
          child: FloatingActionButton.small(
            heroTag: id,
            tooltip: label,
            onPressed: open,
            child: const Icon(Icons.auto_awesome_outlined),
          ),
        ),
      ],
    );
  }
}
