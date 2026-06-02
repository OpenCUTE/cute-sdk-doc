# 概念对齐

这页的目标是把 CUTE SDK 里的术语，先对齐到大家熟悉的知识领域。第一次接触 CUTE 的人，不需要先背所有缩写，更重要的是先知道“这玩意大概像什么”。

## CUTE 是什么

可以先把 CUTE 粗略理解成：

- 一块专门做张量计算的硬件加速器。
- 一套围绕这块加速器的软硬件接口。
- 一套用于验证这块加速器是否算对了的开发流程。

如果类比 GPU 生态：

| GPU 世界 | CUTE 世界 |
|----------|-----------|
| GPU 硬件 | CUTE accelerator |
| CUDA 指令 / runtime API | `instruction.h` + `cutelib/runtime` |
| cuBLAS / cuDNN 这类算子封装 | `cutelib/tensor` / `cutelib/layer` |
| epilogue / activation fusion | `cutelib/fusion` |
| 自定义后处理 kernel | `cutelib/primitive` |

## `cutelib` 是什么

`cutelib` 可以看成“给 CUTE 写程序时用的库函数集合”。

它分层的原因，和很多熟悉的软件栈一样：

- 最底层先把硬件指令包装成人能用的函数。
- 再往上一层把单次 matmul 包装成 tensor 级接口。
- 再往上一层把 activation、RoPE、RMSNorm 这种通用向量逻辑做成可复用 primitive。
- 再把 matmul 输出接这些 primitive，形成 fusion。
- 最后把它们拼成一个 LLaMA block。

## Golden 是什么

`golden` 可以理解成“参考答案”。

如果你熟悉：

- NumPy reference
- PyTorch eager output
- 单元测试里的 expected array

那么 `golden/manual/*/manifest.json + *.bin` 就是这个角色。

它回答的问题是：

```text
这组输入、这组权重、这条算子路径，正确输出应该是什么？
```

## Memverify 是什么

`memverify` 不是再跑一遍算子，而是：

1. 读取仿真产生的 trace。
2. 从 trace 里把硬件写过的内存重建出来。
3. 取出某个输出地址范围。
4. 和 golden 做比较。

如果你熟悉软件测试，它更像：

```text
assert array_equal(...)
assert allclose(...)
```

只不过这里的 `actual` 不是程序直接返回的数组，而是从硬件 trace 里重建出来的 memory。

## Trace 是什么

`run.out` 不是“日志文本”，更像“压缩后的行为记录”。

里面记录了：

- 哪个周期发生了 store。
- store 写到了哪个虚拟地址。
- 写了什么数据。

所以它像是：

- 软件里的执行 trace。
- 硬件里的 transaction log。
- 但不是完整波形，也不是直接可读的最终数组。

要靠 memverify 把它还原成真正的输出内存。

## Suite YAML 是什么

如果你熟悉：

- `pytest -k ...`
- Bazel test target list
- CI workflow 里的 job matrix

那么 `tests/*.yaml` 就是在做这件事：描述一组 case 要怎么一起跑。

它负责：

- 指定 `hwconfig`
- 指定并行度
- 指定默认 timeout
- 列出要跑的 case

## `case.json` 是什么

如果 suite YAML 是“测试清单”，那么 `case.json` 就是“单个测试的 manifest”。

它描述：

- 这个 case 怎么编译。
- 跑完后用哪份 golden。
- 去 ELF 的哪个 symbol 找输出。
- 用 bit exact 还是 tolerance compare。

## BF16 tolerance 为什么重要

很多新人会下意识觉得：

```text
硬件输出 = 参考输出
```

应该 bit 完全一致。

但对 BF16 和近似数学路径，这通常不现实，也没有必要。因为：

- BF16 本身有效位少，1 ULP 差异很常见。
- 向量近似 `exp/sin/cos/reciprocal` 会引入很小的数值误差。

所以当前验证策略是：

| 类型 | 规则 |
|------|------|
| F32 | `0.05%` relative tolerance |
| BF16 | `0.5%` relative tolerance + `1 ULP` |

这样检查的是“数值是否正确”，而不是“编码位是否一模一样”。
