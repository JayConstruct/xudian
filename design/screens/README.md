# 页面稿

页面按 [设计清单](../PLAN.md)中的 UI 编号存放。从项目根目录开始某页设计：

```bash
python3 scripts/design_artifacts.py new ui-01 --brief 'UI-01 日程首页：本轮目标与状态'
```

脚本按需创建 `design/screens/ui-01/`。图片和完整同名提示词直接放该页目录，文件名使用完整批次前缀，例如 `<批次>-mobile-light-default-v01.png`。清单、参考和决策在 `.batches/<批次>/`，完成后运行 `index` 和 `check`。

页面原稿不提交 Git。本轮尚无页面批次，各页在实际设计时建立。
