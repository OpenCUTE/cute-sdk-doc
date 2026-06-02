# CUTE SDK 文档

如果把 CUTE 整体看成一套“硬件加速器 + 软件开发栈”，那么 `cute-sdk` 就是我们最常接触的软件这一半：

- 它提供调用硬件的库函数。
- 它提供 reference 对照用的 golden 数据。
- 它提供测试组织方式。
- 它提供从 Verilator trace 重建 memory 并做正确性比较的工具。

这套文档的目标，是让第一次接触 CUTE 的人也能在较短时间里知道：

1. CUTE SDK 到底像什么。
2. 该先跑哪组测试。
3. pass/fail 到底意味着什么。
4. 想改某一层代码时，应该去哪里看。

## 先给一个直觉

如果你熟悉这些东西，可以先这样类比：

| 你熟悉的概念 | 在 CUTE 里大致对应什么 |
|--------------|-------------------------|
| CUDA kernel launch / device API | `cutelib/runtime` |
| cuBLAS / tiled GEMM wrapper | `cutelib/tensor` |
| activation / norm / softmax 这类后处理 kernel | `cutelib/primitive` |
| GEMM 输出接 activation 的 epilogue / post-op | `cutelib/fusion` |
| 模型层的代码块级组合 | `cutelib/layer` |
| NumPy / PyTorch reference 输出 | `golden/manual/*` |
| 单元测试清单 / CI job list | `tests/*.yaml` |
| 单个测试的 manifest | `tests/**/case.json` |
| 仿真后的可验证结果 | `run.out` compact trace |
| host 端 `assert allclose` | `memverify` |

这不是逐字等价，但对第一次建立感觉很有帮助。

## 我们平时到底在做什么

平时开发里最常见的一条链路是：

```text
写 / 改 cutelib 代码
  ↓
跑某个 suite YAML
  ↓
Verilator 跑出 run.out trace
  ↓
memverify 从 trace 重建输出内存
  ↓
和 golden 做 bit-exact 或 tolerance compare
  ↓
得到 pass / fail
```

所以这套文档不是单纯的“代码 API 手册”，它更像三样东西合在一起：

- 一份入门地图。
- 一份测试与验证说明。
- 一份实现层次的对照表。

## 推荐阅读顺序

| 章节 | 建议什么时候看 |
|------|----------------|
| `整体图景` | 想先知道这套仓库整体在做什么 |
| `概念对齐` | 对 CUTE 术语还没有感觉 |
| `跑通第一组测试` | 想先上手，不想先啃实现细节 |
| `一个 Case 的完整旅程` | 想理解一条测试为什么会 pass/fail |
| `测试组织` | 想写新 case 或改 suite |
| `可运行验证` | 想知道现在有哪些 suite 可以直接跑 |
| `SDK 实现` | 已经知道整体流程，开始看具体代码 |

## 当前最值得先跑的验证

对新人最友好的起点通常是：

1. `vecprimitive.yaml`
2. `vecfusion.yaml`
3. `fusion.yaml`
4. `llama_layer_nonzero_stages.yaml`

其中 `llama_layer_nonzero_stages.yaml` 当前已经确认 `7/7 passed`，很适合用来理解 BF16 / F32 tolerance、长跑 trace 和 `--skip-run` 的实际用法。
