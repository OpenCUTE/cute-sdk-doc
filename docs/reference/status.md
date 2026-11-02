# 当前状态

更新时间：2026-10-28。源文件存在、编译成功、单元测试通过和端到端验收是不同的状态。

| 范围 | 已有证据 | 边界 |
|---|---|---|
| S1 system 验证 | DDR RVV→CUTE→RVV、TCM、延迟 ack 正例；提前 marker、错误输出负例；在线/离线一致 | 单 hart、INT8 CUTE、64 字节对齐 |
| C++ verifier | 27 项合成协议测试及 7 项真实日志负例 | 不能替代所有工作负载的 RTL 回归 |
| SDK 构建 | S1 时 73 个目标完成编译 | 不表示 73 个目标均通过仿真 |
| BERT B1–B6 / LLaMA L1–L4 | 28 项阶段/形状/延迟验收通过，在线/离线一致 | DDR 串行 tile，非完整模型精度与旧流水线性能验收 |
| 浮点矩阵 QEMU | 未完成 | 等待 FPE 数值契约，不能用 INT8 验收外推 |
| 多 hart / CPU 数据写入跟踪 | 未完成 | 当前 profile 不依赖 CPU 写模型输出 |

[System-level 验证](../testing/system-verification.md) 说明新流程的通过条件。[阶段迁移](../testing/workload-migration.md) 说明模型范围。历史 suite 页面中的数量和性能只描述其记录时的配置，不作为当前工作树的通过证明。

## 验收结果与证据

2026-10-28 的模型验收为 **28/28 通过**，包括快速形状、BERT small/base 和
LLaMA-1B 原始形状，以及快速 L2/L4 延迟测试。逐组任务数、输出字节数和附加
正负测试统一维护在主站 [模型验收表](/status/#model-acceptance)。

原始 L4 的最终结论来自独立离线回放；原超时报告仍保留。实际报告路径、构建
身份、回放来源与本机验收包位置见 [证据与复核](/status/#evidence)。本次使用 DDR
串行 tile 和确定的非零输入，范围不包含完整模型精度、旧 TCM/double-buffer 性能
迁移或 CUTE 浮点矩阵。
