# Android 首次安装与模块商店

完整源码在 [main](https://github.com/JayConstruct/xudian)，公开作者索引在 `module-catalog` 分支，统一目录在 [xudian-modules](https://github.com/JayConstruct/xudian-modules)。

## 安装 App

打开 [Android Actions](https://github.com/JayConstruct/xudian/actions/workflows/android.yml)，选择成功运行，下载 `xudian-android-release-<commit>` 产物并解压。多数手机使用 `app-arm64-v8a-release.apk`；x86_64 模拟器使用 `app-x86_64-release.apk`。压缩包附带 `SOURCE_COMMIT` 和 `SHA256SUMS`，可核对源码版本和文件摘要。

2026-10-10 已验证的构建为提交 `0b80430`：[成功运行](https://github.com/JayConstruct/xudian/actions/runs/38021150220) / [下载 APK](https://github.com/JayConstruct/xudian/actions/runs/38021150220/artifacts/11657938170)。该产物保存至 2026-10-24 03:43 UTC，过期后可使用后续成功构建或手动触发工作流。首装与商店安装的具体证据见 [验证记录](VERIFICATION.md)。

将对应 APK 传到 Android 设备并打开，按系统安装提示完成安装。开发设备也可使用 `adb install <APK路径>`。首次打开进入“今天”，默认安装任务、今天和 AI 助手模块；课表与教务导入从商店选择。

当前 APK 使用测试签名，GitHub runner 的测试密钥可能与本机不同，覆盖已有安装需要相同签名。正式稳定签名仍待配置。本文验证 Android 安装流程；ARM 真机和 Windows 的运行验收另行记录。

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
  --output dist/verification/fresh-install
```

在已有模拟器中使用隔离 Android 用户时，先创建并切换该用户，再给脚本传入 `--user <ID>`。Android 用户共享 APK 二进制；保留其他用户数据的验收须使用相同 APK 和签名，或使用独立模拟器。脚本拒绝目标用户已安装 App 的情况，不清数据、不卸载。报告和截图记录首次安装、依赖审核、启用状态、重启与模块入口。采集失败且模块尚未安装时，可使用相同 APK、用户和输出目录加 `--resume`，脚本核验原首装证据及当前 APK 后继续，不重新安装或清数据。
