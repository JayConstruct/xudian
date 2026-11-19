part of 'module_catalog_page.dart';

typedef _CatalogDetailsAction = ({String id, bool install});

class _CatalogListingDetailsDialog extends StatelessWidget {
  const _CatalogListingDetailsDialog({
    required this.item,
    required this.index,
    required this.version,
  });

  final CatalogModule item;
  final ModuleVersionIndex index;
  final CatalogVersion version;

  @override
  Widget build(BuildContext context) => NativeUi(
    child: AlertDialog(
      title: Text(item.name),
      titlePadding: AppDesign.dialogTitlePadding,
      contentPadding: AppDesign.dialogContentPadding,
      actionsPadding: AppDesign.dialogActionsPadding,
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.description),
              const SizedBox(height: 12),
              SelectableText('模块 ID：${item.id}'),
              Text('版本：${version.version} · 可安装'),
              Text('作者：${item.author.isEmpty ? '作者未提供' : item.author}'),
              SelectableText('发布仓库：${item.repository}'),
              SelectableText('下载来源：${version.url}'),
              Text('宿主兼容性：${version.manifest['hostApi']}'),
              Text(
                '权限：${(version.manifest['permissions'] as List? ?? []).join('、')}',
              ),
              const Text('模块依赖（点击查看）'),
              for (final raw in version.manifest['dependencies'] as List? ?? [])
                NativeUi(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      raw is String ? raw : '${object(raw)['moduleId']}',
                    ),
                    subtitle: Text(
                      raw is String ? '任意兼容版本' : '${object(raw)['version']}',
                    ),
                    trailing: const UiIcon(Icons.chevron_right),
                    onTap: () => Navigator.pop<_CatalogDetailsAction>(context, (
                      id: raw is String
                          ? raw
                          : object(raw)['moduleId'] as String,
                      install: false,
                    )),
                  ),
                ),
              const Text('服务依赖（点击查看）'),
              for (final raw in manifestServiceRequirements(version.manifest))
                NativeUi(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${raw['moduleId']}'),
                    subtitle: Text(
                      '${raw['serviceId']} @ ${raw['majorVersion']} ${raw['kind'] ?? ''}',
                    ),
                    trailing: const UiIcon(Icons.chevron_right),
                    onTap: raw['moduleId'] == 'app.host'
                        ? () => showHostService(context, raw)
                        : () => Navigator.pop<_CatalogDetailsAction>(context, (
                            id: raw['moduleId'] as String,
                            install: false,
                          )),
                  ),
                ),
              Text(
                '历史版本：${index.versions.map((entry) => entry.version).join('、')}',
              ),
              const SizedBox(height: 12),
              const Text('安装前验证摘要、身份与包格式，并展示签名状态和完整依赖计划。'),
            ],
          ),
        ),
      ),
      actions: [
        NativeUi(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ),
        NativeUi(
          child: FilledButton(
            onPressed: () => Navigator.pop<_CatalogDetailsAction>(context, (
              id: item.id,
              install: true,
            )),
            child: const Text('解析依赖并安装'),
          ),
        ),
      ],
    ),
  );
}
