# 不可变模块发布包

`modules/` 保存当前作者版本索引 `module-index/` 引用的版本化 `.xmodule` 原始包，包括仍被索引引用的历史版本。它们随源码提交，使干净检出的目录校验和 GitHub Actions 发布流程可核验完整字节、清单、服务与 SHA-256；客户端从索引中的 GitHub Release 地址下载。

包名为 `<模块 ID>-<版本>.xmodule`。已发布包必须保持原始字节；修改模块时提升语义版本，生成新包并追加索引，不能覆盖同版本包。准备和发布命令见 [模块作者发布流程](../docs/MODULE_CATALOG.md)。`release.py` 自动按索引下载 URL 中的 tag 筛选并验证单次 Release 的资产；`--stage-dir` 可先完成纯本地准备，不把目录内所有历史包上传到新 Release。

当前包目录为 `releases/modules/`，本机发布暂存为 `dist/releases/modules/<发布标签>/`。手动发布工具兼容旧 tag 快照及其包目录，保持已有下载 URL 和包摘要。

`dist/` 整体由 Git 忽略，用于本机临时打包、APK、下载缓存、截图和完整验收记录。没有当前作者索引引用的旧模块包可留在本机 `dist/`，不复制到此目录。默认资源包仍在 `client/assets/modules/`，模块源码仍在 `packages/modules/`。
