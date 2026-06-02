# Layer 实现

`cutelib/layer/include/cute_llama.h` 是当前 layer 层的主要实现。它把 runtime/tensor/primitive/fusion 组合成 LLaMA block，并提供可拆 stage 的内部函数。

## 文件位置

```text
cute-sdk/cutelib/layer/include/cute_llama.h
```

依赖：

```text
cute_fusion.h
cute_quant.h
```

## Config

`cute_llama_block_config_t` 包含：

| 类别 | 字段 |
|------|------|
| shape | `seq_len`、`embed_dim`、`key_dim`、`value_dim`、`n_head_q`、`n_head_kv`、`ffn_dim`、`max_ctx_len` |
| numerical | `rms_epsilon`、`kv_scale`、`use_pipeline` |
| attention norm | `attn_norm_weight` |
| QKV/O weights | `proj_q_weight`、`proj_k_weight`、`proj_v_weight`、`proj_o_weight` and scale |
| FFN norm | `ffn_norm_weight` |
| FFN weights | `ffn_gate_weight`、`ffn_up_weight`、`ffn_down_weight` and scale |
| sequence | `rope_theta`、`causal_mask` |

## Workspace

`cute_llama_block_workspace_t` 把所有中间结果显式交给调用者：

| Buffer | 类型 | 用途 |
|--------|------|------|
| `attn_norm_f32` | F32 | attention RMSNorm output |
| `attn_norm_q8` | I8 | attention projection input |
| `attn_norm_scale` | F32 per-token | attention projection scale |
| `q_bf16` | BF16 | Q projection + RoPE |
| `k_bf16` | BF16 | K projection + RoPE |
| `v_bf16_t` | BF16 | V projection transpose layout |
| `scores_bf16` | BF16 | attention softmax score |
| `attn_context_f32` | F32 | attention context |
| `attn_q8` | I8 | output projection input |
| `attn_scale` | F32 per-token | output projection scale |
| `proj_o_f32` | F32 | attention residual output |
| `ffn_norm_f32` | F32 | FFN RMSNorm output |
| `ffn_norm_q8` | I8 | FFN projection input |
| `ffn_norm_scale` | F32 per-token | FFN projection scale |
| `ffn_gate_f32` | F32 | gate projection + SiLU |
| `ffn_up_f32` | F32 | up projection + hadamard |
| `ffn_up_q8` | I8 | down projection input |
| `ffn_up_scale` | F32 per-token | down projection scale |
| `scratch0` / `scratch1` | raw | tiled matmul scratch |
| `zero_bias` | raw | bias fallback |

Workspace 外置的原因是：

- 避免 layer 内部大数组压栈。
- 允许测试直接验证任意 stage output。
- 允许 `.bss` 放大 workspace，配合当前编译器跳过 `.bss` 清零。

## Matmul Helper

### `cute_llama_matmul_post`

包装 tiled matmul：

```text
if use_pipeline:
  cute_tiled_matmul_pipeline_ex(...)
else:
  cute_tiled_matmul_no_pipeline_ex(...)
```

它负责：

- 处理 null bias，改用 `ws->zero_bias`。
- 传递 `output_elem_bytes`，支持 BF16/F32 output。
- 传递 scale、bias mode、transpose 和 post-op context。

### `cute_llama_matmul_row_post`

包装 row-block matmul：

```text
cute_tiled_matmul_row_block_*_ex(...)
```

用于 attention score softmax，因为 softmax 需要看到完整 N 维。

## QKV Projection

`cute_llama_project_qkv`：

```text
attn_norm_q8
  ↓ Q weight + dequant + RoPE + BF16
q_bf16

attn_norm_q8
  ↓ K weight + dequant + RoPE + BF16
k_bf16

attn_norm_q8
  ↓ V weight + dequant + BF16 transpose
v_bf16_t
```

Q/K 使用 `cute_post_dequant_rope_bf16cvt`。V 使用 `cute_post_dequant_bf16cvt` 且 `transpose = 1`。

## Attention

`cute_llama_attention` 分两段：

1. Q x K score：

```text
q_bf16 x k_bf16
  ↓ row-block matmul
F32 score block
  ↓ masked softmax + kv scale + BF16
scores_bf16
```

2. Score x V context：

```text
scores_bf16 x v_bf16_t
  ↓ matmul
attn_context_f32
```

当前 score stage 测试覆盖 head0，验证 BF16 softmax output。

## FFN

`cute_llama_ffn`：

```text
ffn_norm_q8 x gate_weight
  ↓ dequant + SiLU
ffn_gate_f32

ffn_norm_q8 x up_weight
  ↓ dequant + hadamard(ffn_gate_f32)
ffn_up_f32, ffn_up_scale

ffn_up_f32
  ↓ smoothquant stage2
ffn_up_q8

ffn_up_q8 x down_weight
  ↓ dequant + residual add
output
```

stage case 分别验证 gate、up、down，避免 full block 里混合多个错误来源。

## Full Block

`cute_llama_block` 组合完整路径：

```text
RMSNorm(attn)
SmoothQuant(attn)
QKV projection
Attention
SmoothQuant(context)
O projection + residual
RMSNorm(ffn)
SmoothQuant(ffn)
FFN
```

## Bias Fallback

layer helper 对 null bias 的处理：

```text
if bias == NULL or bias->data == NULL:
  use ws->zero_bias
```

这是为了满足 CUTE matmul 接口对 bias pointer 的需求，不代表要在 CPU 里初始化大 bias。当前应尽量让 `zero_bias` 指向可用的 `.bss` 区域，避免在 test 中做大规模清零。

## Stage Test 对应关系

| Layer 函数 | Stage case |
|------------|------------|
| `cute_llama_project_qkv` Q | `llama_stage_proj_q_bf16_nonzero_1b_shape_seq128` |
| `cute_llama_project_qkv` K | `llama_stage_proj_k_bf16_nonzero_1b_shape_seq128` |
| `cute_llama_project_qkv` V | `llama_stage_proj_v_bf16_nonzero_1b_shape_seq128` |
| `cute_llama_attention` score head0 | `llama_stage_score_head0_bf16_nonzero_1b_shape_seq128` |
| `cute_llama_ffn` gate | `llama_stage_ffn_gate_nonzero_1b_shape_seq128` |
| `cute_llama_ffn` up | `llama_stage_ffn_up_nonzero_1b_shape_seq128` |
| `cute_llama_ffn` down | `llama_stage_ffn_down_nonzero_1b_shape_seq128` |

这些 stage 当前全部通过 memory verify。
