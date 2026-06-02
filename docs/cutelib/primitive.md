# Primitive 实现

`cutelib/primitive` 是本轮 BF16 正确性工作的核心。它把所有 LLaMA 中可独立表达的向量计算收敛成普通 buffer API，独立于 CUTE matmul、tile scheduler 和 `cute_post_call_t`。

## 文件清单

```text
cutelib/primitive/include/
├── cute_vec_math.h
├── cute_convert.h
├── cute_elementwise.h
├── cute_sequence.h
├── cute_quant.h
└── cute_vector_fusion.h
```

## `cute_vec_math.h`

| API | 实现 |
|-----|------|
| `cute_fast_sqrt` | scalar `fsqrt.s` |
| `cute_vec_recip_approx` | `vfrec7.v` + 两轮 Newton-Raphson |
| `cute_vec_exp` | range reduction + exponent bit construction + 6 阶多项式 |
| `cute_vec_sin_small` | 小范围 sin 多项式 |
| `cute_vec_sin` | range reduction 到小范围，再恢复符号 |
| `cute_vec_cos` | `sin(x + pi/2)` |

`cute_vec_recip_approx` 用于替换热点除法。例如 SiLU fast 路径：

```text
x / (1 + exp(-x))
  ↓
x * recip_approx(1 + exp(-x))
```

这不是 bit-exact 优化，而是 correctness-with-tolerance 优化。当前 F32 tolerance 足以覆盖它带来的极小误差。

## `cute_convert.h`

| API | 语义 |
|-----|------|
| `cute_dequant_i32` | scalar `acc * input_scale * weight_scale` |
| `cute_f32m4_to_bf16m2_trunc` | F32 bit 右移 16 位，截断为 BF16 |
| `cute_f32_to_f16_tile` | F32 tile 转 F16 |
| `cute_f32_to_bf16_tile` | F32 tile 转 BF16 |
| `cute_dequant_i32_to_f32_tile` | I32 accumulator tile 转 F32 |
| `cute_dequant_i32_to_f16_tile` | I32 accumulator tile 转 F16 |
| `cute_dequant_i32_to_f16_transpose_tile` | I32 accumulator tile 转 F16 transpose layout |
| `cute_dequant_i32_to_bf16_tile` | I32 accumulator tile 转 BF16 |
| `cute_dequant_i32_to_bf16_transpose_tile` | I32 accumulator tile 转 BF16 transpose layout |

普通 dequant 路径使用 per-row input scale：

```text
scale = input_scale[row] * weight_scale[0]
```

transpose dequant 路径按当前实现读取 `input_scale[c]`，用于处理转置输出布局相关的 scale 对齐。

BF16 转换当前是 truncation，不做 round-to-nearest。memverify 因此使用 `1 ULP` 容忍。

## `cute_elementwise.h`

| API | 语义 |
|-----|------|
| `cute_silu_out_tile` | F32 input -> F32 output，使用向量除法 |
| `cute_silu_out_tile_fast` | F32 input -> F32 output，使用 reciprocal approximate |
| `cute_silu_tile` | in-place SiLU |
| `cute_silu_tile_fast` | in-place fast SiLU |
| `cute_hadamard_tile` | `output = lhs * rhs`，并更新 `row_absmax` |
| `cute_resadd_tile` | `output = lhs + rhs` |

Hadamard 的 `row_absmax` 是累积更新：

```text
row_absmax[r] = max(row_absmax[r], max(abs(lhs[r, :] * rhs[r, :])))
```

这用于 FFN up 后的 smoothquant scale。如果 N 维被拆成多个 tile，多个 tile 会共同更新同一 row 的 absmax。

## `cute_sequence.h`

| API | 语义 |
|-----|------|
| `cute_rope_f16_tile` | RoPE 后输出 F16 |
| `cute_rope_bf16_tile` | RoPE 后输出 BF16 |
| `cute_masked_softmax_f16_tile` | causal mask + scale + softmax，输出 F16 |
| `cute_masked_softmax_bf16_tile` | causal mask + scale + softmax，输出 BF16 |

RoPE 实现：

```text
for each row:
  pos_r = pos + row
  angle = rope_theta[k] * pos_r
  real_out = real * cos(angle) - imag * sin(angle)
  imag_out = real * sin(angle) + imag * cos(angle)
  store [real half..., imag half...]
```

Masked softmax 实现：

```text
1. apply kv scale and causal mask
2. row max reduction
3. exp(x - max)
4. row sum reduction
5. normalize and convert to F16/BF16
```

mask 使用 bitmask 读取，`mask_stride = (max_ctx_len + 7) / 8`。

## `cute_quant.h`

| API | 语义 |
|-----|------|
| `cute_primitive_smoothquant_stage1_getscale_impl` | 每 row 计算 `absmax / 127` |
| `cute_primitive_smoothquant_stage2_quant_impl` | F32 按 per-row scale 量化到 I8 |
| `cute_smoothquant` | 可选 stage1 + stage2 |
| `cute_rmsnorm` | RMSNorm |
| `cute_rmsnorm_with_scale` | RMSNorm 并生成 per-token scale |

`cute_rmsnorm_with_scale` 做两件事：

```text
output = input * rsqrt(mean(input^2) + eps) * weight
per_token_scale = max(abs(output[row])) / 127
```

这个 scale 后续供 INT8 projection 使用。

## `cute_vector_fusion.h`

pure vector fusion API 是 primitive 层的组合接口：

| API | 调用链 |
|-----|--------|
| `cute_fuse_dequant_rope_bf16cvt_tile` | dequant_i32_to_f32 -> rope_bf16 |
| `cute_fuse_dequant_bf16cvt_tile` | dequant_i32_to_bf16 |
| `cute_fuse_dequant_bf16cvt_transpose_tile` | dequant_i32_to_bf16_transpose |
| `cute_fuse_masked_softmax_kvscale_bf16cvt_tile` | masked_softmax_bf16 |
| `cute_fuse_dequant_silu_tile` | dequant_i32_to_f32 -> silu_fast |
| `cute_fuse_dequant_hadamard_tile` | dequant_i32_to_f32 -> hadamard |
| `cute_fuse_dequant_resadd_tile` | dequant_i32_to_f32 -> resadd |

context struct：

| Struct | 字段 |
|--------|------|
| `cute_rope_ctx_t` | `pos`、`rope_theta`、`key_dim` |
| `cute_softmax_ctx_t` | `pos`、`bitmask`、`max_ctx_len`、`kv_scale` |
| `cute_resadd_ctx_t` | `residual`、`residual_stride` |
| `cute_hadamard_ctx_t` | `lhs`、`lhs_stride`、`output_absmax` |

## 实现边界

primitive 层必须保持：

| 要求 | 原因 |
|------|------|
| 只接普通指针、stride、shape、scale | 便于独立测试 |
| 不接 `cute_post_call_t` | 避免依赖 tensor scheduler |
| 不 issue CUTE matmul | primitive 只是向量计算 |
| 不做 case-specific memory compare | correctness 交给 host memverify |
| 不读取 LLaMA 全局变量 | 允许 layer / fusion 复用 |

## 测试覆盖

primitive 和 vector fusion 分别由：

```text
cute-sdk/tests/vecprimitive.yaml
cute-sdk/tests/vecfusion.yaml
```

覆盖。每个 case 都有独立 `case.json`、`test.c` 和 golden manifest。
