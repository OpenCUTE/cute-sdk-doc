# 一个 Case 的完整旅程

理解 CUTE SDK 的最好方式，不是先背目录，而是顺着一条测试走一遍。

下面用一个普通 case 的视角，把从 `test.c` 到最终 `PASS` 的过程串起来。

## 第 1 步：`test.c` 发起计算

在 `tests/**/test.c` 里，设备侧代码通常只做这些事：

- 准备输入 / 权重 / 输出指针。
- 调用 `cutelib` API。
- 等待 CUTE 完成。

它通常不会在设备侧自己做大规模正确性比较。

## 第 2 步：`case.json` 告诉 runner 怎么理解这个 case

`case.json` 负责回答四个问题：

1. 用哪个 `test.c` 编译 ELF。
2. 用哪份 golden 当参考答案。
3. 去 ELF 的哪个 symbol 找输出 buffer。
4. 用什么 compare 规则判定 pass/fail。

所以 `test.c` 是“干活的人”，`case.json` 是“说明书”。

## 第 3 步：suite YAML 决定这条 case 什么时候、和谁一起跑

suite YAML 负责：

- 指定硬件配置。
- 指定并行度。
- 指定 timeout。
- 指定哪些 case 一起跑。

所以：

- `case.json` 管单个 case。
- suite YAML 管一组 case。

## 第 4 步：runner 找到 ELF、跑仿真

`tools/runner/cute-test.py` 会：

1. 读取 suite YAML。
2. 读取各个 case.json。
3. 如有必要，展开 fusion variants。
4. 找到对应 ELF。
5. 调 `cute-run.py` 启动仿真。

仿真目录通常在：

```text
build/chipyard_runs/<hwconfig>/<case_name>/
```

里面最关键的是两个文件：

| 文件 | 作用 |
|------|------|
| `run.log` | 是否 `$finish`、是否运行完整 |
| `run.out` | compact trace，后续给 memverify 用 |

## 第 5 步：trace 被还原成输出内存

仿真完成后，runner 不会直接说“算对了”。它会把 `run.out` 交给 memverify。

memverify 会：

1. 解析 compact trace。
2. 提取 store event。
3. 按虚拟地址重建内存内容。
4. 从 `symbol` 对应的 base address 开始切出输出 tensor。

这一层很重要，因为 CUTE 的“结果”最终体现在 memory 里，不是某个函数返回值里。

## 第 6 步：golden compare

从 trace 重建出的输出，会和 golden manifest 指向的 tensor 比较。

比较有两种常见结果：

- `bit exact pass`
- `bit-exact failed; float tolerance passed`

对 BF16 和近似数学路径来说，第二种结果完全可能是正常的。

## 第 7 步：runner 汇总为 PASS / FAIL

最终你在终端看到的是 runner 的汇总：

```text
[case] PASS
...
N/N passed
```

或者：

```text
existing trace is incomplete
```

或者：

```text
bit-exact failed; float tolerance passed
```

这三种输出含义完全不同：

| 输出 | 含义 |
|------|------|
| `PASS` | 正确性通过 |
| `incomplete trace` | 还不能判断，trace 没跑完 |
| `bit-exact failed; tolerance passed` | 数值正确，但不是字节级完全一致 |
