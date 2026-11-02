# CUTE SDK：软件接口、计算库与测试

CUTE SDK 提供 CUTE/RVV 裸机程序使用的指令接口、运行时、计算库和测试工具。
本文档介绍软件分层、调用方式、程序构建及结果验证。系统集成关系见
[核心模块简介](/modules/#sdk)。

## 软件分层与接口

SDK 接收平台、ISA、输入布局和数值约定。runtime 负责提交与等待，tensor 组织矩阵
和分块，primitive 实现数值核，fusion/layer 组合更大的计算阶段。

| 消费者 | SDK 提供的内容 | 双方需要一致的约定 |
|---|---|---|
| CPU 与 CUTE/RVV 硬件 | 裸机程序、配置和任务序列 | 指令、平台、布局和完成语义 |
| QEMU / 独立 reference | 同一计算的程序、输入和数值规则 | 运算、舍入、近似及适用范围 |
| Trace / verify | checkpoint、任务顺序与全部输出描述 | 哪项任务何时完成，哪些结果必须被观察和比较 |
| 软件开发与测试 | API、case 和已验证范围 | 接口兼容性与回归测试范围 |

## 结果验证

当前系统级流程将同源程序编译为 QEMU 和 Verilator ELF，用独立 reference 校准
QEMU，再从 RTL 的请求及成功写 ack 重建实际内存，逐任务比较全部输出。
多个输出、临时数值和完成顺序都应在相应契约中明确。

旧 suite / memverify 仍用于已有测试开发，具有自己的比较模式和覆盖范围。
选择流程前先明确本次目标，详见 [系统级验证](testing/system-verification.md) 和
[当前状态](reference/status.md)。

## 使用与开发入口

| 操作 | 文档入口 |
|---|---|
| 了解软件分层与基本概念 | [整体图景](architecture.md)、[概念对齐](concepts.md) |
| 编译并运行第一项测试 | [第一次上手](getting-started.md) |
| 为一个新阶段定义输入、输出和完成条件 | [模型 case](testing/model-case.md) |
| 理解 BERT/LLaMA 阶段如何迁移 | [迁移说明](testing/workload-migration.md) |
| 修改某一层软件实现 | [Cutelib 总览](cutelib/primitive-and-fusion.md) |
| 维护既有 suite 和 golden | [测试组织](testing/index.md)、[Runner](testing/runner.md)、[Golden](testing/golden-and-memverify.md) |

主文档的 [配置 SoC](/practice-config/) 与 [BERT 阶段实践](/practice/) 展示整个系统
如何构建并运行 SDK 程序。平台配置、生成产物与依赖检查见
[Config-first 对象与依赖](/config-architecture/)。
