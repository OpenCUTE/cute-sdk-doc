# Cutelib 总览

`cutelib` 是 `cute-sdk` 里最像“开发者真正会直接写和改的代码”的部分。可以先把它理解成：

```text
一套把 CUTE 硬件能力包装成可组合软件接口的库
```

第一次看 `cutelib` 时，最容易困惑的地方通常不是函数名字，而是不知道为什么要分这么多层。先别把它想得太神秘，按大家更熟悉的软件栈去理解就行：

- 最底层先把硬件指令包成函数。
- 中间层把单次 matmul 变成 tensor 级接口。
- 再往上把 activation、RoPE、softmax 这类通用后处理做成可复用小积木。
- 最后把这些积木拼成 LLaMA 这样的真实模型层。

## 先看一张图

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

这条链路可以粗略地理解成：

| 层 | 更像什么 | 它主要解决的问题 |
|----|----------|------------------|
| `runtime` | 最底层 device API | 我怎么把参数配置到硬件并发出一条 CUTE 宏指令 |
| `tensor` | tiled GEMM wrapper | 我怎么把大矩阵切 tile，怎么组织 matmul 调度 |
| `primitive` | activation / norm / softmax kernel | 单个向量算子怎么实现和验证 |
| `fusion` | epilogue / post-op adapter | matmul 输出怎么接到后处理 |
| `layer` | 模型层组合逻辑 | 一整个 LLaMA block 怎么拼出来 |

## 为什么不直接写一层到位

因为如果不分层，一旦 full block fail，你会很难知道问题到底出在哪里。

常见的出错点可能有：

- matmul 输出地址不对
- dequant scale 偏移错
- transpose 布局错
- RoPE / softmax / SiLU 数学逻辑有问题
- residual 或 hadamard 的 tile 切片错
- layer 组合顺序错

把 `cutelib` 分层以后，验证顺序就可以变成：

1. `primitive` 先独立验证数学。
2. `fusion` 再验证 matmul 和 post-op 的连接。
3. `layer` 最后验证整层组合。

## 和测试怎么对应

理解 `cutelib` 最有效的方式，不是只看代码，而是把代码和 suite 对起来看：

| 层 | 最相关的 suite |
|----|----------------|
| `runtime` / `tensor` | `smoke.yaml` |
| `primitive` | `vecprimitive.yaml` |
| `primitive` 中的 pure vector fusion | `vecfusion.yaml` |
| `fusion` | `fusion.yaml`、`fusion_attention.yaml`、`fusion_llama_layout.yaml` |
| `layer` | `llama_layer_nonzero_stages.yaml`、`llama_layer_full.yaml` |

这件事很实用，因为它告诉你：

- 想确认一个单独向量算子是不是算对了，就先别跑 full block，去看 `vecprimitive.yaml`。
- 想确认 matmul 输出接 post-op 这件事有没有问题，就去看 `fusion.yaml`。
- 想确认 LLaMA stage 组合是不是对的，就去看 `llama_layer_nonzero_stages.yaml`。

## 第一次看代码时建议怎么读

如果你第一次准备进 `cutelib` 看实现，推荐顺序是：

1. `runtime`
2. `tensor`
3. `primitive`
4. `fusion`
5. `layer`

这个顺序有两个好处：

- 它和抽象层次从低到高的顺序一致。
- 它也和测试从简单到复杂的顺序一致。

这样读到后面时，前面的概念已经有支点了，不容易出现“每个函数都看懂了，但还是不知道整套东西怎么连起来”的情况。
