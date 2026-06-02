# Runner

`tools/runner/cute-test.py` 是当前 SDK 测试的统一入口。可以先把它理解成：

```text
一个把“测试清单、单个 case、仿真运行、结果验证”串起来的总调度器
```

如果你熟悉软件工程里的说法，它有点像：

- 一个轻量 test runner
- 再加上一层 build orchestration
- 再加上一层 trace-based verify glue

## 它负责什么

runner 主要做这些事：

1. 读取 suite YAML。
2. 读取每个 case 的 `case.json`。
3. 如果 case 有 variant，就自动展开。
4. 找到对应 ELF。
5. 调 `cute-run.py` 启动 Verilator。
6. 调 memverify 做正确性检查。

所以它解决的是“怎么把一组测试完整跑起来”的问题，而不是“某个算子数学上怎么实现”的问题。

## 最常见的命令

```bash
cd /root/opencute/CUTE

python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/vecprimitive.yaml
```

常用参数：

| 参数 | 作用 |
|------|------|
| `--suite` | 指定 suite YAML |
| `--hwconfig` | 覆盖 suite 中的硬件配置 |
| `--parallel` | 覆盖 suite 中的并行数 |
| `--skip-build` | 跳过构建 |
| `--skip-run` | 跳过 Verilator，只验证已有 trace |

## 它怎么理解 case

runner 会先看 suite YAML，然后去读每个 case 对应的 `case.json`。

如果是普通 case，它只会找到一个 binary。

如果是 fusion case，它可能会自动展开成多个 variant，例如：

```text
fusion_matmul_dequant_silu
  ↓
fusion_matmul_dequant_silu:notile
fusion_matmul_dequant_silu:nopipeline
fusion_matmul_dequant_silu:pipeline
```

这和很多熟悉的 CI matrix 很像：逻辑上是一类 case，运行时展开成多个具体变体。

## `--skip-run` 是干什么的

`--skip-run` 的含义不是“假装测试通过”，而是：

```text
不重新跑仿真，只拿已有 trace 重新做 verify
```

典型用法：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/llama_layer_nonzero_stages.yaml \
  --skip-build \
  --skip-run
```

它特别适合：

- Verilator 很慢，不想重复跑。
- 你刚改了 memverify。
- 你刚调了 tolerance。
- 你只想确认 golden / symbol / manifest 是否绑定正确。

## 为什么 `--skip-run` 还要检查 `$finish`

runner 不会盲信一个 `run.out` 文件存在就说明测试完成。

它还会检查 `run.log` 里有没有：

```text
Verilog $finish
```

如果没有，runner 会把它判成：

```text
existing trace is incomplete
```

这是为了防止大家拿半截 trace 去判断 correctness。对慢 case 来说，这个保护非常重要。

## Trace Progress

`tools/runner/cute-trace-symbols.py` 用于观察 compact trace 中 store 地址落在哪些 ELF symbol 区间：

```bash
python3 tools/runner/cute-trace-symbols.py \
  --elf cute-sdk/build/layer/llama_stage_ffn_gate_nonzero_1b_shape_seq128.riscv \
  --trace build/chipyard_runs/<hwconfig>/llama_stage_ffn_gate_nonzero_1b_shape_seq128/run.out \
  --top 16 \
  --symbol output
```

这个脚本适合回答：

- 仿真还在写哪里。
- 当前是否已经写到 output 末尾附近。
- 是不是卡在 scratch 或 stack 一类区域。

## 结果怎么看

最常见的三种结果：

| 输出 | 含义 |
|------|------|
| `PASS` | 正确性通过 |
| `existing trace is incomplete` | 还不能判断，trace 没跑完 |
| `bit-exact failed; float tolerance passed` | 数值正确，但不是字节级完全一致 |

如果你第一次看 runner 输出，最重要的是先区分这三种情况，不要把它们混成一种“都算 fail/都算 pass”。

## 当前它已经支持什么

runner 当前支持：

- runtime / tensor / primitive / fusion / layer case 搜索
- `case.json` 基础校验
- suite-level 和 case-level timeout
- fusion build variants
- 多 tensor verify
- `float_tolerance_percent` 和 `float_tolerance_ulp`
- `--skip-run` trace-only verify

它不负责：

- 在设备侧做大规模正确性比较
- 对半截 trace 做 best-effort compare
- 自动帮你推断哪种 tolerance 才合理
