# UI 设计入口

日程基础布局采用[现有界面融合稿](styles/20261030-023219-917453-c-current-ui-fusion-v02.png)，批量任务管理采用[管理页选稿](screens/ui-04/20261103-162137-563384-batch-management-mobile-light-v02.png)。两处已有实现与模拟器验收。原稿和批次链接需要本机设计材料。

## 选稿与实现状态

整体视觉基准为[融合方案 v02](styles/20261030-013221-184495-c-legacy-fusion-v02.png)。选定原因与摘要见[批次清单](styles/.batches/20261030-013221-184495/README.md)，生成输入见[完整提示词](styles/20261030-013221-184495-c-legacy-fusion-v02.prompt.txt)。日程稿另有自己的[修订记录](styles/.batches/20261030-023219-917453/README.md)和[提示词](styles/20261030-023219-917453-c-current-ui-fusion-v02.prompt.txt)。

## 风格来源

今天页的低饱和画布、柔和表面、蓝紫强调色与圆润线性图标取自早期参考图。原图可在 Git 标签 `v0.2.0-beta.27` 的 `docs/design/soft-minimal-today-reference.png` 查阅，生成工具与提示词未知。

普通内容以标题、留白和细分隔线分组，时间网格和真实卡片保留自身结构；阴影与模糊集中用于浮层和导航。浅深色主题保持相同信息层级，界面包与用户配色继续生效。

底部导航的悬浮胶囊结构参考 FlClash v0.8.99，沿用序点配色和 [线性图标](../docs/ui/DESIGN_SYSTEM.md#圆润线性图标)。连续跟手、取消、减少动画及可访问激活由宿主负责，导航不能遮挡页面末尾操作。

## 稿件存储与校验

大幅新增或修改 UI 时，按[协作约定中的设计审核流程](../AGENTS.md#大幅新增或修改-ui)提交单界面图稿。将用户最终确认的各张图记录为本批次选稿，供实现和模拟器截图逐张对照。

临时比较配色、布局或交互时，把图片放在本机的 `design/styles/` 或对应的 `design/screens/ui-XX/`，用文件名说明用途，例如 `ui-04-keyboard-layout.png`。试稿可以直接修改或清理，无需建批次。

### 采用、交付或需要复现的稿件

选作实现依据、准备交付或明确要求复现时，为相关稿件建立批次。已知要复现的稿件从生成时保留原图、实际提示词和参考来源。试稿后来获选时，使用已有原始材料归档。原始输入已丢失的图片可作为视觉参考，注明已知来源和缺失信息。

在仓库根目录按稿件用途选择一条命令。

```bash
python3 scripts/design_artifacts.py new styles --brief '本轮需求与比较范围'
python3 scripts/design_artifacts.py new ui-01 --brief 'UI-01 日程首页：目标、关键状态与参考内容'
```

命令返回 `.batches/<批次>/` 目录。按其中 README 给出的前缀，将原图和同名 `.prompt.txt` 放在风格或页面目录下，例如 `<批次>-mobile-dark-keyboard-v01.png`。同一稿件的修订递增为 `v02`。从工作区外复制原图时核对源文件与副本的 SHA-256。

在 `manifest.json` 填写实际使用的工具和参考来源。参考材料放在批次的 `references/`，衍生预览放在 `notes/previews/`。获选时将 `status` 设为 `selected`，在 `selection` 记录原图文件名 `source` 和理由 `reason`，多张选稿使用数组。

归档完成或修订后，对同一批次先生成索引，再核对文件与摘要。页面稿使用对应的 `design/screens/ui-XX/.batches/<实际批次>`。

```bash
python3 scripts/design_artifacts.py index design/styles/.batches/<实际批次>
python3 scripts/design_artifacts.py check design/styles/.batches/<实际批次>
```

原图、提示词、参考材料与批次保存在本机。需要随文档提交的获选副本放在 `docs/design/selected/`，附来源、批次、摘要、选用理由和实现／验收状态。

### 历史、删除与验收

旧 `schemaVersion: 1` 的 `dist/design/<topic>/<batch>/` 继续支持 index/check，保留 references/drafts/selected/notes 和原清单；其他既有主题的 new 命令保持兼容。新 UI 统一用 styles 或 ui-01 至 ui-23，不再创建 app-ui-* 旧目录。

移动已归档稿件时，记录原路径、新路径与 SHA-256，并修复引用。按要求删除归档稿件时，记录文件名、摘要和删除原因。

参考使用合成内容或授权且必要的材料，排除账号、密钥及私有数据。获选稿的实现状态以代码为准，设备验收状态以 `dist/verification/` 的实测结果为准。
