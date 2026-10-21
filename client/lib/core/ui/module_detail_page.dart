import 'dart:async';

import 'package:flutter/material.dart';

import 'ui_surfaces.dart';
import '../modules/module_registry.dart';
import 'ui_composition.dart';
import 'ui_component.dart';
import 'ui_page_host.dart';
import 'workspace_header.dart';
import 'ui_icon.dart';
import 'native_ui.dart';
import 'workspace_header_action.dart';
import 'workspace_header_menu.dart';

/// A module detail route owns its header independently of the workspace below.
class ModuleDetailPage extends StatefulWidget {
  const ModuleDetailPage({
    super.key,
    required this.registry,
    required this.pageId,
    this.title,
    this.pageContext = const PageContext(),
    this.child,
    this.panel = false,
  });

  final ModuleRegistry registry;
  final String pageId;
  final String? title;
  final PageContext pageContext;
  final Widget? child;
  final bool panel;

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

  void _openHeaderMenu(WorkspaceHeaderLease? lease, Object? owner) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 340,
              maxHeight: MediaQuery.sizeOf(context).height * .7,
            ),
            child: SingleChildScrollView(
              child: WorkspaceHeaderMenu(
                controller: header,
                owner: owner,
                lease: lease,
                hostItems: const [],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WorkspaceHeaderLease? lease,
    Map<String, Object?>? spec,
  ) {
    final actions = (spec?['actions'] as List? ?? [])
        .whereType<Map>()
        .map((action) => Map<String, Object?>.from(action))
        .toList();
    if (actions.isEmpty) return const [];
    final content = header.content;
    final inline = fittingHeaderActions(
      context,
      actions,
      (MediaQuery.sizeOf(context).width * .32).clamp(60, 180),
      compact: true,
    );
    return [
      for (final action in inline)
        WorkspaceHeaderAction(
          action: action,
          compact: true,
          onPressed: () {
            if (lease != null &&
                identical(header.lease, lease) &&
                lease.isActive() &&
                identical(header.content?.owner, content?.owner)) {
              unawaited(header.content!.dispatch(action['event']));
            }
          },
        ),
      if (actions.any((action) => !inline.contains(action)))
        NativeUi(
          child: IconButton(
            tooltip: '页面菜单',
            onPressed: () => _openHeaderMenu(lease, content?.owner),
            icon: const UiIcon(Icons.more_horiz),
          ),
        ),
    ];
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
      enabled: {'contributed', 'date'}.contains(page?.headerMode),
      mode: page?.headerMode ?? 'standard',
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
          child: widget.panel
              ? WorkspaceContentInsets(
                  bottom: 0,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                            child: Row(
                              children: [
                                if (hasInternalBack)
                                  BackButton(onPressed: _back),
                                Expanded(
                                  child: Text(
                                    spec?['title'] as String? ??
                                        widget.title ??
                                        page?.title ??
                                        '页面不可用',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ..._actions(context, lease, spec),
                                NativeUi(
                                  child: IconButton(
                                    tooltip: '关闭面板',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const UiIcon(Icons.close),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child:
                                widget.child ??
                                UiPageHost(
                                  registry: widget.registry,
                                  pageId: widget.pageId,
                                  pageContext: widget.pageContext,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : DetailPage(
                  title:
                      spec?['title'] as String? ??
                      (lease?.isActive() == true
                          ? ''
                          : widget.title ?? page?.title ?? '页面不可用'),
                  titleMaxLines: page?.headerMode == 'date' ? 3 : 1,
                  leading: hasInternalBack
                      ? BackButton(onPressed: _back)
                      : null,
                  actions: _actions(context, lease, spec),
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
