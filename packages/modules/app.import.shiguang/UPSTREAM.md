正方通用脚本来源：

https://github.com/ShiGuangSchedule/shiguang_warehouse/blob/ff72d1f08782df965cae110034a9d87cd91e0c07/resources/zhengfang_jiaowu/zhengfang_01.js

原作者：星河欲转。上游 commit：`ff72d1f08782df965cae110034a9d87cd91e0c07`。

`zhengfang.js` 仅将原脚本文本包装为 ES module 的字符串导出；解析逻辑未修改。保留 MIT 版权与许可于 `THIRD_PARTY_LICENSE.txt`。

桥接兼容与转换代码为本项目实现，接口参考拾光主仓库 commit `feabb68f75c4058319b449287980b5f645eb8d61`。

1.2.0 内置学校目录来自同一适配仓库 commit `c586957c077506a5182105ae3961ceff4d0223ce`：

https://github.com/ShiGuangSchedule/shiguang_warehouse/tree/c586957c077506a5182105ae3961ceff4d0223ce

包含247个学校／教务系统、269个适配项，对应261份唯一脚本。排除 `GLOBAL_TOOLS` 的演示、转换及其他应用工具。脚本正文未经修改，原作者注释完整保留，目录保存每项的维护者、来源路径与SHA-256。许可见 `warehouse/LICENSE.txt`；快照见 `warehouse/snapshot.json`。

`warehouse/scripts-*.js` 仅以字符串保存原文，选择学校后才加载相应分包。适配脚本在用户点击浏览器采集时执行，不在模块工作线程执行。学校目录随版本更新，不在运行时自动下载脚本。

重新生成（需要 Python PyYAML 及该提交的干净 Git 检出）：

```bash
python3 scripts/module_host/build_shiguang_catalog.py /path/to/shiguang_warehouse --revision c586957c077506a5182105ae3961ceff4d0223ce
```
