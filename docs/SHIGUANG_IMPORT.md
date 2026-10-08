# 拾光正方导入兼容模块

`app.import.shiguang` 1.1.0 是独立兼容模块，提供拾光桥接编译、数据转换和配置／预览流程。原入口仍默认复用拾光适配仓库的「正方教务html通用获取」脚本，不匹配学校。新增 `app.import.zhengfang` 1.0.0 演示解析器独立成模块，通过公共接口接入。客户端宿主 API 1.8.0 提供通用网页采集能力；课表 1.6.1 提供只读课表列表服务，数据版本仍为1，更新不修改已有课程和作息。

安装顺序：更新客户端 → 导入 [课表包](../dist/modules/app.schedule.xmodule) → 导入 [兼容包](../dist/modules/app.import.shiguang.xmodule)。兼容模块不会默认安装。入口位于宿主设置的「拾光教务导入」，以及「课表设置 → 导入与备份」的教务导入槽位。

已有 build34 客户端和课表1.6.1时，只需更新兼容包至1.1.0，再按需导入 [正方通用适配包](../dist/modules/app.import.zhengfang.xmodule)。新入口为「正方教务导入（通用）」。学校模块只携带解析脚本和入口，调用兼容模块的公共服务；取消采集不会打开配置，采集成功后进入兼容模块选择课表并确认学期，最终仍由课表预览确认保存。接入协议和其他学校模块的制作方式见 [SHIGUANG_ADAPTER_API.md](SHIGUANG_ADAPTER_API.md)。这并不保证拾光所有学校脚本都可运行；目前支持下述桥接子集及课程模型，特殊作息仍明确拒绝。

客户端交付为 [build34 Release APK](../client/build/app/outputs/flutter-apk/app-release.apk)，包含 ARM64 与 x86_64 的 Flutter 和 QuickJS 引擎。交付摘要见 [shiguang-delivery.json](../dist/verification/shiguang-delivery.json)。

Android 中填写教务登录网址并打开教务浏览器，在网页内登录，进入个人课表查询，选择学年学期并查询，再点击「执行采集」。默认脚本要求页面有 jQuery，支持上游的表格／列表视图选择器，并不适用于所有版本的正方页面。采集后选择新建或已有课表，确认名称、来源标识、第一教学周周一、周数、时区及每周起始日。来源标识使用稳定的「学校/账号别名/学年学期」，不要包含密码；重复导入同一来源保持一致，不同账号或学期使用不同标识。

浏览器在应用内使用系统 Android WebView 内核，不会跳转到外部浏览器 App。工具栏使用独立的现代样式；网页内容由网站自身提供。域名解析遵循设备网络。主页面出现 DNS、连接、HTTP 或证书错误时显示明确原因并禁用采集，后续加载完成回调不会覆盖错误；修改网址或刷新成功后恢复采集。遇到 `ERR_NAME_NOT_RESOLVED`，先用普通 HTTPS 网站验证设备联网，再检查教务网址及校园网／学校 VPN 要求。

默认正方通用脚本只返回课程，没有作息和学期配置。新建时使用12节模板并在预览提示，第一周日期必须由用户填写；合并时优先使用目标课表的已有配置。请按学校实际作息确认和调整。学校脚本若调用 `savePresetTimeSlots`、`saveCourseConfig`，相应配置也会被采集。可粘贴完整拾光适配脚本替换默认脚本，脚本仅在当前运行会话保留。桌面端当前可用「导入拾光 JSON 文件」，内置教务浏览器仅实现 Android。

模块将 `name/day/startSection/endSection/weeks/teacher/position` 转为课程和周期安排，支持明确周次、单双周展开结果、多段安排、颜色、备注和学分。同一安排的重复周次片段合并；优先使用输入的 `courseSourceId` 和 `sourceId/id`。没有安排ID时按课程、星期、节次、教师和地点建立来源键，周次变化可合并，其他字段变化可能形成新安排，预览会说明此限制。默认标记为局部结果，只有用户明确确认全量课程后才允许来源替换删除缺失项；现有课表还会进行三方冲突处理。

