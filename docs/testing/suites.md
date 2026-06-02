# 可运行验证

这页回答一个很实际的问题：

```text
现在这套仓库里，哪些测试是可以直接跑的？
我应该先跑哪个？
正常结果应该长什么样？
```

默认工作目录：

```bash
cd /root/opencute/CUTE
```

## 推荐顺序

如果你是第一次接触这套仓库，推荐按这个顺序跑：

```text
vecprimitive
  ↓
vecfusion
  ↓
fusion
  ↓
llama_layer_nonzero_stages
```

这个顺序背后的考虑很简单：

- 从最小粒度的数学算子开始。
- 再到纯向量组合。
- 再到 matmul + post-op 的连接。
- 最后再到 LLaMA stage 组合。

这样一旦 fail，定位范围会小很多。

## `vecprimitive.yaml`

命令：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/vecprimitive.yaml \
  --skip-build
```

它覆盖的是最基础的一层：

- `exp / sin / cos`
- dequant
- SiLU
- residual add
- hadamard
- RoPE
- masked softmax
- smoothquant
- RMSNorm

正常结果预期：

```text
13/13 passed
```

如果你刚加入项目，最适合先跑它，因为它最接近“单元测试”。

## `vecfusion.yaml`

命令：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/vecfusion.yaml \
  --skip-build
```

它验证的是 pure vector fuse kernel，也就是不依赖 matmul 调度的组合路径：

- dequant + SiLU
- dequant + residual add
- dequant + BF16 convert
- dequant + RoPE + BF16
- dequant + hadamard
- masked softmax + kv scale + BF16

正常结果预期：

```text
6/6 passed
```

## `fusion.yaml`

命令：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/fusion.yaml \
  --skip-build
```

这里开始验证“matmul 输出如何接到 post-op”。

suite 里每个 fusion case 通常会自动展开成三个 variant：

```text
notile
nopipeline
pipeline
```

所以你在 YAML 里看到 6 个 case，实际 runner 往往会展开成 18 个 binary 运行。

正常结果预期：

```text
18/18 passed
```

如果这里 fail，而 `vecprimitive.yaml` 和 `vecfusion.yaml` 都是绿的，那么问题更可能出在：

- tile 地址计算
- post-op adapter
- transpose 布局
- scale 或 residual 的偏移

而不是数学本身。

## `fusion_attention.yaml`

命令：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/fusion_attention.yaml \
  --skip-build
```

它更偏向 attention 特有路径：

- 更大 shape 的 masked softmax + kv scale
- attention context matmul

正常结果预期：

```text
6/6 passed
```

## `fusion_llama_layout.yaml`

命令：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/fusion_llama_layout.yaml \
  --skip-build
```

这个 suite 主要用来验证 LLaMA 里比较敏感的 layout 路径，比如 BF16 transpose 输出。

正常结果预期：

```text
3/3 passed
```

## `llama_layer_nonzero_stages.yaml`

这是当前最值得新人重点理解的一组测试。

命令：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/llama_layer_nonzero_stages.yaml \
  --skip-build
```

如果 trace 已经完整跑过，也可以只做 verify：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/llama_layer_nonzero_stages.yaml \
  --skip-build \
  --skip-run
```

这组 suite 覆盖：

- Q projection
- K projection
- V projection transpose
- score head0 softmax
- FFN gate
- FFN up
- FFN down

当前已经确认结果：

```text
7/7 passed
```

更重要的是，这组 suite 很适合拿来理解三件事：

1. BF16 为什么不总是 bit exact。
2. F32 近似数学为什么也可能只做 tolerance compare。
3. trace 很慢时为什么 `--skip-run` 很有价值。

## `smoke.yaml`

命令：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/smoke.yaml \
  --skip-build
```

它主要覆盖 runtime / tensor 基础路径：

- 基础 INT8 matmul
- transpose matmul
- MXFP 路径
- tiled matmul FIFO
- CPU memcpy 路径

它更像底层回归集，适合确认整个 SDK 的最基础运行链路没有坏。

## Full Layer Suites

还存在几组更重的 LLaMA layer suite：

- `llama_layer.yaml`
- `llama_layer_full.yaml`
- `llama_layer_nonzero_full.yaml`

这些 suite 不适合作为新人的第一组测试，原因很现实：

- 跑得久。
- 中间环节多。
- fail 时定位范围大。

更好的方式是：

1. 先把 `llama_layer_nonzero_stages.yaml` 跑绿。
2. 再去看 full block。
