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
          '确认变更',
          details,
          moduleName: (id) => host?.instances[id]?.package.title ?? id,
          confirmation: rawConfirmation == null
              ? null
              : PlanConfirmation.parse(rawConfirmation),
        );
      case 'packages.review':
        return reviewDialog(
          context,
          '审核模块文件、数据、界面和权限',
          args,
          packageReview: true,
        );
      case 'grants.request':
        final directory = (host?.directoryServices() ?? []).map(object);
        final names = <String, String>{
          for (final service in directory)
            '${service['moduleId']}/${service['id']}@${service['major']}':
                (service['tool'] as Map?)?['description'] as String? ??
                service['description'] as String? ??
                service['id'] as String,
        };
        return showServiceGrantReview(
          context,
          moduleId: caller.moduleId,
          moduleName:
              host?.instances[caller.moduleId]?.package.title ??
              caller.moduleId,
          scopes: (args['scopes'] as List).cast<String>(),
          names: names,
          minutes: args['minutes'] as int,
          limit: args['writeLimit'] as int,
        );
      case 'browser.capture':
        return platformBridge!.invoke(
          caller,
          method,
          args,
          browserTheme: Theme.of(context),
        );
      case 'ui.dialog':
        Widget form(BuildContext context) => UiPackScope(
          moduleId: caller.moduleId,
          child: HostFormDialog(
            title: args['title'] as String? ?? '模块输入',
            description: args['description'] as String?,
            submitLabel: args['submitLabel'] as String? ?? '继续',
            presentation: args['presentation'] as String?,
            fullWidthActions: args['fullWidthActions'] == true,
            fields: [for (final f in args['fields'] as List? ?? []) object(f)],
          ),
        );
        if (args['presentation'] == 'sheet') {
          if (args['fullWidthActions'] == true) {
            return showSettingsModal<Map<String, Object?>>(
              context: context,
              compactFrame: true,
              builder: form,
            );
          }
          return showModalBottomSheet<Map<String, Object?>>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            useSafeArea: true,
            builder: form,
          );
        }
        return showDialog<Map<String, Object?>>(
          context: context,
          useSafeArea: args['presentation'] != 'page',
          barrierColor: args['presentation'] == 'compact'
              ? args['fullWidthActions'] == true
                    ? Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: .34)
                    : Theme.of(context).colorScheme.scrim.withValues(alpha: .4)
              : null,
          animationStyle: args['presentation'] == 'compact'
              ? AppMotion.dialogStyle(context)
              : null,
          builder: form,
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
                barrierColor: Theme.of(context).colorScheme.scrim
                    .withValues(alpha: .33),
                pageBuilder: (panelContext, _, _) {
                  final surface = Theme.of(panelContext)
                      .scaffoldBackgroundColor;
                  return Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 480,
                      height: double.infinity,
                      child: Material(
                        elevation: 12,
                        color: surface,
                        child: SafeArea(
                          bottom: false,
                          child: ModuleDetailPage(
                            registry: widget.registry,
                            pageId: pageId,
                            pageContext: PageContext(values: values),
                            title: page.title,
                            panel: true,
                            panelColor: surface,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          } else {
            final requestedHeight = presentation['heightFactor'];
            final heightFactor =
                requestedHeight is num && requestedHeight.isFinite
                ? requestedHeight.toDouble().clamp(.5, .95)
                : adaptive
                ? .922
                : .9;
            Widget panelBody(BuildContext panelContext) => AnimatedPadding(
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
                  panelColor: adaptive
                      ? AppDesign.modalSurface(Theme.of(panelContext))
                      : null,
                  child: child,
                ),
              ),
            );
            unawaited(
              adaptive
                  ? showSettingsModal<void>(
                      context: context,
                      compactFrame: true,
                      builder: panelBody,
                    )
                  : showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: false,
                      builder: panelBody,
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
