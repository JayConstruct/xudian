# Android 签名保管

APK 内的公开证书和证书 SHA-256 指纹可以公开；需要保密的是 keystore 中的私钥及其密码。下载 APK 不能据此恢复私钥。Base64 只是一种编码，不是加密。

## 选用并保存密钥

优先确认原安装对应的私钥是否仍在。若能找到且尚未泄露，用原密钥可以保留覆盖更新能力；不要把历史开发密钥直接视为安全的正式密钥。若原密钥已经丢失，不能从旧 APK 中恢复；采用新密钥后，历史安装须另行安排数据迁移，不能承诺原地覆盖。

确需新建密钥时，在可信本机运行以下示例，将文件存到仓库外的私有目录；`keytool` 交互输入密码，避免把密码写到命令行或 shell 历史：

```bash
umask 077
mkdir -p "$HOME/.android-signing"
keytool -genkeypair -keystore "$HOME/.android-signing/xudian-release.jks" \
  -alias xudian-release -keyalg RSA -keysize 3072 -validity 10000
keytool -list -v -keystore "$HOME/.android-signing/xudian-release.jks" -alias xudian-release
```

保存 `SHA256` 公开指纹，用作 `ANDROID_SIGNING_CERT_SHA256`。固定签名从建立后持续使用，不能每轮构建重新生成。为 keystore 和密码建立分开保存的加密备份，保留另一份离线副本并验证可恢复；不要把 debug.keystore 当作正式密钥备份。

## 配置 GitHub

1. 创建 `android-release` Environment，把四个签名 secrets 和公开指纹变量按 [更新文档](APP_UPDATES.md#发布-android-更新) 配齐。已有仓库级同名 secrets 应迁入 Environment 并删除仓库级副本，避免其他任务引用。
2. 在该 Environment 的 deployment branches and tags 中选择仅允许 tag `v*`，不允许分支部署。结合仓库 tag ruleset 限制 `v*` 的创建、修改和删除权限，仅让可信发布者操作；仅有命名规则无法证明 tag 指向可信代码。
3. 限制仓库写入和 Environment 管理权限，保护主分支及工作流修改，发布账号启用双重验证。合并前审查依赖、工作流及签名步骤变更；Secrets 的日志脱敏不是防泄露的安全边界。

有 GitHub CLI 时，可在可信本机通过标准输入上传，避免把密钥内容或密码放进参数；密码用交互方式输入。示例需要替换仓库和公开指纹：

```bash
base64 -w 0 "$HOME/.android-signing/xudian-release.jks" | \
  gh secret set ANDROID_KEYSTORE_BASE64 --repo OWNER/REPO --env android-release
gh secret set ANDROID_KEYSTORE_PASSWORD --repo OWNER/REPO --env android-release
gh secret set ANDROID_KEY_ALIAS --repo OWNER/REPO --env android-release
gh secret set ANDROID_KEY_PASSWORD --repo OWNER/REPO --env android-release
gh variable set ANDROID_SIGNING_CERT_SHA256 --repo OWNER/REPO --env android-release \
  --body PUBLIC_CERTIFICATE_SHA256
```

不要把 keystore、密码或 Base64 内容粘贴到聊天、Issue、PR、源码、Flutter assets 或发布说明中；不要启用 `set -x`、输出环境变量或上传整个工作目录。仓库已有忽略和边界检查会拒绝常见密钥文件，但不能识别所有改名或编码后的秘密。

## CI 中的使用范围

所有 App tag，包括测试版，使用相同 Environment 和指纹。`android` 任务只产出候选 APK；`sign` 在另一台临时 GitHub 托管 runner 上下载候选包，核对源码提交和文件摘要，之后才在单个步骤注入私钥与密码。它不检出源码、不运行构建插件；签名会替换候选包的开发签名，并验证三个 ABI 的固定证书。私钥临时文件权限为 `600`、目录为 `700`，成功和普通失败均通过退出清理删除；托管 runner 在任务结束后销毁。`publish` 只读取签名成功后的产物。

这降低了构建代码和依赖接触私钥的机会，不能保证有发布权限的恶意工作流或已被攻破的签名环境无法泄露密钥。更强的隔离需要受控的外部签名服务或硬件密钥托管。不要为“定期轮换”随意替换 Android App 签名私钥；更新兼容性依赖它。

若怀疑泄露，停止发布、限制相关账号和工作流权限并排查。删除 Git 文件或重设 keystore 密码不能使已复制的私钥失效；需评估 Android 支持的签名轮换／用户迁移，再恢复发布。

参考：[Android 签名说明](https://developer.android.com/studio/publish/app-signing)、[GitHub Actions 安全实践](https://docs.github.com/en/actions/reference/security/secure-use)、[Actions Secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)。

## 2026-10-20 本机初始化

用户选择后续重新安装，不再要求兼容历史临时签名。已创建长期 RSA-3072 密钥，keystore 位于 `~/.android-signing/xudian-release.jks`，公开证书位于同目录的 `xudian-release.der`。公开 SHA-256 指纹为：

```text
cdb8ef381555450ad2e6f04dafa4a52635f84fa4fc22fdb92ef776ccb6abc4fd
```

随机生成的 keystore 密码、密钥密码和 alias 暂存于仓库外 `~/.config/xudian-signing/credentials.json`；它和 keystore 的权限均为 `600`，所在专用目录为 `700`。该密码文件不应发送到聊天或提交到仓库。它用于本机安全导入，不替代密码管理器或离线备份：完成导入后，将密码迁入可信密码管理器，并备份 keystore；确认可恢复后再删除本机临时密码副本。

初始化时没有可用的 GitHub CLI 授权。此后已安装官方 GitHub CLI，用户自行完成登录，并通过 CLI 创建和回读核对 `android-release` Environment：仅允许 tag `v*`，四个签名 secrets 与公开指纹变量已配置。Environment 的限制不替代仓库 tag ruleset；后者尚未配置。私钥和密码仅通过标准输入导入，未输出到日志。

以下代码保留为后续安全导入说明；不需要每轮发布重新执行。须在具有 GitHub 管理权限且已完成 CLI 登录的可信本机运行，并能读取上述签名文件；若迁移到其他可信机器，使用加密方式传输。

```bash
python3 - <<'PY'
import base64
import json
from pathlib import Path
import subprocess

config = json.loads((Path.home() / '.config/xudian-signing/credentials.json').read_text())
scope = ['--repo', 'JayConstruct/xudian', '--env', 'android-release']
subprocess.run(['gh', 'secret', 'set', 'ANDROID_KEYSTORE_BASE64', *scope],
               input=base64.b64encode(Path(config['keystorePath']).read_bytes()), check=True)
for name in ['ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD']:
    subprocess.run(['gh', 'secret', 'set', name, *scope],
                   input=config[name].encode(), check=True)
subprocess.run(['gh', 'variable', 'set', 'ANDROID_SIGNING_CERT_SHA256', *scope,
                '--body', 'cdb8ef381555450ad2e6f04dafa4a52635f84fa4fc22fdb92ef776ccb6abc4fd'], check=True)
PY
```

这会修改上述仓库的签名配置；不要在非预期账号或仓库中执行。线上完成配置且合入工作流后，下一个新的测试版／正式版 tag 才会使用固定签名。不要重发或覆盖历史同版本安装包。
