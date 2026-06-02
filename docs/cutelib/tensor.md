# Tensor 实现

`cutelib/tensor` 在 runtime 之上增加 tensor descriptor、tiled matmul 和 post-op callback。它仍然不实现具体 vector 数学，只负责把大 tensor 切成 CUTE tile，并把每个 tile 的输出交给可选 post-op。

## 文件位置

```text
cute-sdk/cutelib/tensor/include/
├── cute_tensor.h
└── cute_ops.h
```

## Tensor Descriptor

`cute_tensor_t`：

```c
typedef struct {
    void    *data;
    uint64_t stride;    /* byte stride per row */
    uint64_t rows;
    uint64_t cols;
    uint64_t dtype;
} cute_tensor_t;
```

`stride` 始终是 byte stride。输入 stride 可用 `cute_stride(cols, dtype)` 计算；CUTE matmul 原始输出通常是 I32/F32 accumulator，因此 `cute_output_stride(cols)` 返回 `cols * 4`。

## Bias 与 Scale

`cute_tensor.h` 定义：

| 宏 | 含义 |
|----|------|
| `CUTE_BIAS_ZERO` | bias 视作 0 |
| `CUTE_BIAS_ROW_REPEAT` | bias 按 row repeat |
| `CUTE_BIAS_FULL` | full bias tensor |
| `CUTE_SCALE_NONE` | 不使用 scale |
| `CUTE_SCALE_PERTOKEN_A_PERTENSOR_B` | A per-token scale + B per-tensor scale |

LLaMA 的 INT8 projection 主要使用：

```text
CUTE_SCALE_PERTOKEN_A_PERTENSOR_B
CUTE_BIAS_ZERO
```

## Single Tile Wrapper

`cute_matmul_op`：

```text
cute_tensor_t a/b/bias/output
  ↓
cute_matmul(...)
```

`cute_blockscale_matmul_op`：

```text
cute_tensor_t a/b/bias/output + scale_a/scale_b
  ↓
cute_blockscale_matmul(...)
```

这两个 API 只是 descriptor 到 runtime 参数的轻量适配。

## Post-op Call ABI

post-op 通过 `cute_post_call_t` 传递 tile 信息：

```c
typedef struct {
    void *src;
    void *dst;
    uint64_t src_stride;
    uint64_t dst_stride;
    int rows;
    int cols;
    int tile_i;
    int tile_j;
    int row0;
    int col0;
} cute_post_tile_t;

typedef struct {
    float *a_scale;
    float *b_scale;
    int scale_type;
    int bias_mode;
    int transpose;
} cute_post_env_t;
```

`cute_run_post_op_shape()` 负责构造 call，并把 `a_scale` 自动偏移到当前 tile row：

```text
call.env.a_scale = a_scale ? a_scale + row0 : NULL
```

因此 fusion adapter 内不能再次叠加 `row0`，否则 per-token scale 会错位。

## Tiled Matmul

### Direct-write Path

当 `post_op == NULL` 时，CUTE 直接写最终 output：

```text
issue tile 0 -> output tile 0
wait tile 0
issue tile 1 -> output tile 1
...
wait last tile
```

这个路径用于普通 tensor matmul 或 attention context 这种不需要 CPU post-op 的情况。

### No-pipeline Post-op Path

`cute_tiled_matmul_no_pipeline_ex()` 使用一个 scratch tile：

```text
issue tile n -> double_buf
wait tile n
CPU post_op(double_buf -> output tile n)
issue tile n+1 -> double_buf
```

特点：

| 项 | 说明 |
|----|------|
| scratch 数量 | 1 |
| CUTE compute 与 CPU post-op | 不重叠 |
| 优点 | 简单，便于定位 correctness |
| 缺点 | 性能较低 |

### Pipeline Post-op Path

`cute_tiled_matmul_pipeline_ex()` 使用两个 scratch tile：

```text
issue tile 0 -> buf0
wait tile 0
issue tile 1 -> buf1
CPU post_op(buf0 -> output tile 0)
wait tile 1
issue tile 2 -> buf0
CPU post_op(buf1 -> output tile 1)
...
```

特点：

| 项 | 说明 |
|----|------|
| scratch 数量 | 2 |
| CUTE compute 与 CPU post-op | 可以重叠 |
| FIFO drain | 仍然按 issue 顺序 |
| fallback | 如果没有 post-op 或双 buffer 不完整，退回 no-pipeline |

## Output Layout

tensor 层通过 `_TILE_OUT_PTR(ti, tj)` 处理普通和 transpose 布局：

```text
normal:
  output + ti * 64 * output_stride + tj * 64 * output_elem_bytes

transpose:
  output + tj * 64 * output_stride + ti * 64 * output_elem_bytes
```

`output_elem_bytes` 很重要：

| 输出 | elem bytes |
|------|------------|
| accumulator F32/I32 | 4 |
| BF16/F16 post-op output | 2 |

因此 `_ex` API 显式接收 `output_elem_bytes`，避免 BF16 transpose 写错地址。

## Row-block Matmul

`cute_tiled_matmul_row_block_*_ex()` 用于 post-op 需要完整 N 维的场景，例如 masked softmax：

```text
每次处理 rows_per_block x N
而不是 64 x 64 tile
```

attention score softmax 需要看到一整行 score，不能只看一个 `64 x 64` tile，因此 LLaMA attention score 走 row-block matmul。

## Backward-compatible Alias

```c
cute_tiled_matmul(...)
```

当前只是 `cute_tiled_matmul_no_pipeline(...)` 的 alias，用于兼容早期测试。新代码优先使用 `_no_pipeline_ex` 或 `_pipeline_ex`，明确输出 element size。
