# BERT / LLaMA 阶段迁移

迁移来源为 `cutetest/transformer_test/bert` 与 `cutetest/transformer_test/llama`。以下编号标识原实验的计算阶段，不代表完整模型推理已验收。

| 阶段 | 原实验 | 计算和输出 |
|---|---|---|
| B1 | ibert / ibert-base 1 | INT8 Q/K/V 投影，饱和量化，V 转置 |
| B2 | 2 | 逐 head QKᵀ，整数 softmax |
| B3 | 3 | 概率乘 V，head 输出拼接 |
| B4 | 4 | 输出投影，整数 LayerNorm，残差 |
| B5 | 5 | FF1、行 bias、整数 GELU |
| B6 | 6 | FF2、行 bias、整数 LayerNorm、残差 |
| L1 | llama3_1B 1 / 8 | attention / FFN RMSNorm，按 token scale，INT8 量化 |
| L2 | 2 / 3 / 4 | Q/K/V INT8 投影、反量化、Q/K RoPE、V 转置，FP16 输出 |
| L3 | 7 | attention context 量化、输出投影、FP32 残差 |
| L4 | 9 / 10 / 11 | gate + SiLU、up + Hadamard、量化、down + 残差 |

原始 BERT 小模型为 S=128、H=512、F=1024、4 heads；base 为 S=128、H=768、F=3072、12 heads。LLaMA 为 S=128、H=2048、F=8192、32 Q heads / 8 KV heads、head dim=64。快速回归使用较小形状，保留多 head、分块和非零输入；原始形状与快速形状的验收分别记录。

LLaMA 旧文件的部分融合名称含 BF16，但对应旧阶段实际执行 FP16 转换。迁移以真实指令与存储格式为准。INT8 主线允许 CPU/RVV 浮点归一化、反量化和激活；它不意味着已经实现 CUTE 浮点矩阵 QEMU 模型。

BERT 的整数 wrap、RNE 转换、饱和以及 LayerNorm 后加残差的顺序须保留。确认的旧代码缺陷单独列在迁移说明中，不用零输入掩盖。L5/M2 浮点矩阵 attention 不属于本轮；ResNet/X2 永久搁置，X1/X3 留待后续。

当前阶段验收结果以生成的 case 和运行报告为准，参见 [当前状态](../reference/status.md)。
S/H/F 分别表示序列长度、hidden width 和 FFN width；快速 profile 为 64/128/256，
包含 2 个 Q/BERT heads 和 1 个 LLaMA KV head。

## 代码与运行入口

迁移 kernel 位于 `cute-sdk/cutelib/primitive/include/cute_model_stages.h`，形状、
任务、输入和独立 oracle 由 `cute-sdk/tests/models/generate.py` 生成。维护说明在
该目录 `README.md`。OpenCUTE 根目录使用 `tools/runner/cute-model-build.py`
和 `cute-model-run.py` 构建/运行；命令见 [模型构建](/build-system/#model-builds) 和
[模型运行](/running/#model-runs)。直接复制旧 `.c` 不会自动获得这些任务边界。

本轮以正确性为目标：DDR 上串行提交 64×64 tile，在任务完成后检查全部输出。
旧实验中的 TCM、流水线和 double-buffer 调度不作为已迁移性能能力。scale 也通过
RVV store 写出并参与校验。LLaMA RMSNorm 明确采用 64-lane 分组再有序归约；
SiLU 使用 SDK exp 多项式和两次 Newton 修正倒数。这些数值实现选择与旧版本的
无序归约/逐元素除法有差别，会记录 QEMU 对数学 reference 的误差。

生成的 `case.json` 对浮点 reference 标明容差，仅用于校准 QEMU；RTL/QEMU 比较
没有容差。缺少任何一个输出的新写 ack、额外未声明写入、未知读数据或不完整
收尾都拒绝通过。模型输入为确定的非零测试数据，不是训练权重，也不衡量模型精度。

扩展阶段时参见 [case 与 checkpoint 接入](model-case.md)。

## 验收结果与证据

2026-10-28 的模型验收为 **28/28 通过**，包括快速形状、BERT small/base 和
LLaMA-1B 原始形状，以及快速 L2/L4 延迟测试。逐组任务数、输出字节数和附加
正负测试统一维护在主站 [模型验收表](/status/#model-acceptance)。

原始 L4 的最终结论来自独立离线回放；原超时报告仍保留。实际报告路径、构建
身份、回放来源与本机验收包位置见 [证据与复核](/status/#evidence)。本次使用 DDR
串行 tile 和确定的非零输入，范围不包含完整模型精度、旧 TCM/double-buffer 性能
迁移或 CUTE 浮点矩阵。
