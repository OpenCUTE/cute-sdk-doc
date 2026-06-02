# Golden 与 Memverify

这页可以看成是在回答一句话：

```text
我们到底是怎么知道“硬件算对了”的？
```

当前 SDK 的正确性验证以 host 端 `memverify` 为中心。Verilator 只负责跑程序和产生 compact trace；`memverify` 负责从 trace 重建 memory，然后和 golden tensor 比较。

## Golden 是什么

可以先把 `golden` 理解成“参考答案”。

如果你更习惯软件侧的说法，它就像：

- NumPy / PyTorch 参考输出
- 单元测试里的 expected tensor
- 回归测试里的 baseline data

所以这里的核心问题是：

```text
在这组输入、这组权重、这条算子路径下，正确输出应该是什么？
```

`golden/manual/*` 目录就是在回答这个问题。

## Golden 怎么组织

常见布局：

```text
golden/manual/
├── tensor/
├── vector/
├── fusion/
├── layer/
└── generators/
```

一个 golden 目录里通常有：

| 文件 | 作用 |
|------|------|
| `manifest.json` | 描述有哪些 tensor、它们的 dtype / shape / 文件路径 |
| `*.bin` | 真正的二进制数据 |
| `*.h` | 测试侧 include 的声明、指针或小规模常量 |

这里的习惯是：

- 大数据尽量放 `.bin`
- `.h` 只放声明和轻量入口

这样既减少编译负担，也避免把大数组直接塞进 C 源码。

## Memverify 在干什么

很多新人第一次听到 `memverify` 会以为它是在“再跑一遍算法”。其实不是。

它做的是：

1. 读取 `run.out`。
2. 找出其中的 store event。
3. 按地址把硬件写过的 memory 重建出来。
4. 从某个 symbol 对应的地址范围切出输出 tensor。
5. 和 golden 做比较。

所以 `memverify` 更像：

```text
host 端的 assert array_equal / assert allclose
```

只是这里的 `actual` 不是程序直接返回值，而是从硬件 trace 里还原出来的 memory。

## 为什么要走 trace，而不是设备侧自己比较

因为大规模 compare 放在仿真里做很慢。

当前策略是：

- 设备侧代码只负责把结果写出来。
- host 端用 trace 重建结果并做 compare。

这样做的好处：

- 仿真时间不会被大规模 compare 吃掉。
- trace 一旦完整，很多验证可以重复在 host 上跑。
- fail 时能拿到更清晰的 mismatch 信息。

## Compare 有哪几种

最常见的是两层：

1. bit exact compare
2. float tolerance compare

bit exact 很直观：

```text
每个字节都一样
```

float tolerance 更接近数值计算世界里的常见判断：

```text
虽然 bit 不完全一样，但数值误差在允许范围内
```

## 为什么 BF16 不能死磕 bit exact

对 BF16 来说，bit exact 不是总能说明问题。

因为：

- BF16 有效位少。
- 1 ULP 差异很常见。
- 在小数值附近，1 ULP 的相对误差可能已经超过一个很紧的 percent 阈值。

所以当前策略是：

| 类型 | 验证规则 |
|------|----------|
| F32 | `0.05%` relative tolerance |
| BF16 | `0.5%` relative tolerance + `1 ULP` |

这更接近我们真正关心的东西：

```text
数值有没有算对
```

而不是：

```text
编码位有没有完全一样
```

## 当前一个很典型的例子

在 `llama_layer_nonzero_stages.yaml` 里：

- Q BF16 是 bit exact pass
- K BF16 是 bit exact fail，但 tolerance pass，`max ULP = 1`
- score head0 BF16 也是 tolerance pass，`max ULP = 1`

这就是一个很典型的“bit 不完全一样，但数值上完全合理”的例子。

## 看 mismatch 时先别慌

看到 mismatch，不要第一时间就下结论“硬件错了”。

先问自己三个问题：

1. trace 完整了吗，也就是 `run.log` 里有 `$finish` 吗？
2. 这个输出类型是 F32 还是 BF16？
3. 当前 compare 是 bit exact fail 还是 tolerance 也 fail？

只有当：

- trace 完整
- symbol / manifest 绑定正确
- tolerance compare 也 fail

这时才更像是真正的 correctness 问题。
