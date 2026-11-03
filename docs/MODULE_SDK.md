# JavaScript 模块 SDK v1

当前宿主 API 为 `1.45.0`。公共 UI 契约、声明式 UI 包和全局／模块选择见 [公共 UI 与界面包](UI_COMPONENTS.md)。

新增模块使用 `formatVersion: 3`、`packageFormat: 2`，按所用能力声明最低 `hostApi`。组件/服务的 `@1` 主版本与宿主 API 版本分别管理，各专题完整契约保留兼容规则。

| 能力 | 最低宿主 API |
| --- | --- |
| 工作区顶栏、设置行、时间输入 | 1.2 |
| 滚动收起工具栏 | 1.3 |
| 内容延伸 / 悬浮面板 | 1.4 / 1.5 |
| 公共组件与无脚本 UI 包 | 1.6 |
| 日期、多选及组件示例 | 1.7 |
| Android 网页采集 | 1.8 |
| 详情标题与内部返回 | 1.9 |
| 数字网格选择 | 1.10 |
| 工作区助手、日期容器初始门控、概览日期控件开关 | 1.18 |
| 系统 IANA 时区读取 | 1.22 |
| 通用页面入场动画 | 1.32 |
| 页面前进／返回动画、固定预览审核 | 1.33 |
| 本地时间范围表格 | 1.34 |
| 原生单项命令确认、规划任务动作与完成状态 | 1.38 |
| 可选规划区块边缘／角标状态指示 | 1.40 |
| 取消状态外观与非占用区块 | 1.41 |
| 行内独立动作与共享图标 | 1.42 |
| 页面前进／返回、输入排队与草稿缓存 | 1.43 |
| 紧凑日程组件配置 | 1.44 |
| 通用内容卡片、徽标、图标、筛选与平面底栏配置 | 1.45 |

模块包目录示例：

```text
module.json
main.js
calendar.js
assets/...
```

模块清单中的 id 采用命名空间，版本为语义版本（支持预发布/构建标识），`hostApi` 使用兼容版本范围（如 `"^1.0.0"`），`dataVersion` 为正整数。collections 声明本模块集合及 JSON Schema，services 声明版本化 query/command，pages 声明页面及入口。依赖可声明模块 ID，或 `{moduleId,version}` 版本约束；宿主更新会检查依赖范围与服务主版本。完整示例见 `packages/modules/app.schedule/module.json`。

```javascript
import {data, services, ui, ids, clock} from '@xudian/sdk';

export async function create({title}) {
  const id = await ids.new();
  return {
    writes: [{collection: 'items', id, value: {id, title}}],
    events: [{type: 'item.created', entity: {moduleId: 'private.example', collection: 'items', id}}],
    result: {id},
  };
}

export async function render({state = {}, event, formValues}) {
  if (event?.type === 'create') {
    const plan = await services.prepare(
      {moduleId: 'private.example', serviceId: 'items.create', majorVersion: 1},
      {title: formValues.title},
    );
    if (await ui.review(plan.planId)) await services.commit(plan.planId);
  }
  return {
    state,
    tree: {type: 'column', children: [
      {type: 'input', key: 'title', text: '标题'},
      {type: 'button', text: '创建', event: {type: 'create'}},
      ...(await data.query('items')).map(x => ({type: 'text', text: x.title})),
    ]},
  };
}
```

## 按功能查阅

| 主题 | 内容 |
| --- | --- |
| [数据、服务与模块生命周期](sdk/DATA_SERVICES.md) | 集合、跨模块服务、准备／提交、可选依赖、迁移与自动化 |
| [页面、表单与状态](sdk/PAGES.md) | 渲染返回值、表单绑定、稳定列表、过渡与输入状态 |
| [组件、顶栏与菜单](sdk/COMPONENTS.md) | 公共组件、选择控件、顶栏、菜单与紧凑显示 |
| [日程与日期上下文](sdk/DATE_CONTEXT.md) | 选中日期、内联作用域、概览、工作区助手与加载门控 |
| [导航、审核与原生命令确认](sdk/INTERACTION.md) | 导航、面板、计划审核、风险勾选和真实用户命令确认 |
| [网络、文件、时区与网页采集](sdk/PLATFORM.md) | 网络／凭据、用户文件、系统时区、纯转换及教务浏览器 |
| [规划看板与时间轴](sdk/PLANNER.md) | 真实时间几何、拖动预览、快速调整、动态日期和区块状态 |

## 能力索引

以下入口保留旧 SDK 的章节锚点，链接进入对应专题；API 数字表示能力引入版本，不是当前模块版本。

