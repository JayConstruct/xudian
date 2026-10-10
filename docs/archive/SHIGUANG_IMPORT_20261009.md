> 历史归档：保留当时的方案、状态与验证结果。当前文档见 [文档导航](../README.md)，历史构建和截图可能只存在于原验收工作区。

# 拾光学校导入兼容模块

`app.import.shiguang` 1.4.0 是独立兼容模块，提供学校搜索、拾光桥接编译、数据转换和配置／预览流程。内置拾光仓库247个学校／教务系统、269个适配项。首页分为按学校导入、通用系统导入、粘贴学校脚本、JSON文件导入、关于与致谢。学校搜索按学校合并显示，覆盖243所学校、265个适配入口；列表只显示校名、分类或入口数量。点开后查看使用说明、选择本科／研究生或校内／WebVPN入口、查看维护者及原始源码地址，并回填登录网址。4个通用系统独立展示：正方、青果、URP、超星；学校无搜索结果时可直接尝试通用脚本。关于与致谢展示上游适配仓库、拾光项目、序点源码地址、贡献者致谢及完整MIT许可，地址可长按复制。粘贴脚本、JSON导入和默认正方HTML通用脚本继续保留。原独立正方导入模块已移除，正方通用入口统一位于拾光模块的「通用系统导入」。客户端宿主 API 1.8.0 提供通用网页采集能力；课表 1.6.1 提供只读课表列表服务，数据版本仍为1，更新不修改已有课程和作息。

安装顺序：更新客户端 → 导入 [课表包](../../dist/modules/app.schedule.xmodule) → 导入 [兼容包](../../dist/modules/app.import.shiguang.xmodule)。兼容模块不会默认安装。入口位于宿主设置的「拾光教务导入」，以及「课表设置 → 导入与备份」的教务导入槽位。

1.4.0 需要先更新到 build37 客户端（宿主 API 1.9.0），再安装拾光兼容包；课表需1.6.1或更高版本。正方、青果、URP、超星均从「通用系统导入」选择，无需另装正方模块。其他学校模块的公共接入协议见 [SHIGUANG_ADAPTER_API.md](../SHIGUANG_ADAPTER_API.md)。特殊作息和真实学校页面仍需按说明核对。

当前客户端build36按ABI分别交付：[ARM64 APK](../../client/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk)、[x86_64 APK](../../client/build/app/outputs/flutter-apk/app-x86_64-release.apk)，包含对应ABI的Flutter与QuickJS引擎。修复仅升级依赖模块时复用依赖未激活的问题，完整最终图按依赖顺序启动；失败完整恢复原版本与数据。

Android 中填写教务登录网址并打开教务浏览器，在网页内登录，进入个人课表查询，选择学年学期并查询，再点击「执行采集」。默认脚本要求页面有 jQuery，支持上游的表格／列表视图选择器，并不适用于所有版本的正方页面。采集后选择新建或已有课表，确认名称、来源标识、第一教学周周一、周数、时区及每周起始日。来源标识使用稳定的「学校/账号别名/学年学期」，不要包含密码；重复导入同一来源保持一致，不同账号或学期使用不同标识。

浏览器在应用内使用系统 Android WebView 内核，不会跳转到外部浏览器 App。工具栏使用独立的现代样式；网页内容由网站自身提供。域名解析遵循设备网络。主页面出现 DNS、连接、HTTP 或证书错误时显示明确原因并禁用采集，后续加载完成回调不会覆盖错误；修改网址或刷新成功后恢复采集。遇到 `ERR_NAME_NOT_RESOLVED`，先用普通 HTTPS 网站验证设备联网，再检查教务网址及校园网／学校 VPN 要求。

默认正方通用脚本只返回课程，没有作息和学期配置。新建时使用12节模板并在预览提示，第一周日期必须由用户填写；合并时优先使用目标课表的已有配置。请按学校实际作息确认和调整。学校脚本若调用 `savePresetTimeSlots`、`saveCourseConfig`，相应配置也会被采集。可粘贴完整拾光适配脚本替换默认脚本，脚本仅在当前运行会话保留。桌面端当前可用「导入拾光 JSON 文件」，内置教务浏览器仅实现 Android。

