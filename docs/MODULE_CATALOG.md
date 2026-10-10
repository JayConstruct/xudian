# 模块目录与作者发布

统一目录仓库为 `JayConstruct/xudian-modules`，入口是 `catalog.json`。它只维护目录、接入说明、JSON Schema 与校验工具。模块由各自作者仓库发布；首批自有模块来自 `JayConstruct/xudian`，源码和测试继续留在 `packages/modules/` 与当前工程。

## 目录和版本索引

目录使用 `catalogFormat: 1` 和 `modules` 数组。每个条目包含 `id`、`name`、`description`、`author`、`repository`（`owner/repo`）及 `indexUrl`。客户端默认目录地址为 `https://raw.githubusercontent.com/JayConstruct/xudian-modules/main/catalog.json`，支持更换目录仓库。

模块商店支持目录条目的可选 `category` 和 `featured`。`category` 是长度 1 至 20 字、不能全部为空白的字符串，客户端去除首尾空白后显示；缺省分类为“其他”。`featured` 必须是布尔值，缺省为 `false`，用于商店的推荐区域。分类和推荐由目录维护者编辑，可直接通过目录 PR 更新；它们不改变模块包、版本索引、官方身份或签名信任，也不表示安全审查结论。未含这些字段的现有目录继续兼容。

```json
{
  "catalogFormat": 1,
  "modules": [{
    "id": "app.import.shiguang",
    "name": "拾光教务导入兼容",
    "description": "按学校或通用教务系统导入课程，提供脚本说明、源码与致谢，预览确认后保存课表。",
    "author": "JayConstruct",
    "category": "学习",
    "featured": true,
    "repository": "JayConstruct/xudian",
    "indexUrl": "https://raw.githubusercontent.com/JayConstruct/xudian/module-catalog/module-index/app.import.shiguang.json"
  }]
}
```

作者版本索引使用 `indexFormat: 1`、`moduleId`、`repository` 与 `versions` 数组。每个版本包含版本号、完整模块 `manifest`、完整 `services` 声明、固定 GitHub Release 下载 `url`、字节数 `size`、SHA-256 `sha256`，以及可选 `signature`。未签名用 `null`，摘要只检测完整性，不证明发布者身份。模块 ID 和版本必须与包内一致，清单及服务声明也必须完全一致。JSON Schema 位于 `packages/schemas/module-catalog-v1.schema.json` 与 `module-version-index-v1.schema.json`。

`description`、`author` 是模块清单的可选字符串，旧包继续兼容。旧包无介绍时客户端显示“作者未提供说明”。作者字段是说明文字，不替代现有官方身份、发布者保护规则或数字签名。

官方模块的在线更新只接受当前 APK 内置目录中已固定的模块 ID 和包摘要。下载包与 APK 内可信资源的固定摘要完全匹配时，客户端可保留该包的官方来源身份；统一目录或作者版本索引中的摘要不能自行赋予此身份。超出当前 APK 固定范围的未签名包不能覆盖已安装的官方模块，也不能借用已验证发布者的文字身份覆盖其签名模块。更新不会自动执行，仍须用户确认。

## 作者准备 Release

将示例中的 `NEW_RELEASE` 和 `EXPECTED_COUNT` 替换为本轮的新 tag 标识及实际准备资产数；不复用已发布 tag。源码目录包含 `module.json` 和源文件。修改说明、作者或源码后必须发布新语义版本；已发布资产和历史索引条目不可修改。工具读取已有 `module-index/`，保留旧版本记录，只追加新版本；同版本包变化会失败。包采用固定 ZIP 时间戳、排序路径和现有包格式，结果可重复生成。

```bash
python3 scripts/module_catalog/publish.py --tag modules-NEW_RELEASE
python3 scripts/module_catalog/catalog.py packages/catalog/catalog.json \
  --index-dir module-index --package-dir dist/module-releases
python3 -m unittest discover -s scripts/module_catalog -p 'test_*.py'
```

输出为 `dist/module-releases/<id>-<version>.xmodule` 和 `module-index/<id>.json`。首批索引发布在源码仓库的 `module-catalog` 分支，保留原 `main` 分支不变；Release tag 指向这份可复现 APK 的源码快照。其他作者可以选择自己的稳定分支。作者仓库可以不同：在目录中登记自己的仓库，然后传入 `--repository Author/repo --modules <source-dir> --catalog <catalog.json> --index-dir <index-dir> --output <release-dir>`。

已有旧版包可通过重复 `--archive-dir <历史包目录>` 收录。工具逐字节保留旧包，采用原清单和服务声明生成索引，不将新说明写回旧包。初期发布版本及资产数量见 [历史发布说明](archive/MODULE_CATALOG_20261009.md)。

需要更新客户端首次安装的资源时添加 `--bundle-catalog client/assets/modules/catalog.json`。工具仅更新原有条目的版本化资产地址及摘要，保留 `default` 标记与所有旧包文件；现有用户的已安装模块不会因资源更新自动升级。

