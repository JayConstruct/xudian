# 从 GitHub 检查 App 更新

入口：右上角菜单 → 设置 → 关于序点 → 检查更新。页面显示实际安装版本与构建号，进入时查询 GitHub；可手动重新检查。启动 App 不自动联网检查。

更新来源固定为 [JayConstruct/xudian Releases](https://github.com/JayConstruct/xudian/releases)。默认正式通道过滤预发布；开启“测试通道”后同时检查正式版与 `alpha.N`、`beta.N`、`rc.N` 测试版，包括 GitHub 标记为 Pre-release 的版本。通道选择保存在本机，切换后立即重新检查，下次进入时沿用选择。测试版本在结果中明确标识，安装前请备份数据。

两个通道都过滤草稿、模块发布和没有当前平台安装包的记录，按语义版本比较；例如 `0.1.10` 高于 `0.1.9`，`0.2.0-beta.10` 高于 `0.2.0-beta.3`，同一基础版本按 alpha → beta → rc → 正式版递增。Android 识别已上传的 `.apk`，Windows 识别名称含 `windows` 的 `.zip`、`.exe` 或 `.msix`。链接必须属于同一仓库，使用 HTTPS。

有新版本时显示更新说明，点击“查看更新并下载”在浏览器打开对应 Release，选择适合设备的安装包；也可复制链接。App 不在后台下载或安装。当前版本更高时不会提示降级，包括从测试通道切回正式通道。构建号用于标识安装包；同一语义版本的不同构建不作为更新，发布新功能或修复需要递增版本号。

网络错误、超时、GitHub 请求限制和格式错误显示可重试的失败状态。没有符合当前通道和平台的 App Release 时，正式通道显示“暂未发布 App 正式版本”，测试通道显示“暂未发布 App 可用版本”。检查最多读取 5 页、每页 100 条记录，达到上限会提示查看发布页，不将不完整的查询视为已是最新版。

## 发布 Android 更新

Android 检查工作流支持 `v*` tag 触发。正式版使用 `vMAJOR.MINOR.PATCH`；测试版使用 `vMAJOR.MINOR.PATCH-alpha.N`、`-beta.N` 或 `-rc.N`，tag 必须与 `client/pubspec.yaml` 的完整版本号一致（不含 `+` 后的构建号）。普通分支检查继续上传 Actions 构建产物；tag 在检查、测试、构建全部通过后，额外发布 Release，包括三个 ABI 的 APK、`SHA256SUMS` 和 `SOURCE_COMMIT`。发布不会覆盖已有 Release。

测试版自动标记为 GitHub Pre-release，不设为 Latest，App 正式更新检查仍会过滤它，开启测试通道后可检查并打开对应下载页。所有 App tag（包括 alpha／beta／rc）发布均使用同一固定签名；历史 CI 临时签名或本机开发签名安装不因此自动兼容。安装前备份数据，签名不匹配时不要通过卸载现有应用来强行覆盖。

在 GitHub 的 `Settings → Environments` 创建 `android-release`，在该 Environment 中配置四个 secrets：

- `ANDROID_KEYSTORE_BASE64`：固定 keystore 的 Base64 内容。
- `ANDROID_KEYSTORE_PASSWORD`：keystore 密码。
- `ANDROID_KEY_ALIAS`：签名别名。
- `ANDROID_KEY_PASSWORD`：签名密钥密码。

同一 Environment 还需配置变量 `ANDROID_SIGNING_CERT_SHA256`，填入这把密钥的公开证书 SHA-256 指纹（64 位十六进制，也接受冒号分隔和大写）。每个 ABI 签名后都必须验证签名有效且指纹匹配；缺少配置、密钥解码／签名失败或指纹不符时停止发布，不回退临时签名。

编译、依赖和测试任务不读取任何签名 secrets，生成的 tag 候选包仅供后续签名。独立 GitHub 托管 runner 的签名任务不检出仓库、不执行应用、Gradle 或测试代码，只运行 Android 官方签名工具。密钥以仅当前用户可读写的权限临时解码，密码通过环境变量传入工具，步骤退出时删除密钥；只上传明确列出的已签名 APK、摘要和源码提交号。工作流 Action 使用完整提交 SHA 固定。分支／PR 构建仍为开发签名，不能作为固定签名更新包分发。

私钥生成、Environment 的 tag 限制、备份与泄露预防见 [Android 签名保管](ANDROID_SIGNING.md)。本机发布构建仍可设置 `XUDIAN_KEYSTORE_PATH`、`XUDIAN_KEYSTORE_PASSWORD`、`XUDIAN_KEY_ALIAS`、`XUDIAN_KEY_PASSWORD` 环境变量；普通本机开发构建继续使用开发签名。已有开发签名安装不会自动转换为固定签名。

正式发布步骤（示例）：将 `client/pubspec.yaml` 的语义版本改为 `0.2.0`，提交并合入主分支，确认 Environment 的签名 secrets 和指纹已配置，再创建和推送 `v0.2.0` tag。tag 触发流程后，安装 `0.1.x` 的用户即可查到正式更新；能否覆盖仍取决于原安装签名。测试版则先将版本改为如 `0.2.0-beta.1`，提交后推送同名 `v0.2.0-beta.1` 标签；只有签名验证和发布任务成功并附带安装包，才算完成发布。

GitHub Release 接口约定见 [GitHub 官方文档](https://docs.github.com/en/rest/releases/releases)。安装版本通过 [package_info_plus](https://pub.dev/packages/package_info_plus) 读取。