| 能力 | 专题 |
| --- | --- |
| <a id="数据和服务"></a>[数据和服务](sdk/DATA_SERVICES.md#数据和服务) | 数据、服务与模块生命周期 |
| <a id="升级"></a>[升级](sdk/DATA_SERVICES.md#升级) | 数据、服务与模块生命周期 |
| <a id="受保护宿主服务"></a>[受保护宿主服务](sdk/DATA_SERVICES.md#受保护宿主服务) | 数据、服务与模块生命周期 |
| <a id="配置导出声明"></a>[配置导出声明](sdk/DATA_SERVICES.md#配置导出声明) | 数据、服务与模块生命周期 |
| <a id="交互和外部操作"></a>[交互和外部操作](sdk/INTERACTION.md#交互和外部操作) | 导航、审核与原生命令确认 |
| <a id="页面"></a>[页面](sdk/PAGES.md#页面) | 页面、表单与状态 |
| <a id="api-119-的可折叠过渡"></a>[API 1.19 的可折叠过渡](sdk/PAGES.md#api-119-的可折叠过渡) | 页面、表单与状态 |
| <a id="api-120-的稳定列表与提交反馈"></a>[API 1.20 的稳定列表与提交反馈](sdk/PAGES.md#api-120-的稳定列表与提交反馈) | 页面、表单与状态 |
| <a id="api-12-的顶栏与设置组件"></a>[API 1.2 的顶栏与设置组件](sdk/COMPONENTS.md#api-12-的顶栏与设置组件) | 组件、顶栏与菜单 |
| <a id="api-130-的图标按钮与分级菜单"></a>[API 1.30 的图标按钮与分级菜单](sdk/COMPONENTS.md#api-130-的图标按钮与分级菜单) | 组件、顶栏与菜单 |
| <a id="api-13-的滚动工具栏"></a>[API 1.3 的滚动工具栏](sdk/COMPONENTS.md#api-13-的滚动工具栏) | 组件、顶栏与菜单 |
| <a id="api-14-的内容延伸与滚动余量"></a>[API 1.4 的内容延伸与滚动余量](sdk/COMPONENTS.md#api-14-的内容延伸与滚动余量) | 组件、顶栏与菜单 |
| <a id="api-17-的选择控件与组件示例"></a>[API 1.7 的选择控件与组件示例](sdk/COMPONENTS.md#api-17-的选择控件与组件示例) | 组件、顶栏与菜单 |
| <a id="api-19-的模块详情导航"></a>[API 1.9 的模块详情导航](sdk/COMPONENTS.md#api-19-的模块详情导航) | 组件、顶栏与菜单 |
| <a id="api-110-的数字网格选择"></a>[API 1.10 的数字网格选择](sdk/COMPONENTS.md#api-110-的数字网格选择) | 组件、顶栏与菜单 |
| <a id="api-112-的-ui-偏好提示和过渡动画"></a>[API 1.12 的 UI 偏好、提示和过渡动画](sdk/COMPONENTS.md#api-112-的-ui-偏好提示和过渡动画) | 组件、顶栏与菜单 |
| <a id="已注册-ui-组件示例api-112"></a>[已注册 UI 组件示例（API 1.12）](sdk/COMPONENTS.md#已注册-ui-组件示例api-112) | 组件、顶栏与菜单 |
| <a id="可复制的调用方式弹窗api-113"></a>[可复制的调用方式弹窗（API 1.13）](sdk/COMPONENTS.md#可复制的调用方式弹窗api-113) | 组件、顶栏与菜单 |
| <a id="api-115-的原生公共-ui"></a>[API 1.15 的原生公共 UI](sdk/COMPONENTS.md#api-115-的原生公共-ui) | 组件、顶栏与菜单 |
| <a id="api-114-的日程与待办呈现"></a>[API 1.14 的日程与待办呈现](sdk/DATE_CONTEXT.md#api-114-的日程与待办呈现) | 日程与日期上下文 |
| <a id="api-116-的每日日期上下文"></a>[API 1.16 的每日日期上下文](sdk/DATE_CONTEXT.md#api-116-的每日日期上下文) | 日程与日期上下文 |
| <a id="api-117-的日期顶栏"></a>[API 1.17 的日期顶栏](sdk/DATE_CONTEXT.md#api-117-的日期顶栏) | 日程与日期上下文 |
| <a id="api-118-的工作区助手与日程加载"></a>[API 1.18 的工作区助手与日程加载](sdk/DATE_CONTEXT.md#api-118-的工作区助手与日程加载) | 日程与日期上下文 |
| <a id="工作区助手入口"></a>[工作区助手入口](sdk/DATE_CONTEXT.md#工作区助手入口) | 日程与日期上下文 |
| <a id="日期容器的初始上下文"></a>[日期容器的初始上下文](sdk/DATE_CONTEXT.md#日期容器的初始上下文) | 日程与日期上下文 |
| <a id="五日概览与待办统计"></a>[五日概览与待办统计](sdk/DATE_CONTEXT.md#五日概览与待办统计) | 日程与日期上下文 |
| <a id="api-18-的通用网页采集"></a>[API 1.8 的通用网页采集](sdk/PLATFORM.md#api-18-的通用网页采集) | 网络、文件、时区与网页采集 |
| <a id="api-121-的纯时区转换与可选查询"></a>[API 1.21 的纯时区转换与可选查询](sdk/PLATFORM.md#api-121-的纯时区转换与可选查询) | 网络、文件、时区与网页采集 |
| <a id="api-124-规划交互原型"></a>[API 1.24 规划交互原型](sdk/PLANNER.md#api-124-规划交互原型) | 规划看板与时间轴 |
| <a id="api-125-规划拖动预览与时长调整"></a>[API 1.25 规划拖动预览与时长调整](sdk/PLANNER.md#api-125-规划拖动预览与时长调整) | 规划看板与时间轴 |
| <a id="规划模块13候选分页与移动时长"></a>[规划模块1.3：候选分页与移动时长](sdk/PLANNER.md#规划模块13候选分页与移动时长) | 规划看板与时间轴 |
| <a id="api-135-连续日期与紧凑规划界面"></a>[API 1.35 连续日期与紧凑规划界面](sdk/PLANNER.md#api-135-连续日期与紧凑规划界面) | 规划看板与时间轴 |
| <a id="api-136-动态日期窗口"></a>[API 1.36 动态日期窗口](sdk/PLANNER.md#api-136-动态日期窗口) | 规划看板与时间轴 |
