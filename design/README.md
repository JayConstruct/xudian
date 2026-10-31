# UI 设计入口

## 选稿与实现状态

继续现有 Flutter/Dart 宿主与 JavaScript/QuickJS 模块。唯一获选基准为 [C · 旧版视觉融合 v02](styles/20261030-013221-184495-c-legacy-fusion-v02.png)，其 [完整提示词](styles/20261030-013221-184495-c-legacy-fusion-v02.prompt.txt) 与 [选定批次](styles/.batches/20261030-013221-184495/README.md) 保留来源及摘要。

另有基于当前模拟器截图的 [现有 UI 融合修订 v02](styles/20261030-023219-917453-c-current-ui-fusion-v02.png)、[提示词](styles/20261030-023219-917453-c-current-ui-fusion-v02.prompt.txt) 和 [批次](styles/.batches/20261030-023219-917453/README.md)。修订稿未替代原获选基准；日程基础布局与相关操作已参考该修订实现并完成模拟器验证，见 [日程验证](../docs/verification/DAILY_FUSION_UI.md)。规划页及整套方案尚未完成，不能把局部验收当作整体实现。

页面编号、设计顺序和关键状态见 [UI 清单](PLAN.md)。本节维护选稿和实现范围，其他入口引用本节。

## 项目与设计目录

```text
client/                       现有 Flutter/Dart 宿主、平台工程与测试
packages/modules/             现有 JavaScript 功能模块及界面包
packages/schemas/             现行模块与页面契约
design/
├── README.md                 本入口
├── PLAN.md                   页面清单与设计顺序
├── styles/                   唯一方案原图及同名完整提示词
│   └── .batches/<批次>/      清单、来源与决策
└── screens/                  后续按页面编号保存细化稿
    └── ui-01/                实际开始该页设计时创建
        └── .batches/<批次>/  本轮来源与决策
```

运行源码保持原位；构建、打包和模拟器流程继续使用现有脚本。业务页面通过模块声明与宿主通用组件表达，边界见 [当前架构](../docs/DESIGN.md) 与 [模块 SDK](../docs/MODULE_SDK.md)。

## 唯一方案与来源

原图文件名：`20261030-013221-184495-c-legacy-fusion-v02.png`。批次清单已设为 `selected`，保留该原图，不另存选定副本。

批次中的旧版实际截图、主题与图标资料是选图的来源，不是其他候选方案。已删除候选的历史输入路径和摘要仅用于追溯，不表示文件仍存在。实现范围以本页“选稿与实现状态”和对应验收记录为准。

## 后续稿件

在该方案基础上细化页面时，图片直接放在 `design/screens/ui-XX/`，完整提示词与图片并列；先创建独立批次：

```bash
python3 scripts/design_artifacts.py new ui-01 --brief '基于已选融合 v02，细化日程首页与关键状态'
```

使用返回的完整批次编号作为文件名前缀，同轮修订递增 `v01`、`v02`，不覆盖原图。输入、来源与决策保存在该批次的 `references/`、`notes/`；清单记录实际工具和选择理由。完成后运行：

```bash
python3 scripts/design_artifacts.py index design/screens/ui-01/.batches/<实际批次>
python3 scripts/design_artifacts.py check design/screens/ui-01/.batches/<实际批次>
```

原图、提示词、批次为本机材料，不提交 Git；本入口、清单及顶层目录说明可以提交。历史 `dist/design/` 保留已有记录。完整规则见 [设计稿规范](../docs/DESIGN_ARTIFACTS.md)。
