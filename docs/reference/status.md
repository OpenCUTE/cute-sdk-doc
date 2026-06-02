# 当前状态

这一页不是给新人第一眼就看的入口，而是给已经顺着前面读下来的人一个“当前做到哪里了”的快照。

它回答两个问题：

1. 这套 SDK 目前哪些部分已经比较稳定。
2. 哪些地方仍然需要带着风险意识去改。

## 已经比较稳定的部分

| 模块 | 状态 | 说明 |
|------|------|------|
| `cutelib/runtime` | 稳定 | runtime wrapper 和基础 query / wait 语义已经固定 |
| `cutelib/tensor` | 稳定 | tiled matmul、post-op callback、pipeline/no-pipeline 入口已可用 |
| `cutelib/primitive` | 稳定 | LLaMA 当前依赖的 RVV primitive 已经落齐 |
| `cutelib/fusion` | 稳定 | tensor tile output 到 vector post-op 的 adapter 已经可跑 |
| `memverify` trace path | 稳定 | compact trace rebuild + bit exact / tolerance compare 已可用 |
| `cute-test.py` | 稳定 | suite、variant、timeout、`--skip-run` 已可用 |

## 当前最重要的已知结果

`llama_layer_nonzero_stages.yaml` 当前已经确认：

```text
7/7 passed
```

这件事很重要，因为它意味着：

- Q/K/V projection BF16 路径已经过了。
- score head0 softmax BF16 路径已经过了。
- FFN gate / up / down 的 F32 路径已经过了。

所以当前如果 full block 还有问题，怀疑范围已经明显缩小，不再是“所有基础算子都不确定”的状态。

## 当前验证策略

| 类型 | 当前策略 |
|------|----------|
| F32 | `0.05%` relative tolerance |
| BF16 | `0.5%` relative tolerance + `1 ULP` |

这是一个有意识的工程选择，不是“先随便放宽再说”：

- 对 F32，我们仍然要求很紧的数值一致性。
- 对 BF16，我们承认其离散步长和 truncation 现实。

## 还需要保持警惕的地方

下面这些点，改代码时仍然容易出问题：

| 风险点 | 为什么容易出错 |
|--------|----------------|
| transpose 布局 | 输出地址计算和 scale 对齐都容易错 |
| per-token scale 偏移 | `row0` / tile offset 一旦重复叠加就会错 |
| half-finished trace | 没有 `$finish` 的 trace 不能用来判断 correctness |
| golden 更新但 ELF 没重链 | 会出现“代码对了但跑出来还是旧结果”的错觉 |
| BF16 bit mismatch | 很容易把本来合理的 1 ULP 差异误判成错误 |

## 接下来最自然的工作方向

从当前状态往后走，比较自然的方向是：

1. 继续把 full LLaMA block 跑稳。
2. 在 correctness 稳定后，再看性能和 trace 热点。
3. 继续把文档、golden generator 和测试组织做得更对新人友好。
