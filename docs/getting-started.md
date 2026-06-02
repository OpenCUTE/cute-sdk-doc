# 跑通第一组测试

第一次上手时，最重要的不是看懂所有实现，而是先跑通一组你能解释清楚的测试。

推荐从 `vecprimitive.yaml` 开始，因为它：

- case 小。
- 覆盖的是常见向量算子。
- 出问题时定位最直接。

## 准备工作

默认工作目录：

```bash
cd /root/opencute/CUTE
```

先记住三件事：

1. `cute-sdk/tests/*.yaml` 是 suite。
2. `tools/runner/cute-test.py` 是统一测试入口。
3. pass/fail 主要靠 host 端 `memverify` 判断，不是设备侧自己大规模比较。

## 第一次跑什么

建议先跑：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/vecprimitive.yaml \
  --skip-build
```

如果还没构建过 binary，可以先去掉 `--skip-build`。

## 正常应该看到什么

正常情况下会看到这样的结构：

```text
Suite: vecprimitive.yaml
  hwconfig: ...
  cases: ...
  parallel: ...

[CHECK] all case.json valid
[BUILD] skipped ...
[RELOC] resolving symbols...
[case] PASS
...
13/13 passed
```

这说明：

- case.json 格式没问题。
- ELF 能找到对应 symbol。
- 仿真完成了。
- 输出 memory 和 golden 对上了。

## 如果已经有 trace

如果某个 suite 很慢，但你知道它之前已经完整跑出过 trace，可以只做 verify：

```bash
python3 tools/runner/cute-test.py \
  --suite cute-sdk/tests/llama_layer_nonzero_stages.yaml \
  --skip-build \
  --skip-run
```

这个模式适合：

- 调 tolerance。
- 改 memverify。
- 检查 case.json / symbol / manifest 是否绑定正确。
