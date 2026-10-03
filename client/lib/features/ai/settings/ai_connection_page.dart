import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_system.dart';
import '../../tasks/application/providers.dart';
import '../provider/openai_compatible_provider.dart';

class AiConnectionPage extends ConsumerStatefulWidget {
  const AiConnectionPage({super.key});

  @override
  ConsumerState<AiConnectionPage> createState() => _AiConnectionPageState();
}

class _AiConnectionPageState extends ConsumerState<AiConnectionPage> {
  final formKey = GlobalKey<FormState>();
  final endpoint = TextEditingController();
  final model = TextEditingController();
  final apiKey = TextEditingController();
  bool loading = true;
  bool saving = false;
  bool obscureKey = true;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final settings = await (await ref.read(aiSettingsStoreProvider.future))
          .load();
      final key = await ref.read(aiSecretStoreProvider).readApiKey();
      if (!mounted) return;
      endpoint.text = settings.endpoint;
      model.text = settings.model;
      apiKey.text = key ?? '';
    } catch (_) {
      if (mounted) loadError = '读取连接配置失败，请重试';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final settings = await ref.read(aiSettingsStoreProvider.future);
      final secrets = ref.read(aiSecretStoreProvider);
      if (apiKey.text.trim().isEmpty) {
        await secrets.deleteApiKey();
      } else {
        await secrets.writeApiKey(apiKey.text.trim());
      }
      await settings.save(
        endpoint: endpoint.text.trim(),
        model: model.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI 连接配置已保存')));
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    endpoint.dispose();
    model.dispose();
    apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DetailPage(
    title: 'AI 连接',
    child: loading
        ? const Center(child: CircularProgressIndicator())
        : loadError != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(loadError!),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          )
        : Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  '连接你使用的模型服务',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '支持 Chat Completions 兼容接口。地址与模型保存在本机，密钥保存在系统安全存储。',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppDesign.muted(context)),
                ),
                const SizedBox(height: 24),
                ContentSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: endpoint,
                        enabled: !saving,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '接口地址',
                          hintText: 'https://example.com/v1/chat/completions',
                        ),
                        validator: (value) {
                          final uri = Uri.tryParse(value?.trim() ?? '');
                          return uri != null &&
                                  OpenAiCompatibleProvider.acceptsEndpoint(uri)
                              ? null
                              : '请输入 HTTPS 接口地址；本机地址可使用 HTTP';
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: model,
                        enabled: !saving,
                        decoration: const InputDecoration(labelText: '模型名称'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入模型名称'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: apiKey,
                        enabled: !saving,
                        obscureText: obscureKey,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          helperText: '本机服务可留空；清空后保存会移除密钥',
                          helperMaxLines: 2,
                          suffixIcon: IconButton(
                            tooltip: obscureKey ? '显示密钥' : '隐藏密钥',
                            onPressed: () =>
                                setState(() => obscureKey = !obscureKey),
                            icon: Icon(
                              obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(saving ? '保存中…' : '保存连接配置'),
                ),
              ],
            ),
          ),
  );
}
