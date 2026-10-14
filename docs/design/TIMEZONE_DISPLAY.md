# 课表时区与显示诊断

2026-10-13 第三批实现，关联 UX-07 与 DISPLAY-01。当前能力与设备实测分别记录；不因诊断入口或模拟器测量完成就认定 ARM 显示比例问题已解决。

## 时区默认与保留规则

宿主 API 1.22 新增 `clock.systemTimezone()`，每次重新读取系统标识，验证为完整 IANA 数据库支持的时区，返回 `{zone,source}`。明确零时区别名规范为 `UTC`；读取失败、超时或非法名称返回 `{zone:'Asia/Shanghai',source:'fallback'}`，业务界面说明回退。不会依据当前数字偏移或歧义缩写猜测地区，也不更改系统时区。

| 流程 | 时区规则 |
| --- | --- |
| 新建课表、创建示例 | 使用系统时区；普通创建不要求填时区 |
| 已有课表 | 保留存储时区，出差或系统修改不自动改写 |
| 手动修改 | 课表设置 → 学期设置 → 高级设置；保留草稿并审核实际变更，冲突拒绝保存 |
| 拾光导入已有目标 | 保留目标课表时区 |
| 拾光导入新课表 | 优先保留来源明确的时区，否则采用系统时区 |
| JSON 课表备份 | 保留备份声明的时区，导出同样保留 |
| 课程查询、日程与规划 | 按课表本地日期／时刻转换，跨日与夏令时边界不静默移动 |

课表源码为 `app.schedule 1.13.0`，拾光为 `app.import.shiguang 1.6.0`，两者最低宿主 API `^1.22.0`。源码与本地 `dist/modules` 候选包已更新；预装清单没有新增这两项，已发布索引及历史包不改写。仅更新 APK 不会自动升级用户已安装的模块。

## 平台实现

Android 使用专用 `xudian.host/clock` 通道读取 `TimeZone.getDefault().id`。Windows 每次读取当前 Windows 时区键，再用系统 ICU 映射为 IANA；不使用进程缓存的 ICU 默认值。系统 ICU 缺失、映射失败或关闭动态夏令时而无法等价映射时返回缺失，由宿主明确回退。完整数据库保留 Android／ICU 可能返回的历史 IANA 别名。

Windows 实现依据为 [GetDynamicTimeZoneInformation](https://learn.microsoft.com/en-us/windows/win32/api/timezoneapi/nf-timezoneapi-getdynamictimezoneinformation)、[微软系统 ICU](https://learn.microsoft.com/en-us/windows/win32/intl/international-components-for-unicode--icu-) 与 [ICU 时区映射接口](https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/ucal_8h.html)。当前环境没有 Windows 编译器，构建和实际系统切换仍待 Windows 验证；Dart 通道测试不能替代原生运行。Android 后续已部署 release build117 到 ARM 真机与 x86_64 模拟器，原生时区分别实测为 `Asia/Shanghai` 与规范后的 `UTC`，详见下节。

## 显示与布局诊断

入口：“设置 → 辅助工具 → 显示与布局信息”。实时读取当前 `FlutterView` 像素尺寸／像素比，以及根 `MediaQuery` 逻辑视口、安全区、键盘遮挡与实际字号样本（12、14、24）。页面容器及内容可用宽度单独记录；平台视图像素尺寸不等同于面板硬件分辨率，`TextScaler` 样本不假定线性倍率。

只有用户主动点击才复制指标 JSON。数据使用字段白名单，不含任务、输入草稿、账户或密钥；不截图、上传或修改系统／应用显示设置。窗口、键盘、安全区与像素比变化时更新，使用当前视图而非默认的首个视图。

Android 只读系统测量工具：

```bash
source scripts/dev-env.sh
python3 scripts/module_host/measure_android_display.py \
  --serial DEVICE_SERIAL \
  --output dist/verification/display/device-display.json
```

支持 `--adb-host` 与 `--adb-port`，默认沿用 `XUDIAN_ADB_HOST`／`XUDIAN_ADB_PORT`。工具只读取 `wm size/density`、字体设置、平台信息和目标应用的 Android 配置；保留原始尺寸与覆盖值，计算结果明确标为估算，Flutter 视图实测需从应用诊断页获取。不写系统设置、不采集其他应用配置或界面正文。

## 当前测量与后续验收

2026-10-13 后续连接 ARM 真机，并将同签名 release build117 覆盖安装到两台设备；课表 1.13.0、拾光 1.6.0 的本地候选包已逐项审核并升级，业务数据未清除，发布索引保持原状态。系统与新诊断页的实际 Flutter 视图一致：

| 指标 | ARM64 真机（Android 15） | x86_64 模拟器（Android 17） |
| --- | --- | --- |
| 屏幕／Flutter View | 1080×2400 | 1080×2400 |
| 系统密度／实际像素比 | 480 DPI／3 | 420 DPI／2.625 |
| 实际逻辑视口 | 360×800 | 411.43×914.29 |
| 页面内容宽度 | 328 | 379.43 |
| 安全区上／下 | 31.67／16 | 24／24 |
| 默认系统字号／12、14、24 样本 | 1.0／12、14、24 | 1.0／12、14、24 |
| 系统时区／新建审核中的默认值 | Asia/Shanghai／Asia/Shanghai | GMT／UTC |

两台设备没有显示尺寸或密度覆盖。同一逻辑尺寸在真机上占用的物理像素比模拟器多约 14.29%，真机可用逻辑尺寸少 12.5%；这些设置能解释比例差异，不能归因于 ARM 架构。新建表单无需输入时区，冻结计划中默认值与原生通道结果一致；取消后课表数量及当前选择保留。

未发现根应用额外叠加显示或字号缩放：根 `MediaQuery.copyWith` 只合并减少动画设置，局部缩放属于底栏动画或面板／预览视口。诊断页默认字号样本也未出现额外放大。针对较小逻辑视口，商店去掉重复说明与四行筛选标签，改用两个可响应字号的下拉筛选；真机首卡从物理 y=1595 移到 y=803，即 531.67→267.67 逻辑像素，前移 264。

没有修改系统显示密度，也没有关闭应用文字缩放。模拟器临时字号 1.5 的实际非线性样本为 12→18、14→22、24→28，商店筛选、菜单、表单键盘及审核取消通过，最终恢复原 1.0。真机 ROM 拒绝 ADB 字号写入，原值复查保持 1.0，真机大字号仍待验收。真机长审核正文另发现内部文本滚动抢占外层手势，修复保留全文选择复制与外层弹性滚动。实际验收范围、对比设置恢复与剩余项目见 [真机验收](../VERIFICATION.md#2026-10-13-arm-真机显示与体验验收)；第三批未部署时的历史结果保留在 [第三批验证](../VERIFICATION.md#2026-10-13-系统时区与显示诊断第三批完善)。
