# System-level 验证

本流程用同一份 C 源码分别生成裸机 QEMU 和 Verilator ELF。当前两平台都使用 HTIF，共享 ISA/ABI 选项，两个编译目标的 ELF 允许相同。QEMU 在每个任务的 checkpoint 导出**全部声明输出**，host 从 RTL 的 CUTE/RVV 写请求及成功 ack 重建内存，并逐字节比较。CPU 不读回大块输出，也不通过 UART 输出数据。

## 软件任务边界

```c
cute_checkpoint_context ctx = {0};
uint64_t task = cute_matmul(/* 地址、维度、类型 */);
cute_wait_task(task);
if (!cute_checkpoint(&ctx, 1)) return 1;
/* 下一个任务可读取前一个任务的输出。 */
cute_checkpoint_finish();
```

这是调用顺序示意，完整可编译例子在 `cute-sdk/tests/system/system_int8.c`。`cute_checkpoint` 在标记前后执行 fence，并消费 TRACE_MARK 的返回值；调用者仍须先等待 CUTE 任务完成。当前实现只验收单 hart、标记处清空该 hart 请求的 profile，不能据此推断跨核同步已经成立。

`case.json` 逐任务声明 hart、单调 seq、key 和输出符号。runner 分别解析两个 ELF 的符号，检查长度及 64 字节对齐。每个输出字节必须有本任务的新写 ack；输入来自 ELF 初始段，未知内存不会默认当作零。输出重用需要再次声明其新版本。

## 构建和运行

从 OpenCUTE 根目录使用 `tools/runner/cute-system-build.py`，它构建 SDK、QEMU、C++ verifier 和对应硬件 simulator，并记录 `build-manifest.json`。随后使用 `tools/runner/cute-system.py` 指定 manifest、两个 ELF、case、fixtures 和工具路径。完整命令见主文档的 [构建系统](/build-system/) 与 [运行程序与结果](/running/)。

每次运行创建独立目录，记录 QEMU 命令、golden、输入内存、任务地址映射、RTL trace、在线及离线报告。源码或产物与 manifest 不一致时拒绝运行。一次在线执行结束后，还会离线重放同一份 trace，要求报告相同。

## 结果含义

- `PASS`：全部任务输出相同，任务、请求/响应、marker 返回和各端口最终 watermark 完整，程序成功退出。
- `FAIL`：数值不同或协议违规，例如交叉访问未完成的输出、提前标记、遗漏写入。
- `INVALID` / runner 错误：缺文件、输入无效、构建身份不符等，不能当作通过。

QEMU 与独立 NumPy reference 的校准和 RTL 与 QEMU 的逐字节比较是两项检查。浮点参考所用容差必须在 case 中明示；RTL 比较始终精确到字节。

历史 suite runner / memverify 的最终内存检查仍可用于开发，但不自动具备本流程的 ack 配对、任务版本及日志完整性保证。参见 [迁移范围](workload-migration.md) 和 [状态](../reference/status.md)。

## 近似计算之后的整数阶段

L4 的 SiLU 与数学 reference 之间允许显式声明的微小误差，该误差可能跨过下一步
INT8 量化的舍入边界。因此 L4 使用逐阶段组合校准：先校准上游浮点任务，再以
已通过校准的上游数据为输入，用独立 NumPy 运算计算 Hadamard、scale、量化和
后续 GEMM 的 reference。整数输出仍精确比较，不能用容差吞掉差一的结果。

`oracle_expression` 只能引用先前已经校准成功的任务输出和已哈希的输入文件；
引用本任务或未来任务会报错。每项派生 reference 及哈希保存在 `calibration/`。
这项数学模型校准与 RTL byte-exact 检查分开记录，不宣称近似激活与原精确除法
在所有输入上逐位相同。

大日志的离线分析使用单独的 `--replay-timeout`（默认 600 秒）。RTL 已正常完成
时，`cute-system-replay.py --run ... --verifier ... --out ...` 可在新目录重新回放，
保留原报告，并核对原在线结果；不能用此入口把缺 footer 或异常退出的运行当成成功。
