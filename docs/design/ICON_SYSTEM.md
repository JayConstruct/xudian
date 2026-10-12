# 圆润线性图标

确认的效果图中的图标是图像生成模型绘制的视觉参考，并不来自可安装的图标包。应用使用自绘矢量路径复现这类风格：24 单位画布、圆头圆角、1.7 单位描边，在高对比度模式下加粗到 2.2。文字、背景、控件与图标分别遵循主题，图标不会影响按钮的可点击面积。

图标源为 `client/lib/app/app_icons.dart`。`AppIconPainter` 绘制实际路径，`AppIcon` 兼容现有 `IconData`，未映射的原生图标保留原有图形。业务界面使用 `UiIcon` 接入 `ui.icon@1`，选定 UI 包可覆盖图标呈现；UI 包内部的 icon primitive 使用原始绘制组件，避免递归调用。

模块直接使用命名的公共组件，无需引用字体编码：

```js
ui.component('ui.icon@1', {
  props: {name: 'calendar', size: 24, semanticLabel: '课表'}
});
```

| 场景 | 图标名称 |
| --- | --- |
| 页面入口 | `today`、`calendar`、`tasks`、`modules`、`folder`、`inbox` |
| 通用操作 | `add`、`close`、`more`、`search`、`edit`、`delete`、`copy`、`refresh` |
| 导航方向 | `left`、`right`、`up`、`down` |
| 内容与状态 | `info`、`warning`、`error`、`check`、`clock`、`school` |
| 设置与组织 | `settings`、`sliders`、`transfer`、`history`、`pin`、`unpin` |
| 工具与浮层 | `ai`、`link`、`code`、`play`、`pause`、`eye`、`download`、`upload` |

旧模块的 `list`、`projects`、`schedule`、`tune`、`importExport` 等名称继续支持。未提供名称时不绘制占位圆。UI 示例的“文字、图标与分割线”页面显示各场景的可调用名称。

新增图标应根据对应内容绘制，并加入同一命名词汇；保持边缘留白与统一描边，不把位图截图切片作为图标。测试检查小尺寸/大尺寸/高对比度的边界、主题和可访问标签、选中态布局，以及 UI 包替换图标后原按钮操作仍可执行。
