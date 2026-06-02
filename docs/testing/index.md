# 测试组织

如果把 `cutelib` 看成“我们写给 CUTE 硬件调用的代码”，那么 `tests/` 就是“我们证明这些代码确实算对了的地方”。

第一次接触这套测试时，最容易混淆三件事：

1. suite YAML 是什么。
2. `case.json` 是什么。
3. `test.c` 到底负责什么，`memverify` 又负责什么。

这页先把这三个概念理顺。

## 一条测试里有哪些角色

可以先用软件测试里更熟悉的类比来理解：

| CUTE 里的东西 | 更像什么 |
|---------------|----------|
| `test.c` | 被执行的测试程序 |
| `case.json` | 单个测试的配置文件 |
| suite YAML | 一组测试的清单 |
| golden | 参考输出 |
| `run.out` | 运行后的行为记录 |
| `memverify` | host 端的 `assert array_equal/allclose` |

## `tests/` 目录怎么分

```text
cute-sdk/tests/
├── runtime/        # 最底层 runtime 包装
├── tensor/         # tiled matmul / tensor 级接口
├── primitive/      # 单个向量算子和纯向量 fuse
├── fusion/         # matmul + post-op adapter
├── layer/          # LLaMA block / stage
├── smoke.yaml
├── vecprimitive.yaml
├── vecfusion.yaml
├── fusion.yaml
├── fusion_attention.yaml
├── fusion_llama_layout.yaml
├── llama_layer.yaml
├── llama_layer_full.yaml
├── llama_layer_nonzero_full.yaml
└── llama_layer_nonzero_stages.yaml
```

最简单的理解是：

- `runtime/primitive/fusion/layer` 这些子目录存“单个 case”。
- 根目录下的 `*.yaml` 存“要把哪些 case 一起跑”。

## 单个 Case 目录长什么样

最常见的是这样：

```text
tests/primitive/primitive_silu_m128_n128/
├── case.json
└── test.c
```

这里：

- `test.c` 负责准备输入、调用 `cutelib`、等硬件跑完。
- `case.json` 负责告诉 runner：
  - 这个 case 怎么编译
  - 用哪份 golden
  - 去哪个 symbol 取输出
  - 用什么 compare 规则

如果是 fusion case，会多几个 source 文件，因为我们想比较不同调度方式：

```text
tests/fusion/fusion_matmul_dequant_silu/
├── case.json
├── test_notile.c
├── test_nopipeline.c
└── test_pipeline.c
```

## `test.c` 负责什么，不负责什么

很多新人第一次看这套测试，会默认以为：

```text
test.c 会在设备侧自己比对结果
```

实际上这里不是这个思路。

`test.c` 主要负责：

- 准备输入 / 输出 buffer
- 调用 `cutelib` API
- 让硬件把结果写到目标地址

`test.c` 通常不负责：

- 在设备侧逐元素对比整个输出
- 输出一大堆数值结果供人工检查

因为大规模 compare 放在 Verilator 里做会很慢。我们更希望：

- 设备侧只把真实结果写出来
- host 端再根据 trace 做正确性判断

## `case.json` 是单个测试的说明书

普通 case 的结构可以先这样理解：

```json
{
  "id": "primitive_silu_m128_n128",
  "build": {
    "source": "test.c"
  },
  "run": {
    "hwconfig": "..."
  },
  "golden": "golden/manual/vector/silu_m128_n128/manifest.json",
  "verify": {
    "mode": "return_code_and_bit_exact",
    "tensors": [
      {
        "tensor": "golden_silu_golden_y",
        "symbol": "output"
      }
    ]
  }
}
```

你可以把它当成“单测配置文件”：

- `build`：怎么编译
- `run`：怎么跑
- `golden`：参考答案在哪里
- `verify`：怎么判 pass/fail

## suite YAML 是一组 case 的清单

例如：

```yaml
hwconfig: cute4tops_shuttle512_d512_v512_m512_sysbus512_membus1_core_dramsim48
build: false
parallel: 12
timeout_seconds: 1200
cases:
  - primitive_vec_math_n256
  - primitive_dequant_f32_m64_n64
  - primitive_dequant_f16_m64_n64
  - primitive_silu_m128_n128
```

suite YAML 解决的是“这一组测试怎么一起跑”的问题：

- 用哪个 `hwconfig`
- 并发几个
- 默认超时多久
- 包含哪些 case

## Variant 是什么

fusion case 常常不是一个 binary，而是多个“同一个算子、不同调度方式”的 binary：

```text
notile
nopipeline
pipeline
```

这时候 suite YAML 里只写：

```yaml
cases:
  - fusion_matmul_dequant_silu
```

runner 会自动展开成三条 case：

```text
fusion_matmul_dequant_silu:notile
fusion_matmul_dequant_silu:nopipeline
fusion_matmul_dequant_silu:pipeline
```

## Verify 是怎么判定 PASS 的

最关键的是 `verify.mode`：

| mode | 含义 |
|------|------|
| `return_code` | 只要求程序完整跑完 |
| `bit_exact` | 只比较输出 memory |
| `return_code_and_bit_exact` | 既要跑完，也要 compare 通过 |

而 compare 本身又可能分成两层：

1. bit exact compare
2. float tolerance compare

对 F32 和 BF16，我们当前更关心“数值是否正确”，不一味要求“每个 bit 完全一样”。
