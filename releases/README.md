# 不可变模块发布包

`modules/` 保存当前作者版本索引 `module-index/` 引用的版本化 `.xmodule` 原始包，包括仍被索引引用的历史版本。它们随源码提交，使干净检出的目录校验和 GitHub Actions 发布流程可核验完整字节、清单、服务与 SHA-256；客户端从索引中的 GitHub Release 地址下载。

包名为 `<模块 ID>-<版本>.xmodule`。已发布包必须保持原始字节；修改模块时提升语义版本，生成新包并追加索引，不能覆盖同版本包。准备和发布命令见 [模块作者发布流程](../docs/MODULE_CATALOG.md)。`release.py` 自动按索引下载 URL 中的 tag 筛选并验证单次 Release 的资产；`--stage-dir` 可先完成纯本地准备，不把目录内所有历史包上传到新 Release。

当前目录整理只改变源码仓库中的包路径。旧 tag、已有 GitHub Release、下载 URL 和包摘要保持不变；旧 tag 仍包含当时的目录布局与工作流。当前分支的手动发布工作流使用当前工具校验指定 tag 快照，并兼容旧包目录。历史文档中的 `dist/module-releases/` 指当时的路径，当前入口为 `releases/modules/`。

`dist/` 整体由 Git 忽略，用于本机临时打包、APK、下载缓存、截图和完整验收记录。没有当前作者索引引用的旧模块包可留在本机 `dist/`，不复制到此目录。默认资源包仍在 `client/assets/modules/`，模块源码仍在 `packages/modules/`。
