# 从 GitHub 检查 App 更新

入口：右上角菜单 → 设置 → 关于序点 → 检查更新。页面显示实际安装版本与构建号，进入时查询 GitHub；可手动重新检查。启动 App 不自动联网检查。

更新来源固定为 [JayConstruct/xudian Releases](https://github.com/JayConstruct/xudian/releases)。检查器读取公开 Release，过滤草稿、预发布、模块发布和没有当前平台安装包的记录，按语义版本比较；例如 `0.1.10` 高于 `0.1.9`。Android 识别已上传的 `.apk`，Windows 识别名称含 `windows` 的 `.zip`、`.exe` 或 `.msix`。链接必须属于同一仓库，使用 HTTPS。

有新版本时显示更新说明，点击“查看更新并下载”在浏览器打开对应 Release，选择适合设备的安装包；也可复制链接。App 不在后台下载或安装。当前版本更高时不会提示降级。构建号用于标识安装包；同一语义版本的不同构建不作为正式更新，正式发布新功能或修复需要递增版本号。

网络错误、超时、GitHub 请求限制和格式错误显示可重试的失败状态。仓库只有模块包或没有 App Release 时显示“暂未发布 App 正式版本”。检查最多读取 5 页、每页 100 条记录，达到上限会提示查看发布页，不将不完整的查询视为已是最新版。

## 发布正式 Android 更新

Android 检查工作流支持 `v*` tag 触发。正式版使用 `vMAJOR.MINOR.PATCH`；测试版使用 `vMAJOR.MINOR.PATCH-alpha.N`、`-beta.N` 或 `-rc.N`，tag 必须与 `client/pubspec.yaml` 的完整版本号一致（不含 `+` 后的构建号）。普通分支检查继续上传 Actions 构建产物；tag 在检查、测试、构建全部通过后，额外发布 Release，包括三个 ABI 的 APK、`SHA256SUMS` 和 `SOURCE_COMMIT`。发布不会覆盖已有 Release。

测试版自动标记为 GitHub Pre-release，不设为 Latest，App 正式更新检查仍会过滤它。测试版使用 CI 开发签名，不保证不同 CI 构建或现有安装之间的签名一致；安装前备份数据，签名不匹配时不要通过卸载现有应用来强行覆盖。需要固定签名的版本使用下述正式发布流程。

正式 Release 必须使用固定 Android 签名。仓库需配置四个 Actions secrets：

- `ANDROID_KEYSTORE_BASE64`：固定 keystore 的 Base64 内容。
- `ANDROID_KEYSTORE_PASSWORD`：keystore 密码。
- `ANDROID_KEY_ALIAS`：签名别名。
- `ANDROID_KEY_PASSWORD`：签名密钥密码。

tag 构建缺少其中任一项时会停止发布。keystore 只在 runner 临时目录使用；仓库中不保存密钥。本机发布构建可设置对应 `XUDIAN_KEYSTORE_PATH`、`XUDIAN_KEYSTORE_PASSWORD`、`XUDIAN_KEY_ALIAS`、`XUDIAN_KEY_PASSWORD` 环境变量。普通本机开发构建继续使用开发签名。覆盖安装必须与原安装签名一致，应保管原签名密钥；已有开发签名安装不会因此自动转换为正式签名。

正式发布步骤（示例）：将 `client/pubspec.yaml` 的语义版本改为 `0.2.0`，提交并合入主分支，确认签名 secrets 已配置，再创建和推送 `v0.2.0` tag。tag 触发流程后，安装 `0.1.x` 的用户即可查到正式更新。测试版则先将版本改为如 `0.2.0-beta.1`，提交后推送同名 `v0.2.0-beta.1` 标签；只有发布任务成功并附带安装包，才算完成发布。

GitHub Release 接口约定见 [GitHub 官方文档](https://docs.github.com/en/rest/releases/releases)。安装版本通过 [package_info_plus](https://pub.dev/packages/package_info_plus) 读取。
