# 从 GitHub 检查 App 更新

入口：右上角菜单 → 设置 → 更新设置 → 检查 App 更新，也可从“关于序点 → 检查更新”进入。页面显示实际安装版本与构建号，进入时查询 GitHub；可手动重新检查。

“更新设置”提供“启动时检查更新”开关，默认关闭，选择保存在本机。开启后从下次冷启动起，在首帧之后异步并行检查 App 与已安装模块（包括已停用模块），返回前台、页面切换和设置变化不重复触发。两类检查分别限时 30 秒，网络失败不影响启动；发现更新时提供“查看”提醒，设置首页和更新设置页也保留本次检查结果。关闭开关后仍可手动检查。

App 沿用已选择的更新通道。模块沿用模块商店配置的目录源，只查询已安装模块的索引，最多并发 3 个；按语义版本筛选高于已安装版本、兼容当前宿主 API 的正式版本，已知来源与目录不符的模块跳过。启动检查不以离线缓存宣告检查成功，单个索引失败不影响其他模块结果。检查只读取元数据；App 下载仍打开发布页，模块下载、权限审核及安装仍由用户在模块商店确认。

更新来源固定为 [JayConstruct/xudian Releases](https://github.com/JayConstruct/xudian/releases)。默认正式通道过滤预发布；开启“测试通道”后同时检查正式版与 `alpha.N`、`beta.N`、`rc.N` 测试版，包括 GitHub 标记为 Pre-release 的版本。通道选择保存在本机，切换后立即重新检查，下次进入时沿用选择。测试版本在结果中明确标识，安装前请备份数据。

两个通道都过滤草稿、模块发布和没有当前平台安装包的记录，按语义版本比较；例如 `0.1.10` 高于 `0.1.9`，`0.2.0-beta.10` 高于 `0.2.0-beta.3`，同一基础版本按 alpha → beta → rc → 正式版递增。Android 识别已上传的 `.apk`，Windows 识别名称含 `windows` 的 `.zip`、`.exe` 或 `.msix`。链接必须属于同一仓库，使用 HTTPS。

有新版本时显示更新说明，点击“查看更新并下载”在浏览器打开对应 Release，选择适合设备的安装包；也可复制链接。App 不在后台下载或安装。当前版本更高时不会提示降级，包括从测试通道切回正式通道。构建号用于标识安装包；同一语义版本的不同构建不作为更新，发布新功能或修复需要递增版本号。

网络错误、超时、GitHub 请求限制和格式错误显示可重试的失败状态。没有符合当前通道和平台的 App Release 时，正式通道显示“暂未发布 App 正式版本”，测试通道显示“暂未发布 App 可用版本”。检查最多读取 5 页、每页 100 条记录，达到上限会提示查看发布页，不将不完整的查询视为已是最新版。

## 发布 Android 更新

Android 检查工作流支持 `v*` tag 触发。正式版使用 `vMAJOR.MINOR.PATCH`；测试版使用 `vMAJOR.MINOR.PATCH-alpha.N`、`-beta.N` 或 `-rc.N`，tag 必须与 `client/pubspec.yaml` 的完整版本号一致（不含 `+` 后的构建号）。普通分支检查继续上传 Actions 构建产物；tag 在检查、测试、构建全部通过后，额外发布 Release，包括三个 ABI 的 APK、`SHA256SUMS` 和 `SOURCE_COMMIT`。发布不会覆盖已有 Release。

测试版自动标记为 GitHub Pre-release，不设为 Latest，App 正式更新检查仍会过滤它，开启测试通道后可检查并打开对应下载页。所有 App tag（包括 alpha／beta／rc）发布均使用同一固定签名；历史 CI 临时签名或本机开发签名安装不因此自动兼容。安装前备份数据，签名不匹配时不要通过卸载现有应用来强行覆盖。

流水线将静态／Python／目录检查、三个 Flutter 测试分片和三 ABI APK 构建并行执行。每个分片保留两个测试进程，使用 Flutter 内置的 `--total-shards=3 --shard-index=0/1/2` 覆盖完整测试集；各测试任务独立生成模块夹具。构建通过 `setup-java` 缓存 Gradle 状态，并启用 Gradle 构建缓存。`android` 总关卡要求检查、全部分片和构建均成功；失败、取消或意外跳过都会阻止后续签名，签名仍在独立 runner 中执行。

同时推送 main 与版本标签时，main 先核对当前版本对应标签的实际提交和同一工作流的标签运行。只有提交完全一致且标签运行正在进行或已成功，才省去 main 的重复测试与构建；main 的 `android` 总关卡继续等待该标签运行的 `android` 检查通过，并传递失败或取消结果。轻量与附注标签均核对到提交。查询失败、标签尚未注册运行、提交不符或标签运行已失败时，main 正常执行完整检查；PR、手动运行和标签本身始终完整执行。去重不会复用其他提交的 APK，也不会自动发布未打标签的提交。

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
