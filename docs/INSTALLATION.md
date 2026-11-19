# Android 安装、更新与模块商店

完整源码在 [main](https://github.com/JayConstruct/xudian)，公开作者索引在 `module-catalog` 分支，统一目录在 [xudian-modules](https://github.com/JayConstruct/xudian-modules)。

## 安装 App

有正式 App Release 时，可从 [发布页](https://github.com/JayConstruct/xudian/releases) 下载对应设备的 APK。安装后在“设置 → 关于序点 → 检查更新”查询新版本，详见 [检查 App 更新](#检查-app-更新)。模块 Release 不作为 App 更新。

打开 [Android Actions](https://github.com/JayConstruct/xudian/actions/workflows/android.yml)，选择成功运行，下载 `xudian-android-release-<commit>` 产物并解压。App tag 发布的 APK 统一命名为 `xudian-v<版本>-<ABI>-release.apk`，每个 ABI 仅一份；文件名与摘要清单一致。多数手机选择 `arm64-v8a`，旧 ARMv7 手机选择 `armeabi-v7a`，x86_64 模拟器选择 `x86_64`。普通分支／PR 的开发构建仍使用 Flutter 的 `app-<ABI>-release.apk` 命名。压缩包附带 `SOURCE_COMMIT` 和 `SHA256SUMS`，可核对源码版本和文件摘要。

将对应 APK 传到 Android 设备并打开，按系统安装提示完成安装。开发设备也可使用 `adb install <APK路径>`。首次打开进入“日程”，默认安装任务、日程和 AI 助手模块；课表与教务导入从商店选择。

按当前工作流发布的 App tag APK（包括测试版）必须通过固定签名和证书指纹验证；请下载 Release 附件或对应的 `xudian-android-release-<commit>` 最终产物，不分发 `candidate` 中间产物。普通分支／PR 构建仍使用开发签名。历史 CI 临时签名或本机开发安装与固定签名不一定一致，覆盖更新需要原签名匹配；不要为覆盖而直接卸载或清数据。签名配置见 [Android 签名保管](ANDROID_SIGNING.md)。本文验证 Android 安装流程；ARM 真机和 Windows 的运行验收另行记录。

## 检查 App 更新

入口：右上角菜单 → 设置 → 更新设置 → 检查 App 更新，也可从“关于序点 → 检查更新”进入。页面显示实际安装版本与构建号，进入时查询 GitHub；可手动重新检查。

“更新设置”提供“启动时检查更新”开关，默认关闭，选择保存在本机。开启后从下次冷启动起，在首帧之后异步并行检查 App 与已安装模块（包括已停用模块），返回前台、页面切换和设置变化不重复触发。两类检查分别限时 30 秒，网络失败不影响启动；发现更新时提供“查看”提醒，设置首页和更新设置页也保留本次检查结果。关闭开关后仍可手动检查。

App 沿用已选择的更新通道。模块沿用模块商店配置的目录源，只查询已安装模块的索引，最多并发 3 个；按语义版本筛选高于已安装版本、兼容当前宿主 API 的正式版本，已知来源与目录不符的模块跳过。启动检查不以离线缓存宣告检查成功，单个索引失败不影响其他模块结果。检查只读取元数据；App 下载仍打开发布页，模块下载、权限审核及安装仍由用户在模块商店确认。

更新来源固定为 [JayConstruct/xudian Releases](https://github.com/JayConstruct/xudian/releases)。默认正式通道过滤预发布；开启“测试通道”后同时检查正式版与 `alpha.N`、`beta.N`、`rc.N` 测试版，包括 GitHub 标记为 Pre-release 的版本。通道选择保存在本机，切换后立即重新检查，下次进入时沿用选择。测试版本在结果中明确标识，安装前请备份数据。

两个通道都过滤草稿、模块发布和没有当前平台安装包的记录，按语义版本比较；例如 `0.1.10` 高于 `0.1.9`，`0.2.0-beta.10` 高于 `0.2.0-beta.3`，同一基础版本按 alpha → beta → rc → 正式版递增。Android 识别已上传的 `.apk`，Windows 识别名称含 `windows` 的 `.zip`、`.exe` 或 `.msix`。链接必须属于同一仓库，使用 HTTPS。

有新版本时显示更新说明，点击“查看更新并下载”在浏览器打开对应 Release，选择适合设备的安装包；也可复制链接。App 不在后台下载或安装。当前版本更高时不会提示降级，包括从测试通道切回正式通道。构建号用于标识安装包；同一语义版本的不同构建不作为更新，发布新功能或修复需要递增版本号。

网络错误、超时、GitHub 请求限制和格式错误显示可重试的失败状态。没有符合当前通道和平台的 App Release 时，正式通道显示“暂未发布 App 正式版本”，测试通道显示“暂未发布 App 可用版本”。检查最多读取 5 页、每页 100 条记录，达到上限会提示查看发布页，不将不完整的查询视为已是最新版。

## 从商店安装业务模块

1. 打开右上角页面菜单 → 设置 → 模块与连接 → 模块管理与恢复 → 模块商店。
2. 选择“拾光教务导入兼容”，查看版本、发布仓库、权限及依赖，点击“解析依赖并安装”。
3. 商店下载并核验模块包，同时补齐“大学课表”依赖。审核页展示两个模块的版本、安装操作、权限、未签名提示和 SHA-256；点击“确认安装”。
4. 返回模块管理，确认两者为“已启用”。返回工作区可打开“课表”；设置的“模块与连接”中可打开拾光导入入口。
5. 完全关闭并重新打开 App，检查模块和入口仍然可用。

作者索引更新后，GitHub CDN 可能短暂保留旧内容；可以在商店“刷新 / 重试”。安装需要能匿名访问 GitHub、raw.githubusercontent.com 及 Release 下载 CDN。真实学校账号的采集不属于本安装验收。

## 自动复验

连接专用 x86_64 Android 模拟器，确保当前前台 Android 用户尚未安装 App，然后执行：

```bash
python3 scripts/module_host/verify_fresh_install.py \
  --apk client/build/app/outputs/flutter-apk/app-x86_64-release.apk \
  --output dist/verification/installation/fresh-install
```

在已有模拟器中使用隔离 Android 用户时，先创建并切换该用户，再给脚本传入 `--user <ID>`。Android 用户共享 APK 二进制；保留其他用户数据的验收须使用相同 APK 和签名，或使用独立模拟器。脚本拒绝目标用户已安装 App 的情况，不清数据、不卸载。报告和截图记录首次安装、依赖审核、启用状态、重启与模块入口。采集失败且模块尚未安装时，可使用相同 APK、用户和输出目录加 `--resume`，脚本核验原首装证据及当前 APK 后继续，不重新安装或清数据。
