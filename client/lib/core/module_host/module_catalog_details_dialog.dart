part of 'module_catalog_page.dart';

typedef _CatalogDetailsAction = ({String id, bool install});

class _CatalogListingDetailsDialog extends StatelessWidget {
  const _CatalogListingDetailsDialog({
    required this.item,
    required this.index,
    required this.version,
    required this.icon,
  });

  final CatalogModule item;
  final ModuleVersionIndex index;
  final CatalogVersion version;
  final IconData icon;

  Widget _field(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 27),
      child: Row(
        children: [
          Flexible(flex: 1, child: Text(label)),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: AppDesign.muted(context)),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dependencies = version.manifest['dependencies'] as List? ?? [];
    final services = manifestServiceRequirements(version.manifest);
    final permissions = version.manifest['permissions'] as List? ?? [];
    return SettingsSheet(
      title: const Text('模块详情'),
      expandedActions: true,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 17,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 45,
                        height: 45,
                        decoration: ShapeDecoration(
                          color: colors.primaryContainer,
                          shape: AppDesign.smoothShape(radius: 14),
                        ),
                        alignment: Alignment.center,
                        child: UiIcon(icon, size: 24, color: colors.primary),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item.category} · ${item.author.isEmpty ? '作者未提供' : item.author}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: '模块信息',
              dividerIndent: 15,
              children: [
                _field(context, '版本', version.version),
                _field(context, '模块 ID', item.id),
                _field(context, '宿主兼容', '${version.manifest['hostApi']}'),
                _field(context, '发布仓库', item.repository),
              ],
            ),
            SettingsGroup(
              title: '安装前核对',
              dividerIndent: 15,
              children: [
                _field(
                  context,
                  '权限',
                  permissions.isEmpty ? '无需权限' : permissions.join('\n'),
                ),
                if (dependencies.isEmpty)
                  _field(context, '模块依赖', '无')
                else
                  ExpansionTile(
                    title: const Text('模块依赖'),
                    subtitle: Text('${dependencies.length} 项'),
                    children: [
                      for (final raw in dependencies)
                        SettingsEntry(
                          title: raw is String
                              ? raw
                              : '${object(raw)['moduleId']}',
                          subtitle: raw is String
                              ? '任意兼容版本'
                              : '${object(raw)['version']}',
                          icon: Icons.extension_outlined,
                          onTap: () => _openDependency(
                            context,
                            raw is String
                                ? raw
                                : object(raw)['moduleId'] as String,
                          ),
                        ),
                    ],
                  ),
                if (services.isEmpty)
                  _field(context, '服务依赖', '无')
                else
                  ExpansionTile(
                    title: const Text('服务依赖'),
                    subtitle: Text('${services.length} 项'),
                    children: [
                      for (final service in services)
                        SettingsEntry(
                          title: '${service['moduleId']}',
                          subtitle:
                              '${service['serviceId']} @ ${service['majorVersion']} ${service['kind'] ?? ''}',
                          icon: Icons.link,
                          onTap: service['moduleId'] == 'app.host'
                              ? () => showHostService(
                                  context,
                                  service,
                                  useGlobalStyle: true,
                                )
                              : () => _openDependency(
                                  context,
                                  service['moduleId'] as String,
                                ),
                        ),
                    ],
                  ),
                ExpansionTile(
                  leading: const SettingsGlyph(Icons.link),
                  minTileHeight: 55,
                  title: const Text('下载来源'),
                  childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(version.url.toString()),
                    const SizedBox(height: 8),
                    Text(
                      '历史版本：${index.versions.map((entry) => entry.version).join('、')}',
                    ),
                  ],
                ),
              ],
            ),
            const SettingsNote('下一步会核对包身份与依赖，并展示安装计划。'),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop<_CatalogDetailsAction>(context, (
            id: item.id,
            install: true,
          )),
          child: const Text('解析依赖并安装'),
        ),
      ],
    );
  }

  void _openDependency(BuildContext context, String id) {
    Navigator.pop<_CatalogDetailsAction>(context, (id: id, install: false));
  }
}
