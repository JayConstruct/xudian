# 公共 UI 与界面包

公共组件通过稳定契约与实现分离。业务页面负责数据、校验和操作；UI 包负责样式与声明式布局。最终控件由 Flutter 宿主渲染，UI 包不启动脚本线程。

## 选择与恢复

设置 → 外观与交互 → 界面风格支持全局选择和模块专属选择，分别展示“全局风格”“模块专属界面”和“保存与恢复”；完整分类见 [设置层级](SETTINGS_HIERARCHY.md)。模块管理可以筛选 UI 包并预览；安装不会自动切换风格。预览包含五类模板、标题与导航，全部使用模拟数据，支持窄／宽屏和浅／深色，退出不保存。

界面风格和预览页的选择框共用 `AppSelectField`：弹出列表使用 20px 连续圆角、选项使用 14px 连续圆角，当前选项显示浅色背景与勾选；长名称最多显示三行，菜单按可用宽度和屏幕高度限制大小。选择框仅用于选择，不弹出输入键盘；选择风格仍先修改草稿，点击保存后应用。布局选择弹窗的选项沿用相同的连续圆角。

配置保存在现有 `AppSettings` 的 `ui.selection`，无需数据库结构迁移：

```json
{"formatVersion":1,"globalPackId":"app.ui.default","modulePackIds":{"app.views.inbox":"example.ui.compact"}}
```

组件按模块选择、全局选择、内置默认的顺序解析；模块显式选择“内置默认”时使用默认组件与样式，不继承全局包。导航使用全局选择。停用、卸载或加载失败的包不删除选择，界面回退并标明不可用，重新启用后恢复。保存成功后才发布选择；草稿保存检查持久化基线，拒绝覆盖其他操作的新配置。

选择与恢复页固定使用默认 UI。恢复默认只清除界面选择，不卸载包或删除业务数据；审核与权限等宿主控制由内置界面呈现。

## 契约与接口

组件 ID 的 `@1` 表示契约主版本，与包版本独立。`ui.catalog()` 提供当前契约目录。

| 类别 | 契约 | 必须保留 |
| --- | --- | --- |
| 操作 | `ui.button@1` | `press` 事件 |
| 内容 | `ui.card@1`、`ui.list@1` | `content`、`items` 槽位 |
| 输入 | 文本、开关、选择、日期／时间等输入契约 | `control` 槽位，宿主持有输入状态 |
| 列表模板 | `ui.page.list@1` | `items` |
| 表单模板 | `ui.page.form@1` | `fields`、`actions` |
| 设置模板 | `ui.page.settings@1` | `sections` |
| 详情模板 | `ui.page.detail@1` | `content`、`actions` |
| 时间网格模板 | `ui.page.timeGrid@1` | `grid` |
| 底栏 | `ui.chrome.bottomNav@1` | `navigation`、`input`（无快捷输入时提供空槽位） |
| 侧栏 | `ui.chrome.sidebar@1` | `navigation` |
| 标题 | `ui.chrome.header@1` | `title`、`actions` |

Flutter 页面通过 `UiComponent(ref, fallback, props, slots, events)` 使用组件，`UiPackScope` 传递模块与选择上下文。fallback 提供稳定默认内容；slots 是宿主持有的 Widget，输入、焦点与业务状态不交给包。

工作区顶栏右侧的统一「页面菜单」由宿主在标题模板外绘制，包含页面操作、顶部模块入口、设置和界面风格与恢复。标题模板保留 `actions` 空槽位以兼容已有界面包，菜单不会被自定义顶栏隐藏或重复渲染。

统一菜单验证：124项菜单、顶栏、布局和课表回归测试通过，静态分析无问题；320／1280宽度及1.6倍字体覆盖全部模块入口与宿主设置访问。build35已在Android模拟器验证普通页面和课表共用单按钮、设置／界面恢复／AI模块入口及课表显示操作。记录见 [workspace-single-menu-install.json](../dist/verification/workspace-single-menu-install.json)，[课表菜单截图](../dist/verification/android-workspace-single-menu-schedule-open.png)。

脚本页面使用纯构造函数：

```js
ui.component('ui.button@1', {
  key: 'save',
  props: {label: '保存', disabled: false},
  events: {press: {type: 'save'}}
})
```

事件端口只转发调用方提供的操作，UI 包不能添加权限或修改原业务事件。旧节点通过兼容层继续进入公共组件，原字段与事件语义保持。

