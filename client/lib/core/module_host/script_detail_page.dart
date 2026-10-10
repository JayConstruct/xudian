import 'dart:async';

import 'package:flutter/material.dart';

import '../modules/module_registry.dart';
import '../security/capability_registry.dart';
import '../ui/module_detail_page.dart';
import 'module_host.dart';
import 'script_app_module.dart';

/// Detail routes opened from the store do not have a workspace registry.
class ScriptDetailPage extends StatefulWidget {
  const ScriptDetailPage({
    super.key,
    required this.host,
    required this.pageId,
    required this.title,
  });
  final ModuleHost host;
  final String pageId, title;

  @override
  State<ScriptDetailPage> createState() => _ScriptDetailPageState();
}

class _ScriptDetailPageState extends State<ScriptDetailPage> {
  late final ModuleRegistry registry;
  StreamSubscription<void>? subscription;

  @override
  void initState() {
    super.initState();
    registry = ModuleRegistry([
      for (final i in widget.host.instances.values)
        ScriptAppModule(widget.host, i.package),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
    subscription = widget.host.registryChanges.stream.listen((_) {
      registry.replaceExtensions([
        for (final i in widget.host.instances.values)
          ScriptAppModule(widget.host, i.package),
      ]);
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModuleDetailPage(
    registry: registry,
    pageId: widget.pageId,
    title: widget.title,
  );
}
