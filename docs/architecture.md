# 整体图景

先不要急着看实现细节。第一次接触 CUTE SDK，更重要的是先知道这套仓库在整个系统中的位置。

## 一句话版本

`cute-sdk` 是 CUTE 的软件开发与验证层。

它做四件事：

1. 用库函数把硬件指令包装成更容易调用的接口。
2. 组织测试 case 和 suite。
3. 管理 golden 参考数据。
4. 从硬件仿真 trace 重建 memory，并在 host 端判断正确性。

## 在整个 CUTE 仓库里的位置

可以把它粗略看成这样：

```text
CUTE/
├── configs/      # 各种配置和版本描述
├── tools/        # 运行、构建、trace 相关工具
├── trace/        # compact trace 的 catalog / parser / decoder
├── chipyard/     # 硬件侧工程
└── cute-sdk/     # 软件开发与验证层
```

如果从“写代码的人”的角度看：

- 你平时最常改的是 `cute-sdk/cutelib/*`
- 最常跑的是 `cute-sdk/tests/*.yaml`
- 最常看的结果是 `build/chipyard_runs/.../run.log` 和 `run.out`

## `cute-sdk` 里面有什么

```text
cute-sdk/
├── cuteisa/      # ISA 相关头文件和产物
├── ops/          # 算子语义契约
├── memverify/    # host 端 memory compare
├── cutelib/      # 给 CUTE 写程序时用的库函数
├── tests/        # case 与 suite
├── golden/       # golden 数据和生成脚本
├── plans/        # 分阶段实现计划
└── CMakeLists.txt
```

最实用的理解方式不是背目录名，而是记住每个目录回答的问题：

| 目录 | 它回答什么问题 |
|------|----------------|
| `cutelib/` | 我怎么调用硬件，怎么组织算子 |
| `tests/` | 我要跑哪些 case，怎么跑 |
| `golden/` | 正确答案是什么 |
| `memverify/` | 仿真输出和正确答案是否一致 |
| `tools/runner/` | 怎么把 build、run、verify 串起来 |

## `cutelib` 为什么要分层

`cutelib` 当前分成几层：

```text
runtime
  ↓
tensor
  ↓
primitive
  ↓
fusion
  ↓
layer
```

按熟悉的软件概念理解：

| 层 | 更像什么 |
|----|----------|
| `runtime` | 最底层 device API / 指令包装 |
| `tensor` | tiled matmul / tensor operator wrapper |
| `primitive` | activation、RoPE、softmax、RMSNorm 这类向量算子 |
| `fusion` | GEMM 输出接后处理的 epilogue adapter |
| `layer` | 把多个算子拼成一层，例如 LLaMA block |

## 正确性是怎么判断的

这里最重要的一点是：

**正确性判断主要在 host 端完成，不在 `test.c` 里完成。**

一条典型链路是：

```text
test.c 调 cutelib
  ↓
Verilator 跑出 run.out trace
  ↓
memverify 从 trace 重建 memory
  ↓
和 golden 比较
  ↓
pass / fail
```

这么做的好处是：

- 仿真里不做昂贵的大规模 compare。
- trace 一旦完整，很多验证可以反复在 host 上重跑。
- fail 时能拿到更清楚的 mismatch 报告。