模块将 `name/day/startSection/endSection/weeks/teacher/position` 转为课程和周期安排，支持明确周次、单双周展开结果、多段安排、颜色、备注和学分。同一安排的重复周次片段合并；优先使用输入的 `courseSourceId` 和显式 `sourceId`；仓库脚本的 `id` 可能是课程代码或随机值，不用作稳定安排ID。没有安排ID时按课程、星期、节次、教师和地点建立来源键，周次变化可合并，其他字段变化可能形成新安排，预览会说明此限制。默认标记为局部结果，只有用户明确确认全量课程后才允许来源替换删除缺失项；现有课表还会进行三方冲突处理。

桥接支持 `shiguangBridge` / `shiguangBridgePromise` 与旧的 `AndroidBridge` / `AndroidBridgePromise`，包括提示、输入、单选、课程、学期配置、作息和完成通知。保存类调用只暂存于网页运行会话，`notifyTaskCompletion` 后一次返回；保存调用失败或课程为空不会返回成功。关闭、导航、重新执行和模块停用使旧执行结果失效。结果不包含浏览器的 Cookie 或登录凭据；站点存储由 Android WebView 管理，不是课表的备份数据。

配置确认后先显示转换摘要，「预览实际变更」准备课表计划；存在冲突时先在兼容模块选择处理方式，再转交课表导入预览。最终写入由课表确认和宿主审核，兼容模块不能提交课表写集。取消采集或配置不写入正式数据。JSON 文件导入使用同一流程。

支持数字字符串节次、周次及星期，支持整分秒格式时间，并按节次编号排序作息后校验。自定义上课时刻仅在起止时间准确对应已有节次时转换，不近似取整；按日期变化的夏冬季组合作息仍需进一步适配。周日起始的源学期会调整周日课程周次，保持实际日期；第一周周日在课表第一周周一之前，当前数据模型无法表示，整份导入明确拒绝，避免静默丢课或日期偏移。

选择另一学校、粘贴另一脚本或恢复默认脚本会清除旧草稿及来源配置。取消新采集或配置可保留此前草稿，页面会明确说明；不会把未完成的新采集视为已导入。

学校目录来自上游固定提交 `c586957c077506a5182105ae3961ceff4d0223ce`。269项均通过脚本语法、桥接直接方法引用及浏览器脚本大小检查；成都银杏酒店管理学院和东北大学研究生的未修改脚本通过模拟数据执行测试。真实QuickJS验证目录分页、全部5个脚本分包及学校选择，320px屏宽和1.6倍字号验证界面。静态特征包含25项自定义时刻、5项组合作息标记，不能据此推算实际可用学校数量；尚未逐校使用真实网站或账号验收。审计见 [兼容性记录](../../dist/verification/shiguang-warehouse-compatibility.json)。

上游脚本及接口参考版本、作者与许可见 [UPSTREAM.md](../../packages/modules/app.import.shiguang/UPSTREAM.md) 和 [MIT 许可](../../packages/modules/app.import.shiguang/THIRD_PARTY_LICENSE.txt)。脚本不会自动从远端更新，升级使用新的有版本模块包。

验证命令：

```bash
python3 scripts/module_host/build_packages.py
node --experimental-default-type=module scripts/module_host/shiguang_compat_test.mjs
node --experimental-default-type=module scripts/module_host/audit_shiguang_warehouse.mjs
source scripts/dev-env.sh
cd client
flutter test --no-pub test/shiguang_import_test.dart test/shiguang_school_picker_test.dart test/host_browser_test.dart test/schedule_import_test.dart test/host_ui_test.dart test/script_package_security_test.dart
flutter analyze --no-pub
```

19项 JavaScript 测试和32项 Flutter 回归测试通过，静态分析无问题。覆盖真实 QuickJS 转换、跨模块公共桥接调用、学校模块交接与取消、来源调用身份、课表接收计划、兼容模块不能提交、重复导入更新周次、未保存预览、非法输入与不支持的作息。另有14项安装器回归测试通过，覆盖多级复用依赖、新版候选依赖及失败回滚；build36 Release三种ABI构建通过。当前模拟器复验：`source scripts/dev-env.sh` 后运行 `python3 scripts/module_host/verify_shiguang_catalog.py --install`，只更新兼容模块，使用本地模拟页面，不访问真实学校或账号，不保存采集课程。输入学校缩写和网址时使用英文键盘，避免拼音组合文本尚未提交。

