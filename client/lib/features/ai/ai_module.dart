import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/declarative/package/module_install_provenance.dart';
import '../../core/modules/app_module.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/modules/module_registry.dart';
import '../../core/ui/ui_registration.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_slot.dart';
import '../../app/design_system.dart';
import '../declarative_runtime/declarative_runtime_controller.dart';
import '../tasks/application/providers.dart';
import 'proposal/module_proposal_coordinator.dart';
import 'proposal/module_proposal_service.dart';
import 'provider/openai_compatible_provider.dart';
import 'settings/ai_connection_page.dart';
import 'settings/ai_settings_store.dart';
import 'assistant_overlay.dart';
import 'assistant_panel.dart';
import 'assistant_runtime.dart';

class AiModule implements AppModule {
  AiModule({required this.registry});

  final ModuleRegistry registry;
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.ai',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry'],
    permissions: ['ui.register', 'tasks.read', 'tasks.write'],
  );

  @override
  List<UiRegistration> get ui => [
    WidgetRegistration(
      UiSlot.globalOverlay,
      'app.ai.overlay',
      (_) => AssistantOverlay(
        registry: registry,
        developerBuilder: (_) => AiModuleDeveloperPanel(registry: registry),
      ),
    ),
    UiPageRegistration(
      id: 'app.ai.page',
      moduleId: manifest.id,
      title: 'AI 助手',
      builder: (_, _) => AiWorkspacePanel(registry: registry),
    ),
    UiEntryRegistration(
      id: 'app.ai.entry',
      moduleId: manifest.id,
      pageId: 'app.ai.page',
      label: 'AI 助手',
      icon: Icons.auto_awesome_outlined,
      opening: UiOpening.adaptivePanel,
      defaultMount: const UiMount(placement: UiPlacement.header),
    ),
  ];
}

class AiWorkspacePanel extends StatelessWidget {
  const AiWorkspacePanel({super.key, required this.registry});

  final ModuleRegistry registry;

  @override
  Widget build(BuildContext context) => AssistantPanel(
    registry: registry,
    developerBuilder: (_) => AiModuleDeveloperPanel(registry: registry),
  );
}

class AiModuleDeveloperPanel extends ConsumerStatefulWidget {
  const AiModuleDeveloperPanel({super.key, required this.registry});

  final ModuleRegistry registry;

