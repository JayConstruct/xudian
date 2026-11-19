import '../../core/modules/app_module.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/ui/ui_registration.dart';
import '../../core/ui/ui_slot.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_page_host.dart';
import '../../core/modules/module_registry.dart';

import 'package:flutter/material.dart';

import 'ui_examples_page.dart';

class UiExamplesModule implements AppModule {
  UiExamplesModule({this.registry});

  final ModuleRegistry? registry;
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.ui.examples',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );

  @override
  List<UiRegistration> get ui => [
    WidgetRegistration(UiSlot.workspacePage, manifest.id, (_) => _gallery()),
    UiPageRegistration(
      id: 'app.ui.examples.page',
      moduleId: manifest.id,
      title: 'UI 示例',
      builder: (_, _) => _gallery(),
    ),
    const UiEntryRegistration(
      id: 'app.ui.examples.entry',
      moduleId: 'app.ui.examples',
      pageId: 'app.ui.examples.page',
      label: 'UI 示例',
      icon: Icons.widgets_outlined,
      opening: UiOpening.detail,
      defaultMount: UiMount(placement: UiPlacement.hidden),
    ),
    UiPageRegistration(
      id: 'app.ui.examples.composition',
      moduleId: manifest.id,
      title: '页面槽位示例',
      container: true,
      retainPosition: true,
      builder: (_, _) => const SizedBox.shrink(),
      slots: const [
        PageSlotDefinition(
          id: 'actions',
          label: '本模块入口',
          kind: PageSlotKind.entries,
        ),
        PageSlotDefinition(
          id: 'tabs',
          label: '公开页签',
          kind: PageSlotKind.tabs,
          isPublic: true,
        ),
        PageSlotDefinition(
          id: 'sections',
          label: '公开纵向内容',
          kind: PageSlotKind.sections,
          isPublic: true,
        ),
      ],
    ),
    const UiEntryRegistration(
      id: 'app.ui.examples.compositionEntry',
      moduleId: 'app.ui.examples',
      pageId: 'app.ui.examples.composition',
      label: '页面槽位示例',
      icon: Icons.account_tree_outlined,
      opening: UiOpening.detail,
      defaultMount: UiMount(placement: UiPlacement.hidden),
    ),
    UiPageRegistration(
      id: 'app.ui.examples.local',
      moduleId: manifest.id,
      title: '局部位置示例',
      retainPosition: true,
      builder: (_, _) => ListView(
        key: const PageStorageKey('local-example-list'),
        children: [
          const ListTile(title: Text('此页面声明保留滚动位置，仅当前运行期间有效')),
          for (var index = 0; index < 25; index++)
            ListTile(title: Text('演示条目 ${index + 1}')),
        ],
      ),
    ),
    const UiEntryRegistration(
      id: 'app.ui.examples.localEntry',
      moduleId: 'app.ui.examples',
      pageId: 'app.ui.examples.local',
      label: '本模块滚动示例',
      icon: Icons.list_alt,
      content: true,
      defaultMount: UiMount(
        placement: UiPlacement.page,
        pageId: 'app.ui.examples.composition',
        slotId: 'tabs',
      ),
    ),
  ];

  Widget _gallery() => UiExamplesPage(
    onOpenComposition: registry == null
        ? null
        : (context) {
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('页面槽位示例')),
                  body: UiPageHost(
                    registry: registry!,
                    pageId: 'app.ui.examples.composition',
                  ),
                ),
              ),
            );
          },
  );
}

class UiExampleContributionsModule implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.ui.contributions',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );

  @override
  List<UiRegistration> get ui => [
    UiPageRegistration(
      id: '${manifest.id}.info',
      moduleId: manifest.id,
      title: '跨模块贡献',
      builder: (_, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('此内容来自另一个模块，只申请 UI 注册权限，不读写真实业务数据。'),
        ),
      ),
    ),
    UiPageRegistration(
      id: '${manifest.id}.context',
      moduleId: manifest.id,
      title: '上下文示例',
      requiredContext: const ['projectId'],
      builder: (_, _) => const Center(child: Text('上下文已满足；此示例不读取项目内容。')),
    ),
    UiEntryRegistration(
      id: '${manifest.id}.tab',
      moduleId: manifest.id,
      pageId: '${manifest.id}.info',
      label: '跨模块页签',
      icon: Icons.extension_outlined,
      content: true,
      defaultMount: const UiMount(
        placement: UiPlacement.page,
        pageId: 'app.ui.examples.composition',
        slotId: 'tabs',
        order: 1,
      ),
    ),
    UiEntryRegistration(
      id: '${manifest.id}.section',
      moduleId: manifest.id,
      pageId: '${manifest.id}.info',
      label: '跨模块内容区',
      icon: Icons.extension_outlined,
      content: true,
      defaultMount: const UiMount(
        placement: UiPlacement.page,
        pageId: 'app.ui.examples.composition',
        slotId: 'sections',
      ),
    ),
    UiEntryRegistration(
      id: '${manifest.id}.invalid',
      moduleId: manifest.id,
      pageId: '${manifest.id}.context',
      label: '缺少上下文示例',
      icon: Icons.warning_amber_outlined,
      content: true,
      defaultMount: const UiMount(
        placement: UiPlacement.page,
        pageId: 'app.ui.examples.composition',
        slotId: 'tabs',
        order: 2,
      ),
    ),
  ];
}