Android x86_64 模拟器已验证默认上游脚本在本地测试课表的 DOM 解析、单周展开、桥接返回配置流程及取消操作；测试页面只实现解析器所需的 jQuery 调用，不代表真实学校页面。截图见 [浏览器](../../dist/verification/android-shiguang-browser.png) 和 [采集后配置](../../dist/verification/android-shiguang-captured-config.png)，记录见 [shiguang-browser.json](../../dist/verification/shiguang-browser.json)。可追加 `--release` 在正式 APK 上复验。真实学校账号登录、ARM64 真机和 Windows 运行未验收。

build34 Release 已在同一模拟器复验：普通 HTTPS 网页 `https://example.com` 加载成功、网址输入保持原文、主页面 HTTP 404 和 `ERR_NAME_NOT_RESOLVED` 提示持续保留、失败页面禁用采集、后续成功加载恢复采集，并完成本地课表采集和取消。普通网页截图见 [public-page](../../dist/verification/android-shiguang-browser-public-page.png)，错误截图见 [dns-error](../../dist/verification/android-shiguang-browser-dns-error.png)。此次设备网络故障是模拟器 Wi-Fi 已开启但未连接；重新连接 AndroidWifi 后恢复域名解析。测试网络会对不存在的域名返回 fake-IP，故 DNS 错误用含空标签的 `xudian..invalid` 触发。复验命令：`python3 scripts/module_host/verify_shiguang_browser.py --install --release --public-url https://example.com`。

1.2.0 已在build36模拟器完成模块升级、学校缩写搜索、网址回填及未修改YXHMC官方脚本采集，确认具名校验通过、返回学期配置、取消不保存。网页fetch仅返回本地模拟数据；原有课表界面与上次验收完全一致。取消后的键盘恢复导致自动检查一度看不到底部提示，关闭键盘后完成实机检查，复验工具已加入该处理。记录见 [模拟器验证](../../dist/verification/shiguang-warehouse-emulator.json)、[学校搜索截图](../../dist/verification/android-shiguang-school-search.png) 和 [取消状态截图](../../dist/verification/android-shiguang-warehouse-cancelled.png)。

1.3.0 层级与归因验证：14项学校目录／页面测试通过（包含320px屏宽、1.6倍字体），与浏览器和课表导入联合回归共24项通过，JavaScript兼容测试19项通过。模拟器界面复验工具：`python3 scripts/module_host/verify_shiguang_hierarchy.py`，不执行浏览器脚本或写入课程。学校列表只展示学校名和分类／入口数量，详情显示该校各入口、说明、维护者和原始脚本Github地址；关于页的地址和完整许可均可长按复制。

最终1.3.1统一使用宿主支持的图标，校内／WebVPN入口及首页选项对齐一致。已在原build36客户端中只更新模块，实机验证学校合并、详情说明、无结果通用入口、源码地址与致谢许可；最终首页及通用／关于页再次核对。记录见 [层级验证](../../dist/verification/shiguang-hierarchy-emulator.json)、[首页截图](../../dist/verification/android-shiguang-1.3-home.png)、[学校搜索](../../dist/verification/android-shiguang-1.3-schools.png) 和 [关于与致谢](../../dist/verification/android-shiguang-1.3-about.png)。

1.4.0 合并模块与 App 的返回操作：左上角箭头与 Android 系统返回均返回实际上一层，首页才退出模块。顶栏随学校列表、学校详情、通用系统、导入结果和关于与致谢变化，内容不再重复标题或返回按钮。学校搜索、分页、网址和未保存草稿保留；详情打开致谢后返回原详情。

客户端 build37 与模块1.4.0一起验证：608 项 Flutter 测试、19 项 JavaScript 兼容测试及21 项发布工具测试通过，静态分析无问题，三个 Android ABI 的 release APK 构建通过。导航测试使用真实模块详情路由，覆盖320像素／1.6倍字体、顶栏及系统返回、搜索保留和原有课表记录不变。汇总见 [检查记录](../../dist/verification/shiguang-navigation-checks.json)。模拟器导航复验命令为 `python3 scripts/module_host/verify_shiguang_navigation.py`，不连接学校、不保存课程。
