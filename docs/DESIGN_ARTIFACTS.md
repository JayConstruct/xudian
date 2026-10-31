# 设计稿存储规范

继续维护当前 Flutter/QuickJS 工程，UI 原稿使用浅层目录，`dist/design/` 保留历史。总入口见 [design/](../design/README.md)，逐页顺序见 [UI 清单](../design/PLAN.md)。当前唯一获选方案为 `design/styles/20261030-013221-184495-c-legacy-fusion-v02.png`，保留同名完整提示词及批次来源；获选不代表已实现或已通过设备验收。

## 新 UI 目录

| 内容 | 目录 |
| --- | --- |
| 风格原图和同名完整提示词 | `design/styles/`，图片直接放本层 |
| 风格批次元数据 | `design/styles/.batches/<批次>/` |
| 页面原图和同名完整提示词 | `design/screens/ui-XX/`，图片直接放该页目录 |
| 页面批次元数据 | `design/screens/ui-XX/.batches/<批次>/` |
| 需要随文档保存的获选副本 | `docs/design/selected/`，附来源、批次与摘要 |
| 运行截图、UI XML、录屏及测量记录 | `dist/verification/<专题>/<批次>/` |

开始风格或页面设计：

```bash
python3 scripts/design_artifacts.py new styles --brief '本轮需求与比较范围'
python3 scripts/design_artifacts.py new ui-01 --brief 'UI-01 日程首页：目标、关键状态与参考内容'
```

脚本以 Asia/Shanghai 时间创建 `.batches/<YYYYMMDD-HHMMSS-ffffff>/`，返回批次记录目录，不是图片目录。批次内包含 `README.md`、`manifest.json`、`references/` 和 `notes/`。README 显示原图目录和文件前缀。

## 文件命名与归属

```text
design/styles/
├── <批次>-style-a-v01.png
├── <批次>-style-a-v01.prompt.txt
├── <批次>-style-b-v01.png
├── <批次>-style-b-v01.prompt.txt
└── .batches/<批次>/
    ├── README.md
    ├── manifest.json
    ├── references/
    └── notes/
```

每轮需求新建批次，同轮修订递增 `v01`、`v02`。文件名使用完整批次编号作为前缀，后接小写英文、数字和短横线，例如 `<批次>-mobile-dark-keyboard-v02.png`。不用 final/latest 或覆盖同名文件区分稿件。脚本只索引本批次前缀的顶层文件及其参考/笔记，不扫描其他批次。

保留生成工具实际返回的原图，不以截图或联系表替代；提示词保存完整实际输入。工具先输出到工作区外时，交付前复制原图、提示词和来源，核对复制前后 SHA-256。衍生预览放批次 `notes/previews/` 并注明来源。

## 清单与校验

新布局使用 `schemaVersion: 2`、`layout: flat`，记录固定的 `artifactDirectory`、`filePrefix`、需求、工具、参考、状态及逐文件摘要；目录必须与主题对应，不接受任意路径、逃逸路径和符号链接。

- `brief`：本轮需求。
- `tool`：实际工具、模式和已知参数；未知模型如实标记。
- `references`：实际参考及来源，材料复制到本批次内；截图注明页面和采集时间。
- `selection`：未选定为 null；实际获选记录 `{source: '<原图文件名>', reason: '理由'}`，多张使用数组。
- `status`：draft 或 selected，须与选择记录一致。选定只引用原图，不另复制本机 selected/。

完成或修改后对实际批次运行：

```bash
python3 scripts/design_artifacts.py index design/styles/.batches/<实际批次>
python3 scripts/design_artifacts.py check design/styles/.batches/<实际批次>
```

页面使用其实际 `design/screens/ui-XX/.batches/<批次>/`。index 更新路径、字节数和 SHA-256，check 只读核对；索引前先确认变动符合预期。摘要只验证内容变化，不判断设计获选。

原图、提示词、参考和批次均留本机，不提交；design 的入口/清单与 styles/screens 顶层 README 可提交。检查器防止强制加入原稿。需要随文档保存的获选副本放 `docs/design/selected/`，附原路径、批次、摘要、理由与实现/验收状态。

## 历史、删除与验收

旧 `schemaVersion: 1` 的 `dist/design/<topic>/<batch>/` 继续支持 index/check，保留 references/drafts/selected/notes 和原清单；其他既有主题的 new 命令保持兼容。新 UI 统一用 styles 或 ui-01 至 ui-22，不再创建 app-ui-* 旧目录。

历史来源缺失标记未知。整理时记录原路径、新路径、SHA-256 并修复引用；用户明确要求删除时按准确范围删除，留下文件名、摘要和原因的精简记录，不保留被要求删除的图片副本。本次未采用的新版候选按用户要求删除，当前仅保留获选方案及其必要来源资料，无关历史稿保持原位。

参考使用合成内容或授权且必要的材料，不写入账号、密钥及私有数据。真实运行验收留在 dist/verification/，作为设计参考时仅复制必要材料。设计、原型、实现和设备验收分别记录，获选不代表已实现或通过验收。
