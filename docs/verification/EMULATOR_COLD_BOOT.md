# 模拟器冷启动脚本验证

日期：2026-10-30。范围为 `scripts/start-emulator.sh`、Windows 控制台后备实现及脚本回归测试；没有修改应用运行代码、APK 或模块。

## 问题与修复

- ADB shell 子进程会读取标准输入，导致管道中的 `y` 在确认提示之前被读走。ADB/PowerShell 子进程现在从 `/dev/null` 读取，脚本保留确认输入；新增 `--cold-boot --yes` 供已授权的自动化调用。
- 实际环境中的 Linux ADB 控制台命令存在退出码为零却返回空输出、或返回 `KO:` 而未关闭的情况。脚本检查响应并观察设备是否退出，空响应只等待三秒后转入后备关闭。
- 后备实现通过 Windows 回环控制台完成认证，先核对 `avd name`，再向已确认的目标发送 `kill`。认证信息只在进程内使用。ADB 设备消失、Windows 旧进程退出后才重新启动；关闭失败不会启动第二个实例。协议依据 [Android 官方控制台文档](https://developer.android.com/studio/run/emulator-console)。

## 检查与实际执行

`python3 -m unittest discover -s scripts/tests -p test_start_emulator.py -v` 的 47 项测试通过；Bash 语法、Windows PowerShell 语法、差异空白及仓库检查通过。回归包含确认输入被子进程读取、显式确认、取消/EOF、零退出码的 `KO`/空响应、后备认证或目标失败、退出超时、错误端口/AVD、普通复用、刷新率及恢复设置。

在真实 Windows 控制台执行错误 AVD 的关闭请求时，后备实现先拒绝目标，没有关闭设备。随后实际执行 `scripts/start-emulator.sh --cold-boot --yes`：

- AVD 为 `Medium_Phone_API_37.0`，设备为 `emulator-5554`。
- 旧进程 `49960 / 43064` 已退出，新进程为 `2220 / 35068`；Android 启动 ID 由 `d702c9d0-521b-4cd3-bf35-9beefc5e0e5c` 变为 `71779510-a08f-4910-8d8b-5942c92667b1`。
- 两个新进程均带 `-no-snapshot-load`，没有 `-wipe-data`；`sys.boot_completed=1`，启动动画已停止。
- APK SHA-256 前后一致。重新打开日程后，已有任务、课程和导航可见，没有清除应用或模块数据。
- 真实管道输入 `n` 正常取消，普通无参数启动复用当前实例；两个流程均正常退出。

本机日志、前后进程/启动标识、APK 摘要、截图与 XML 位于 `.cache/emulator-start/cold-boot-verification/`，测试日志位于 `.cache/emulator-start/cold-boot-tests.log`，这些本机产物不提交。交互式确认路径由回归测试覆盖，本次真实冷启动使用显式 `--yes`。