  @override
  ConsumerState<AiModuleDeveloperPanel> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiModuleDeveloperPanel> {
  AiSettings connection = const AiSettings(endpoint: '', model: '');
  String apiKey = '';
  final requestController = TextEditingController();
  final jsonController = TextEditingController();
  bool applying = false;
  bool showAdvanced = false;
  bool loadingSettings = true;
  AiRequestCancellation? pendingRequest;
  late final AssistantController assistant;
  late int cancellationVersion;

  bool get available => mounted && widget.registry.isEnabled('app.ai');

  @override
  void initState() {
    super.initState();
    assistant = ref.read(assistantControllerProvider(widget.registry));
    cancellationVersion = assistant.cancellationVersion;
    assistant.addListener(_assistantChanged);
    widget.registry.addListener(_registryChanged);
    _loadSettings();
  }

  void _registryChanged() {
    if (!widget.registry.isEnabled('app.ai')) pendingRequest?.cancel();
    if (mounted) setState(() {});
  }

  void _assistantChanged() {
    if (assistant.cancellationVersion != cancellationVersion) {
      cancellationVersion = assistant.cancellationVersion;
      pendingRequest?.cancel();
    }
  }

  Future<void> _loadSettings() async {
    if (mounted) setState(() => loadingSettings = true);
    try {
      final settings = await ref.read(aiSettingsStoreProvider.future);
      final loaded = await settings.load();
      final loadedKey = await ref.read(aiSecretStoreProvider).readApiKey();
      if (!mounted) return;
      connection = loaded;
      apiKey = loadedKey ?? '';
    } catch (_) {
      _message('读取 AI 连接配置失败，请在设置中重试');
    } finally {
      if (mounted) setState(() => loadingSettings = false);
    }
  }

  Future<void> _openConnection() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AiConnectionPage()),
    );
    if (mounted) await _loadSettings();
  }

  @override
  void dispose() {
    assistant.removeListener(_assistantChanged);
    widget.registry.removeListener(_registryChanged);
    pendingRequest?.cancel();
    requestController.dispose();
    jsonController.dispose();
    super.dispose();
  }

  Future<ModuleProposalService> _proposalService() async {
    final store = await ref.read(declarativeModuleStoreProvider.future);
    final runtime = DeclarativeRuntimeController(
      store: store,
      registry: widget.registry,
      ruleEngine: await ref.read(ruleEngineProvider.future),
      templateEngine: await ref.read(templateEngineProvider.future),
    );
    return ModuleProposalService(
      store: store,
      registry: widget.registry,
      runtime: runtime,
    );
  }

  Future<void> _generateAndReview() async {
    if (applying || !available) return;
    final endpoint = Uri.tryParse(connection.endpoint);
    if (endpoint == null ||
        !OpenAiCompatibleProvider.acceptsEndpoint(endpoint)) {
      _message('请先配置 AI 连接');
      await _openConnection();
      return;
    }

    setState(() => applying = true);
    final cancellation = AiRequestCancellation();
    pendingRequest = cancellation;
    try {
      final store = await ref.read(declarativeModuleStoreProvider.future);
      final installed = await store.listInstalled();
      if (!mounted || !available || cancellation.cancelled) return;
      final source = await const OpenAiCompatibleProvider().generateModule(
        endpoint: endpoint,
        model: connection.model,
        apiKey: apiKey,
        request: requestController.text,
        installedModules: [
          for (final item in installed)
            if (item.installed) '${item.id}@${item.version}',
        ],
        cancellation: cancellation,
      );
      if (!mounted || !available || cancellation.cancelled) return;
      jsonController.text = const JsonEncoder.withIndent('  ').convert(source);

      final service = await _proposalService();
      if (!mounted || !available || cancellation.cancelled) return;
      final applied = await ModuleProposalCoordinator(service).reviewAndApply(
        context,
        source,
        provenance: const ModuleInstallProvenance.ai(),
        canApply: () => available && !cancellation.cancelled,
      );
      if (applied && mounted) {
        requestController.clear();
        _message('AI 生成的模块已应用');
      }
    } catch (error) {
      if (!cancellation.cancelled) _message('AI 提案失败：$error');
    } finally {
      if (identical(pendingRequest, cancellation)) pendingRequest = null;
      if (mounted) setState(() => applying = false);
    }
  }

  Future<void> _reviewJson() async {
    if (applying || !available) return;
    Map<String, Object?> source;
    try {
      final decoded = jsonDecode(jsonController.text);
      if (decoded is! Map) {
        throw const FormatException('提案必须是 JSON 对象');
      }
      source = decoded.map((key, value) => MapEntry('$key', value));
    } catch (error) {
      _message('JSON 无法解析：$error');
      return;
    }

    setState(() => applying = true);
    final cancellation = AiRequestCancellation();
    pendingRequest = cancellation;
    try {
      final service = await _proposalService();
      if (!mounted || !available || cancellation.cancelled) return;
      final applied = await ModuleProposalCoordinator(service).reviewAndApply(
        context,
        source,
        provenance: const ModuleInstallProvenance.ai(),
        canApply: () => available && !cancellation.cancelled,
      );
      if (applied && mounted) {
        _message('模块已应用');
      }
    } catch (error) {
      _message('提案失败：$error');
    } finally {
      if (identical(pendingRequest, cancellation)) pendingRequest = null;
      if (mounted) setState(() => applying = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    if (!available) {
      return const WorkspaceEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: 'AI 助手已关闭',
        subtitle: '可在模块管理中重新开启，连接配置已保留',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Text('AI 模块生成', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '生成任务视图、自定义字段、任务模板和自动化规则',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppDesign.muted(context)),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: requestController,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: '你想添加什么功能？',
            alignLabelWithHint: true,
            hintText:
                '例如：增加一个考试管理功能，记录科目、考试日期和难度，'
                '并显示未完成的考试任务。',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: applying || loadingSettings ? null : _generateAndReview,
            icon: applying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: const Text('生成并查看变更'),
          ),
        ),
        const SizedBox(height: 16),
        ContentSurface(
          child: ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('模型连接'),
            subtitle: Text(
              loadingSettings
                  ? '读取配置…'
                  : connection.model.isEmpty
                  ? '先连接模型服务，再生成模块'
                  : connection.model,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: applying || loadingSettings ? null : _openConnection,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '生成时会向你配置的模型服务发送功能描述和已安装模块的标识、版本；'
          '确认变更后才会安装或更新模块。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppDesign.muted(context)),
        ),
        const SizedBox(height: 12),
        Card(
          child: ExpansionTile(
            initiallyExpanded: showAdvanced,
            onExpansionChanged: (value) {
              setState(() => showAdvanced = value);
            },
            title: const Text('高级：直接编辑模块 JSON'),
            subtitle: const Text('模型输出也会同步显示在这里'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: jsonController,
                      minLines: 10,
                      maxLines: 24,
                      decoration: const InputDecoration(
                        labelText: '模块提案 JSON',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: applying ? null : _reviewJson,
                        icon: const Icon(Icons.rate_review_outlined),
                        label: const Text('查看 JSON 变更'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
