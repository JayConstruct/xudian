import '../ui/ui_icon.dart';
import '../ui/native_ui.dart';
import '../ui/ui_composition.dart';

import 'package:flutter/material.dart';

import 'module_host.dart';
import 'script_page.dart';

Future<void> openScriptLauncher(
  BuildContext context, {
  required ModuleHost host,
  required String moduleId,
  required String handler,
  required String label,
  PageContext pageContext = const PageContext(),
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Semantics(
      label: label,
      child: FractionallySizedBox(
        heightFactor: .9,
        child: ScriptPage(
          host: host,
          moduleId: moduleId,
          handler: handler,
          pageContext: {
            ...pageContext.values,
            if (pageContext.taskId != null) 'taskId': pageContext.taskId,
            if (pageContext.projectId != null)
              'projectId': pageContext.projectId,
          },
        ),
      ),
    ),
  );
}

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
    void open() => openScriptLauncher(
      context,
      host: host,
      moduleId: moduleId,
      handler: handler,
      label: label,
    );
    if (!floating) {
      return NativeUi(
        child: TextButton.icon(
          onPressed: open,
          icon: const UiIcon(Icons.extension_outlined),
          label: Text(label),
        ),
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
            child: const UiIcon(Icons.auto_awesome_outlined),
          ),
        ),
      ],
    );
  }
}