## 包格式与示例

仍使用 `.xmodule` ZIP、`packageFormat: 2`、`formatVersion: 3` 和现有摘要／来源审核。manifest 声明 `kind: "uiPack"`、`hostApi: "^1.6.0"`；`dataVersion` 为 1，permissions、collections、services、pages 为空，省略 entryPoint。旧包未声明 kind 时仍作为脚本模块。

`uiPack.contractVersion: 1` 定义 tokens、components、templates 和 chrome。light／dark tokens 支持 primary、surface、canvas、radius 和 spacing，缺失配置继承默认；颜色使用 `#RRGGBB` 或 `#AARRGGBB`。每个组件实现包含 tree，最小按钮替换：

```json
{
  "ui.button@1": {
    "tree": {
      "type":"primitive", "name":"button",
      "props": {
        "label":{"bind":["props","label"]},
        "disabled":{"bind":["props","disabled"]},
        "variant":"outlined"
      },
      "event":"press"
    }
  }
}
```

节点支持 base（完整内置实现）、slot、primitive、component、if、repeat 和 responsive。绑定只能读取 props、当前 item／index 和 environment。条件与响应分支必须保留必要槽位／事件；base 满足当前契约的全部要求。循环引用、不兼容契约、重复放置原生控件和超过 32 层的展开被拒绝。原生滚动槽位不能放入会使视口失去高度约束的滚动包装；纵向布局中的列表、网格和导航槽位由宿主分配剩余高度。

原子节点支持 column、row、wrap、card、text、button、icon、divider、spacer、padding、expanded、scroll、list。以当前目录与验证器为准，不能把任意 Flutter 控件名作为原子节点。

示例源码为 `packages/modules/example.ui.compact/module.json`，产物为 `dist/modules/example.ui.compact.xmodule`。它使用绿色浅／深色配置、紧凑间距、描边按钮，以及保留默认内容的模板与导航包装。导入后在“界面风格”预览并保存。

## 性能与验证

校验时编译声明树，宿主发布不可变注册表；组件渲染不重复读取 ZIP 或解析 JSON。高频输入、焦点、滚动、按压由宿主执行；包只转发业务事件。列表按需构建，模板保留宿主的滚动与尺寸处理。任务视图首批读取 50 项，通过“加载更多任务”扩大页面；数据服务对兼容的标量筛选、排序和分页使用绑定参数的 SQLite 查询，仅解析请求页记录。比较涉及混合类型、非 ASCII 排序、复杂值或暂存写集时保留原 Dart 语义；类型检查按集合修订号缓存。

页面记录实际读取的模块，忽略无关模块的数据变化；纯 UI 包安装和风格切换只重建呈现，不重新执行业务页面脚本。默认控件子树使用稳定身份保留文本、焦点、选择范围和滚动状态。

性能验收在相同设备、数据和操作下比较默认与示例包的帧耗时、掉帧、内存与切换耗时；使用 profile 构建分别检查 UI／绘制阶段。60Hz 帧预算约 16.7ms，120Hz 约 8.3ms。功能测试覆盖保存失败、并发修改、重启、缺失包回退、停用／更新、预览不写业务数据与输入／滚动状态保留。平台性能须分别测量，Linux 测试不能代替 Windows 或 Android 真机。

本轮实现、自动化结果和 Android 调试包见 [界面包验证记录](UI_PACK_VERIFICATION.md)。

## 公共输入控件与 UI 示例

宿主 API 1.7.0 补齐日期、时间、日期时间、日期范围、多选与数字输入，搜索模式复用 ui.input@1；新增 ui.dateRangeInput@1 和 ui.slider@1，均保留 control 槽位。已有 @1 契约的必需槽位与事件要求保持兼容；未提供新控件样式的 UI 包使用内置回退。

生产 UI 示例为 `packages/modules/app.ui.examples` 的 1.1.0 脚本包：17 张独立卡片、静态组件搜索、分类选中态、响应式单／双列、局部与全部重置、当前值和展开说明。分类栏横向滚动，避免窄屏大字下占满视口；内容区共用一个纵向滚动区域。所有示例使用本地模拟数据。宿主日期表单和脚本控件共用选择器；旧表单空日期保持空字符串。

值格式、事件和新节点见 [SDK API 1.7](MODULE_SDK.md#api-17-的选择控件与组件示例)。设计与实现边界见 [修改方案](UI_EXAMPLES_PLAN.md)。
