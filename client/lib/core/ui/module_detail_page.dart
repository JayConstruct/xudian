import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../modules/module_registry.dart';
import 'ui_composition.dart';
import 'ui_component.dart';
import 'ui_page_host.dart';
import 'workspace_header.dart';

/// A module detail route owns its header independently of the workspace below.
class ModuleDetailPage extends StatefulWidget {
  const ModuleDetailPage({
    super.key,
    required this.registry,
    required this.pageId,
    this.title,
    this.pageContext = const PageContext(),
    this.child,
  });

  final ModuleRegistry registry;
  final String pageId;
  final String? title;
  final PageContext pageContext;
  final Widget? child;

  @override
  State<ModuleDetailPage> createState() => _ModuleDetailPageState();
}

class _ModuleDetailPageState extends State<ModuleDetailPage> {
  final header = WorkspaceHeaderController();
  UiPageRegistration? currentPage;
  String? currentContext;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    header.addListener(_changed);
    widget.registry.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ModuleDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry != widget.registry) {
      oldWidget.registry.removeListener(_changed);
      widget.registry.addListener(_changed);
      currentPage = null;
    }
  }

  @override
  void dispose() {
    widget.registry.removeListener(_changed);
    header.removeListener(_changed);
    header.dispose();
    super.dispose();
  }

  void _back() {
    final content = header.content;
    final event = content?.spec['backEvent'];
    if (event != null) unawaited(content!.dispatch(event));
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.registry.ui.page(widget.pageId);
    if (!identical(currentPage, page) ||
        currentContext != widget.pageContext.identity) {
      currentPage = page;
      currentContext = widget.pageContext.identity;
      revision++;
    }
    final lease = header.activate(
      identity: '${widget.pageId}:$revision',
      moduleId: page?.moduleId ?? '',
      pageId: widget.pageId,
      enabled: page?.headerMode == 'contributed',
      isActive: () =>
          mounted && identical(widget.registry.ui.page(widget.pageId), page),
    );
    final spec = lease?.isActive() == true ? header.content?.spec : null;
    final hasInternalBack = spec?['backEvent'] != null;
    return WorkspaceHeaderScope(
      controller: header,
      lease: lease,
      child: PopScope<void>(
        canPop: !hasInternalBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && hasInternalBack) _back();
        },
        child: UiPackScope(
          moduleId: page?.moduleId,
          child: DetailPage(
            title:
                spec?['title'] as String? ??
                (lease?.isActive() == true
                    ? ''
                    : widget.title ?? page?.title ?? '页面不可用'),
            leading: hasInternalBack ? BackButton(onPressed: _back) : null,
            child:
                widget.child ??
                UiPageHost(
                  registry: widget.registry,
                  pageId: widget.pageId,
                  pageContext: widget.pageContext,
                ),
          ),
        ),
      ),
    );
  }
}