桥接支持 `shiguangBridge` / `shiguangBridgePromise` 与旧的 `AndroidBridge` / `AndroidBridgePromise`，包括提示、输入、单选、课程、学期配置、作息和完成通知。保存类调用只暂存于网页运行会话，`notifyTaskCompletion` 后一次返回；保存调用失败或课程为空不会返回成功。关闭、导航、重新执行和模块停用使旧执行结果失效。结果不包含浏览器的 Cookie 或登录凭据；站点存储由 Android WebView 管理，不是课表的备份数据。

配置确认后先显示转换摘要，「预览实际变更」准备课表计划；存在冲突时先在兼容模块选择处理方式，再转交课表导入预览。最终写入由课表确认和宿主审核，兼容模块不能提交课表写集。取消采集或配置不写入正式数据。JSON 文件导入使用同一流程。

目前不支持拾光的自定义上课时刻和按日期变化的夏冬季组合作息，遇到这类数据明确拒绝转换。

上游脚本及接口参考版本、作者与许可见 [UPSTREAM.md](../packages/modules/app.import.shiguang/UPSTREAM.md) 和 [MIT 许可](../packages/modules/app.import.shiguang/THIRD_PARTY_LICENSE.txt)。脚本不会自动从远端更新，升级使用新的有版本模块包。

验证命令：

```bash
python3 scripts/module_host/build_packages.py
node --experimental-default-type=module scripts/module_host/shiguang_compat_test.mjs
source scripts/dev-env.sh
cd client
flutter test --no-pub test/shiguang_import_test.dart test/host_browser_test.dart test/schedule_import_test.dart test/host_ui_test.dart test/script_package_security_test.dart
flutter analyze --no-pub
```

8项 JavaScript 测试与26项 Flutter 测试通过，覆盖真实 QuickJS 转换、跨模块公共桥接调用、学校模块交接与取消、来源调用身份、课表接收计划、兼容模块不能提交、重复导入更新周次、未保存预览、非法输入与不支持的作息。Android debug x86_64 构建通过。模拟器复验工具为 `source scripts/dev-env.sh` 后运行 `python3 scripts/module_host/verify_shiguang_browser.py --install`，使用本地测试页面，不使用真实学校或账号，不保存采集课程。

Android x86_64 模拟器已验证默认上游脚本在本地测试课表的 DOM 解析、单周展开、桥接返回配置流程及取消操作；测试页面只实现解析器所需的 jQuery 调用，不代表真实学校页面。截图见 [浏览器](../dist/verification/android-shiguang-browser.png) 和 [采集后配置](../dist/verification/android-shiguang-captured-config.png)，记录见 [shiguang-browser.json](../dist/verification/shiguang-browser.json)。可追加 `--release` 在正式 APK 上复验。真实学校账号登录、ARM64 真机和 Windows 运行未验收。

build34 Release 已在同一模拟器复验：普通 HTTPS 网页 `https://example.com` 加载成功、网址输入保持原文、主页面 HTTP 404 和 `ERR_NAME_NOT_RESOLVED` 提示持续保留、失败页面禁用采集、后续成功加载恢复采集，并完成本地课表采集和取消。普通网页截图见 [public-page](../dist/verification/android-shiguang-browser-public-page.png)，错误截图见 [dns-error](../dist/verification/android-shiguang-browser-dns-error.png)。此次设备网络故障是模拟器 Wi-Fi 已开启但未连接；重新连接 AndroidWifi 后恢复域名解析。测试网络会对不存在的域名返回 fake-IP，故 DNS 错误用含空标签的 `xudian..invalid` 触发。复验命令：`python3 scripts/module_host/verify_shiguang_browser.py --install --release --public-url https://example.com`。