发布顺序：先审阅包和版本索引，创建对应固定 tag 的 GitHub Release 并上传所有包；再让作者索引公开可访问，使索引所有下载地址可用；最后提交目录 PR。首次创建统一目录仓库时，将 `packages/catalog/` 内容作为仓库根目录发布，勿将 `.xmodule` 或作者版本索引复制过去。作者仓库和目录仓库都必须公开，客户端匿名下载不会使用维护者的 GitHub 授权。需要登录 GitHub 并具备两个仓库的写权限。

```bash
python3 scripts/module_catalog/release.py --repository JayConstruct/xudian \
  --tag modules-NEW_RELEASE --expected-count EXPECTED_COUNT
python3 scripts/module_catalog/catalog.py packages/catalog/catalog.json --online
```

不要使用 `gh release upload --clobber` 覆盖已发布版本。Release tag 也不可重新指向另一份代码。已存在的版本重新运行工具时会复用原下载 URL，保留原 tag。

发布脚本需要 [GitHub CLI](https://cli.github.com/)；本地先安装 `gh` 并执行 `gh auth login`。脚本先验证已准备包的摘要、清单、服务和索引，再检查仓库公开状态以及远端 tag 已存在。它使用 `gh release create --verify-tag --draft`，下载上传后的资产重新校验，最后公开 Release。重试会验证同名包的完整字节，拒绝不同摘要、额外资产、被移动的 tag 和缺少资产的已公开 Release；失败的草稿可补传缺失资产，不覆盖任何资产。Release 说明记录 tag 对象摘要，缺少记录的已有 Release 要先人工审阅，脚本不会改写。

草稿恢复使用有写权限的身份分页查询 Release 列表，按 `tag_name` 唯一匹配，再按 Release ID 读取和公开；按 tag 查询的 REST 接口只能找到已公开版本。即使包已全部上传但公开前进程失败，重试也会复用同一草稿，完整校验资产后公开，不重复创建。[GitHub Release 接口说明](https://docs.github.com/en/rest/releases/releases#list-releases)

当前作者工程提供 `.github/workflows/module-release.yml`：推送经过审阅的 `modules-*` tag 后，Actions 从 tag 取出源码、作者索引和已准备包，校验完整目录，按索引下载 URL 筛选当前 tag 对应资产，下载复验后公开 Release。工作流仅需当前仓库的 `contents: write`，按 tag 串行执行。它不会移动 tag、覆盖已发布包或更新目录仓库；完成 Release 验证后再更新公开作者索引及目录。手动重试使用 `workflow_dispatch` 并指定已有 tag；必须先确保该 tag 已存在。

## 接入与依赖

当前拾光兼容模块依赖大学课表；正方、青果、URP、超星通用导入在拾光模块内选择。独立的 `app.import.zhengfang` 已从当前源码、作者索引和统一目录移除，已有安装可卸载，已发布的历史 Release 保持不可变。各条目可以由不同作者仓库提供：依赖通过模块 ID 解析，发布仓库不需要相同。客户端测试使用独立学校适配器夹具验证“学校适配器 → 拾光兼容 → 大学课表”的跨仓库安装。

模块依赖在 `manifest.dependencies` 声明 `{moduleId, version}`，服务依赖在 `manifest.serviceDependencies` 声明 `{moduleId, serviceId, majorVersion}`；现有 `services.query:<moduleId>/<serviceId>@<major>` 与 `services.command:...` 权限声明也参与服务依赖检查。客户端复用满足条件的已安装版本，补齐需要安装、升级或启用的模块，并在完整下载验证后一次确认。优先最高稳定版本，不自动降级，不自动选预发布版本。失败时显示具体版本、服务或循环冲突。

当前分发已移除收件箱和项目视图，任务与项目底层服务保留；客户端按随 APK 的退役清单过滤在线和离线旧目录条目，历史 Release 原包不改写。

离线可以查看缓存目录与已安装模块；缺失包没有下载齐全时不会开始安装。SHA-256 和包身份校验后仍执行宿主已有包格式及运行时验证。批量计划绑定包摘要和安装状态，状态变化需要重新解析；事务失败恢复数据、旧版本与启用状态。安装或更新始终由用户发起，第一版没有后台自动更新、逐权限开关或固定模块分层限制。

## 校验与维护

目录仓库运行 `python3 tools/validate.py catalog.json --online`。本地可用 `--index-dir`、`--package-dir` 校验准备好的历史索引和资产；省略两个目录且不启用 `--online` 时仅验证目录结构。网络模式检查 GitHub 固定资产及其专用 CDN 跳转，拒绝跳转到其他作者仓库。

工具中的校验是收录前检查；运行时以宿主实际校验为准。未签名包须明确显示“未签名”，任何自称官方的作者文字、仓库名称或摘要都不会绕过客户端身份保护。
