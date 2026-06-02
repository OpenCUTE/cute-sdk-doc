# Fusion 实现

`cutelib/fusion/include/cute_fusion.h` 是 tensor 层和 primitive 层之间的 adapter。它不实现新数学，只把 `cute_post_call_t` 中的 tile 信息转换成 `cute_vector_fusion.h` 的普通 buffer 参数。

## 文件位置

```text
cute-sdk/cutelib/fusion/include/cute_fusion.h
```

依赖：

```text
cute_ops.h
cute_vector_fusion.h
```

## Adapter 边界

fusion adapter 的职责：

| 输入 | 输出 |
|------|------|
| `cute_post_call_t` | primitive fusion API 参数 |
| tile src/dst/stride |普通 buffer + stride |
| `row0` / `col0` | context pointer offset |
| `env.a_scale` / `env.b_scale` | dequant scale |
| `user_ctx` | RoPE / softmax / hadamard / residual context |

fusion adapter 不负责：

- issue CUTE matmul。
- 管理 scratch buffer。
- 重新实现 dequant / softmax / RoPE / SiLU。
- 做 correctness check。

## Tile Pointer Helper

```c
static inline const void *cute_fusion_tile_ptr_const(
    const void *base,
    uint64_t stride,
    int row0,
    int col0,
    size_t elem_bytes)
```

用于从 whole tensor base 指针计算当前 tile 的 residual / lhs 指针：

```text
base + row0 * stride + col0 * elem_bytes
```

Hadamard 和 ResAdd 都依赖它把 `user_ctx` 的全局 tensor 指针切到当前 tile。

## Adapter 列表

### `cute_post_dequant_rope_bf16cvt`

用途：

```text
I32 accumulator tile
  ↓ dequant
F32 tile
  ↓ RoPE
BF16 Q/K tile
```

实现要点：

- 从 `user_ctx` 读取 base `cute_rope_ctx_t`。
- 构造 tile-local ctx。
- 当前实现中 `tile_ctx.pos = base_ctx->pos + call->tile.row0`。
- 调用 `cute_fuse_dequant_rope_bf16cvt_tile`。

### `cute_post_dequant_bf16cvt`

用途：

```text
I32 accumulator tile
  ↓ dequant
BF16 output
```

如果 `call->env.transpose != 0`，调用 transpose 版本：

```text
cute_fuse_dequant_bf16cvt_transpose_tile
```

这条路径用于 V projection 的 `v_bf16_t` 布局。

### `cute_post_masked_softmax_kvscale_bf16cvt`

用途：

```text
F32 score row block
  ↓ causal mask
  ↓ kv scale
  ↓ softmax
BF16 score
```

它直接把 `row0` / `col0` 传给 `cute_fuse_masked_softmax_kvscale_bf16cvt_tile`，让 primitive 根据全局 row/col 定位 mask。

### `cute_post_dequant_silu`

用途：

```text
I32 accumulator tile
  ↓ dequant
F32 tile
  ↓ SiLU fast
F32 output
```

用于 FFN gate projection。

### `cute_post_dequant_hadamard`

用途：

```text
I32 accumulator tile
  ↓ dequant
F32 up tile
  ↓ multiply gate tile
F32 output + row_absmax
```

实现要点：

- `lhs` 从 full `ffn_gate_f32` 按 `row0/col0` 切到 tile。
- `output_absmax` 偏移到 `base_ctx->output_absmax + row0`。
- 多个 tile 可以共同更新同一 row 的 absmax。

### `cute_post_dequant_resadd`

用途：

```text
I32 accumulator tile
  ↓ dequant
F32 tile
  ↓ add residual tile
F32 output
```

用于 attention output projection 和 FFN down projection。

## Fusion Case Layout

每个 fusion case 是一个目录、三个 binary variant：

```text
tests/fusion/fusion_matmul_dequant_resadd/
├── case.json
├── test_notile.c
├── test_nopipeline.c
└── test_pipeline.c
```

variant 语义：

| Variant | 含义 |
|---------|------|
| `notile` | 单次或直接路径，用于对照 |
| `nopipeline` | tiled matmul + 单 scratch post-op |
| `pipeline` | tiled matmul + 双 scratch post-op |

三个 variant 使用同一份 golden。runner 会把 `case:variant` 展开成独立 ELF，并分别 verify。

## 正确性原则

fusion adapter 的 correctness 关注点：

| 风险 | 检查方式 |
|------|----------|
| `a_scale` row offset 错误 | stage / fusion golden compare |
| transpose 输出地址错 | BF16 transpose fusion 和 V stage |
| `row0` / `col0` mask 坐标错 | masked softmax case |
| residual / hadamard lhs tile 指针错 | resadd / hadamard fusion case |
| row_absmax 跨 tile 累积错 | hadamard row_absmax golden |

当前设计把数学核心压到 primitive，adapter 只保留参数搬运逻辑，降低重复 bug 面。
