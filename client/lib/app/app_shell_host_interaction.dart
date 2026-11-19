part of 'app_shell.dart';

extension _AppShellHostInteraction on _AppShellState {
  Future<Object?> _dispatchHostInteraction(
    ModuleActor caller,
    String method,
    Map<String, Object?> args,
  ) async {
    if (!mounted) throw StateError('Host interaction unavailable');
    switch (method) {
      case 'ui.showCode':
        await showCodePreviewDialog(context, args);
        return null;
      case 'ui.notify':
        AppToast.show(
          context,
          message: args['message'] as String,
          kind: args['kind'] as String,
          duration: Duration(milliseconds: args['duration'] as int),
        );
        return null;
      case 'ui.review':
        final details = Map<String, Object?>.from(args);
        final rawConfirmation = details.remove('confirmation');
        return reviewDialog(
          context,
          '确认实际数据变更',
          details,
          confirmation: rawConfirmation == null
              ? null
              : PlanConfirmation.parse(rawConfirmation),
        );
      case 'packages.review':
        return reviewDialog(context, '审核模块文件、数据、界面和权限', args);
      case 'grants.request':
        return reviewDialog(context, '授权模块调用（30分钟，最多20次写入）', args);
      case 'browser.capture':
        return platformBridge!.invoke(
          caller,
          method,
          args,
          browserTheme: Theme.of(context),
        );
      case 'ui.dialog':
        return showDialog<Map<String, Object?>>(
          context: context,
          barrierColor: args['presentation'] == 'compact'
              ? Theme.of(context).colorScheme.scrim.withValues(alpha: .4)
              : null,
          animationStyle: args['presentation'] == 'compact'
              ? AppMotion.dialogStyle(context)
              : null,
          builder: (_) => UiPackScope(
            moduleId: caller.moduleId,
            child: HostFormDialog(
              title: args['title'] as String? ?? '模块输入',
              description: args['description'] as String?,
              submitLabel: args['submitLabel'] as String? ?? '继续',
              presentation: args['presentation'] as String?,
              fields: [
                for (final f in args['fields'] as List? ?? []) object(f),
              ],
            ),
          ),
        );
      case 'secrets.configure':
        return platformBridge!.configureSecret(caller, args['endpoint'], (
          endpoint,
        ) async {
          final values = await showDialog<Map<String, Object?>>(
            context: context,
            builder: (_) => UiPackScope(
              defaultOnly: true,
              child: HostFormDialog(
                title: '安全凭据 · ${caller.moduleId}',
                fields: [
                  {
                    'key': 'key',
                    'label': '${args['label'] ?? '密钥'}（绑定 $endpoint）',
                    'type': 'secret',
                  },
                ],
              ),
            ),
          );
          if (values == null) return null;
          return values['key'] as String;
        });
      case 'ui.navigate':
      case 'ui.panel':
        final pageId = args['page'] as String;
        if (pageId == 'app.host.settings') {
          _openSettings();
          return true;
        }
        if (pageId == 'app.host.layout') {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => UiLayoutPage(registry: widget.registry),
              ),
            ),
          );
          return true;
        }
        final page = widget.registry.ui.page(pageId);
        if (page == null) throw StateError('Page unavailable');
        final values = object(args['context'] ?? {});
        if (method == 'ui.navigate') {
          final workspaceEntries = widget.registry.ui.entries.where(
            (entry) =>
                entry.pageId == pageId &&
                entry.opening == UiOpening.workspace &&
                !entry.content,
          );
          if (workspaceEntries.isNotEmpty) {
            final entry = workspaceEntries.first;
            final pageContext = _profile
                .mountFor(entry)
                .context
                .merge(PageContext(values: values));
            if (mountProblem(
                  widget.registry.ui,
                  entry,
                  _profile.mountFor(entry),
                  context: pageContext,
                ) ==
                null) {
              // A module can navigate from a detail route or modal panel.
              // Reveal the shell before rendering the destination; background
              // pages defer work while a route covers them (including handoff
              // to another module's preview page).
              final workspaceRoute = ModalRoute.of(context);
              if (workspaceRoute != null) {
                Navigator.of(context)
                    .popUntil((route) => identical(route, workspaceRoute));
              }
              _openEntry(entry, pageContext: pageContext);
              return true;
            }
          }
        }
        final child = UiPackScope(
          moduleId: page.moduleId,
          child: UiPageHost(
            registry: widget.registry,
            pageId: pageId,
            pageContext: PageContext(values: values),
          ),
        );
        if (method == 'ui.panel') {
          final presentation = object(args['presentation'] ?? {});
          final adaptive = presentation['adaptive'] == true;
          final centered = presentation['wide'] == 'center';
          if (adaptive && centered && MediaQuery.sizeOf(context).width >= 820) {
            unawaited(
              showDialog<void>(
                context: context,
                builder: (panelContext) => Dialog(
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 560,
                    height: MediaQuery.sizeOf(panelContext).height * .85,
                    child: ModuleDetailPage(
                      registry: widget.registry,
                      pageId: pageId,
                      pageContext: PageContext(values: values),
                      title: page.title,
                      panel: true,
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          } else if (adaptive && MediaQuery.sizeOf(context).width >= 820) {
            unawaited(
              showGeneralDialog<void>(
                context: context,
                barrierDismissible: true,
                barrierLabel: '关闭面板',
                pageBuilder: (panelContext, _, _) => SafeArea(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 480,
                      child: Material(
                        elevation: 16,
                        color: Theme.of(context).colorScheme.surface,
                        child: ModuleDetailPage(
                          registry: widget.registry,
                          pageId: pageId,
                          pageContext: PageContext(values: values),
                          title: page.title,
                          panel: true,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          } else {
            final requestedHeight = presentation['heightFactor'];
            final heightFactor =
                requestedHeight is num && requestedHeight.isFinite
                ? requestedHeight.toDouble().clamp(.5, .95)
                : .9;
            unawaited(
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: adaptive,
                builder: (panelContext) => AnimatedPadding(
                  duration: AppMotion.duration(
                    panelContext,
                    const Duration(milliseconds: 180),
                  ),
                  curve: AppMotion.enter,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(panelContext).bottom,
                  ),
                  child: FractionallySizedBox(
                    heightFactor: heightFactor,
                    child: ModuleDetailPage(
                      registry: widget.registry,
                      pageId: pageId,
                      pageContext: PageContext(values: values),
                      title: page.title,
                      panel: true,
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          }
        } else {
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => UiPackScope(
                  moduleId: page.moduleId,
                  child: ModuleDetailPage(
                    registry: widget.registry,
                    pageId: pageId,
                    pageContext: PageContext(values: values),
                    title: page.title,
                    child: child,
                  ),
                ),
              ),
            ),
          );
        }
        return true;
      default:
        return platformBridge!.invoke(caller, method, args);
    }
  }
}
