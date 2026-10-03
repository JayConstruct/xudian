import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_system.dart';
import '../../core/modules/app_module.dart';
import '../../core/modules/module_context.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/ui/app_destination.dart';
import '../../core/ui/ui_registration.dart';
import '../../data/app_database.dart';
import '../tasks/application/providers.dart';
import '../tasks/task_list_page.dart';
import '../tasks/quick_task_input.dart';

class ProjectsModule implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.views.projects',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['tasks.query', 'tasks.command', 'ui.registry'],
    permissions: ['tasks.read', 'tasks.write', 'ui.register'],
  );

  @override
  List<UiRegistration> get ui => [
    NavigationRegistration(
      AppDestination(
        id: 'projects',
        label: '项目',
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder,
        builder: (_) => const ProjectsPage(),
      ),
    ),
  ];
}

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  Project? selected;

  Future<void> _createProject() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateProjectDialog(),
    );
    if (name == null || name.isEmpty) return;
    final commands = await ref.read(commandBusProvider.future);
    await commands.execute(const ModuleContext.system(), 'project.create', {
      'name': name,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (selected case final project?) {
      return Column(
        children: [
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: Text(project.name),
            onTap: () => setState(() => selected = null),
          ),
          Expanded(
            child: WorkspaceContentInsets(
              bottom: 0,
              child: TaskListPage(
                emptyTitle: '这个项目还没有任务',
                emptySubtitle: '可以从底部输入栏添加任务。',
                projectId: project.id,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              WorkspaceContentInsets.bottomOf(context) + 12,
            ),
            child: FloatingSurface(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: QuickTaskInput(
                key: ValueKey(project.id),
                hintText: '添加到${project.name}…',
                defaults: {'projectId': project.id},
              ),
            ),
          ),
        ],
      );
    }

    final state = ref.watch(projectsProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('无法读取项目：$error')),
      data: (projects) {
        final active = projects.where((p) => p.archivedAt == null).toList();
        return Column(
          children: [
            SectionHeading(
              title: '${active.length} 个项目',
              action: FilledButton.tonalIcon(
                onPressed: _createProject,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('新建项目'),
              ),
            ),
            Expanded(
              child: active.isEmpty
                  ? const WorkspaceEmptyState(
                      icon: Icons.folder_open_rounded,
                      title: '还没有项目',
                      subtitle: '新建一个项目，把相关任务放在一起',
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        WorkspaceContentInsets.bottomOf(context) + 24,
                      ),
                      itemCount: active.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final project = active[index];
                        return Material(
                          color: Theme.of(context).colorScheme.surface,
                          shape: AppDesign.smoothShape(),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            shape: AppDesign.smoothShape(),
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(project.name),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() => selected = project),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建项目'),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 120,
      decoration: const InputDecoration(labelText: '项目名称'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('创建'),
      ),
    ],
  );
}
